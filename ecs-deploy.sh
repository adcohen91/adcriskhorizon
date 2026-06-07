#!/usr/bin/env bash
# ECS deployment script for adcriskhorizon.com
# Run: bash ecs-deploy.sh

set -euo pipefail

AWS_PROFILE="adcriskhorizon"
AWS_REGION="us-east-1"
ACCOUNT_ID="968246765001"
APP="adcriskhorizon"
ECR_REPO="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${APP}"
CLUSTER="${APP}-cluster"
SERVICE="${APP}-service"
TASK_FAMILY="${APP}-task"
VPC_ID="vpc-0ab23a48b7fa1c9b5"
SUBNETS="subnet-0e54d1c1bccc06255,subnet-04dcf7acb84b25b8f,subnet-085b6b645edb97d80,subnet-0a5551c33119404c4"
CERT_ARN="arn:aws:acm:us-east-1:968246765001:certificate/b7d2c471-6e3f-43d1-b2c6-4a27b65722d7"

echo "=== ADC Risk Horizon — ECS Deployment ==="

# ── 1. ECR: create repo if needed ──────────────────────────────────────────
echo ""
echo "[1/8] Creating ECR repository..."
aws ecr create-repository --repository-name "${APP}" \
  --image-scanning-configuration scanOnPush=true \
  --region "${AWS_REGION}" --profile "${AWS_PROFILE}" 2>/dev/null || echo "  (repository already exists)"

# ── 2. Docker build & push ─────────────────────────────────────────────────
echo ""
echo "[2/8] Authenticating Docker with ECR..."
aws ecr get-login-password --region "${AWS_REGION}" --profile "${AWS_PROFILE}" \
  | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo ""
echo "[3/8] Building and pushing Docker image..."
docker build -t "${APP}:latest" .
docker tag "${APP}:latest" "${ECR_REPO}:latest"
docker push "${ECR_REPO}:latest"

IMAGE_URI="${ECR_REPO}:latest"
echo "  Image pushed: ${IMAGE_URI}"

# ── 3. ECS Task Execution Role ─────────────────────────────────────────────
echo ""
echo "[4/8] Creating ECS task execution role..."
TRUST_POLICY='{
  "Version":"2012-10-17",
  "Statement":[{
    "Effect":"Allow",
    "Principal":{"Service":"ecs-tasks.amazonaws.com"},
    "Action":"sts:AssumeRole"
  }]
}'

EXEC_ROLE_ARN=$(aws iam create-role \
  --role-name "${APP}-ecs-exec-role" \
  --assume-role-policy-document "${TRUST_POLICY}" \
  --query 'Role.Arn' --output text \
  --profile "${AWS_PROFILE}" 2>/dev/null) || \
EXEC_ROLE_ARN=$(aws iam get-role --role-name "${APP}-ecs-exec-role" \
  --query 'Role.Arn' --output text --profile "${AWS_PROFILE}")

aws iam attach-role-policy \
  --role-name "${APP}-ecs-exec-role" \
  --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" \
  --profile "${AWS_PROFILE}" 2>/dev/null || true

echo "  Execution role: ${EXEC_ROLE_ARN}"

# ── 4. ECS Cluster ─────────────────────────────────────────────────────────
echo ""
echo "[5/8] Creating ECS Fargate cluster..."
aws ecs create-cluster \
  --cluster-name "${CLUSTER}" \
  --capacity-providers FARGATE \
  --region "${AWS_REGION}" --profile "${AWS_PROFILE}" 2>/dev/null || echo "  (cluster already exists)"

# ── 5. Security Groups ─────────────────────────────────────────────────────
echo ""
echo "[6/8] Creating security groups..."

ALB_SG=$(aws ec2 create-security-group \
  --group-name "${APP}-alb-sg" \
  --description "ALB for adcriskhorizon" \
  --vpc-id "${VPC_ID}" \
  --query 'GroupId' --output text \
  --region "${AWS_REGION}" --profile "${AWS_PROFILE}" 2>/dev/null) || \
ALB_SG=$(aws ec2 describe-security-groups \
  --filters Name=group-name,Values="${APP}-alb-sg" Name=vpc-id,Values="${VPC_ID}" \
  --query 'SecurityGroups[0].GroupId' --output text \
  --region "${AWS_REGION}" --profile "${AWS_PROFILE}")

aws ec2 authorize-security-group-ingress --group-id "${ALB_SG}" --protocol tcp --port 80 --cidr 0.0.0.0/0 --region "${AWS_REGION}" --profile "${AWS_PROFILE}" 2>/dev/null || true
aws ec2 authorize-security-group-ingress --group-id "${ALB_SG}" --protocol tcp --port 443 --cidr 0.0.0.0/0 --region "${AWS_REGION}" --profile "${AWS_PROFILE}" 2>/dev/null || true

ECS_SG=$(aws ec2 create-security-group \
  --group-name "${APP}-ecs-sg" \
  --description "ECS tasks for adcriskhorizon" \
  --vpc-id "${VPC_ID}" \
  --query 'GroupId' --output text \
  --region "${AWS_REGION}" --profile "${AWS_PROFILE}" 2>/dev/null) || \
ECS_SG=$(aws ec2 describe-security-groups \
  --filters Name=group-name,Values="${APP}-ecs-sg" Name=vpc-id,Values="${VPC_ID}" \
  --query 'SecurityGroups[0].GroupId' --output text \
  --region "${AWS_REGION}" --profile "${AWS_PROFILE}")

aws ec2 authorize-security-group-ingress --group-id "${ECS_SG}" --protocol tcp --port 80 --source-group "${ALB_SG}" --region "${AWS_REGION}" --profile "${AWS_PROFILE}" 2>/dev/null || true

echo "  ALB SG: ${ALB_SG}  |  ECS SG: ${ECS_SG}"

# ── 6. ALB + Target Group ──────────────────────────────────────────────────
echo ""
echo "[7/8] Creating Application Load Balancer..."
SUBNET_LIST=$(echo "${SUBNETS}" | tr ',' ' ')

ALB_ARN=$(aws elbv2 create-load-balancer \
  --name "${APP}-alb" \
  --subnets ${SUBNET_LIST} \
  --security-groups "${ALB_SG}" \
  --scheme internet-facing \
  --type application \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text \
  --region "${AWS_REGION}" --profile "${AWS_PROFILE}" 2>/dev/null) || \
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --names "${APP}-alb" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text \
  --region "${AWS_REGION}" --profile "${AWS_PROFILE}")

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns "${ALB_ARN}" \
  --query 'LoadBalancers[0].DNSName' --output text \
  --region "${AWS_REGION}" --profile "${AWS_PROFILE}")

TG_ARN=$(aws elbv2 create-target-group \
  --name "${APP}-tg" \
  --protocol HTTP --port 80 \
  --vpc-id "${VPC_ID}" \
  --target-type ip \
  --health-check-path /health \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 2 \
  --query 'TargetGroups[0].TargetGroupArn' --output text \
  --region "${AWS_REGION}" --profile "${AWS_PROFILE}" 2>/dev/null) || \
TG_ARN=$(aws elbv2 describe-target-groups \
  --names "${APP}-tg" \
  --query 'TargetGroups[0].TargetGroupArn' --output text \
  --region "${AWS_REGION}" --profile "${AWS_PROFILE}")

# HTTP listener → redirect to HTTPS
aws elbv2 create-listener \
  --load-balancer-arn "${ALB_ARN}" \
  --protocol HTTP --port 80 \
  --default-actions "Type=redirect,RedirectConfig={Protocol=HTTPS,Port=443,StatusCode=HTTP_301}" \
  --region "${AWS_REGION}" --profile "${AWS_PROFILE}" 2>/dev/null || true

# HTTPS listener → forward to target group
aws elbv2 create-listener \
  --load-balancer-arn "${ALB_ARN}" \
  --protocol HTTPS --port 443 \
  --ssl-policy ELBSecurityPolicy-TLS13-1-2-2021-06 \
  --certificates "CertificateArn=${CERT_ARN}" \
  --default-actions "Type=forward,TargetGroupArn=${TG_ARN}" \
  --region "${AWS_REGION}" --profile "${AWS_PROFILE}" 2>/dev/null || true

echo "  ALB DNS: ${ALB_DNS}"

# ── 7. ECS Task Definition ─────────────────────────────────────────────────
echo ""
echo "[8/8] Registering task definition and creating service..."

TASK_DEF=$(cat <<EOF
{
  "family": "${TASK_FAMILY}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "${EXEC_ROLE_ARN}",
  "containerDefinitions": [{
    "name": "${APP}",
    "image": "${IMAGE_URI}",
    "portMappings": [{"containerPort": 80, "protocol": "tcp"}],
    "essential": true,
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/${APP}",
        "awslogs-region": "${AWS_REGION}",
        "awslogs-stream-prefix": "ecs",
        "awslogs-create-group": "true"
      }
    }
  }]
}
EOF
)

TASK_ARN=$(aws ecs register-task-definition \
  --cli-input-json "${TASK_DEF}" \
  --query 'taskDefinition.taskDefinitionArn' --output text \
  --region "${AWS_REGION}" --profile "${AWS_PROFILE}")

echo "  Task definition: ${TASK_ARN}"

# Create or update service
SERVICE_EXISTS=$(aws ecs describe-services \
  --cluster "${CLUSTER}" --services "${SERVICE}" \
  --query 'services[0].status' --output text \
  --region "${AWS_REGION}" --profile "${AWS_PROFILE}" 2>/dev/null || echo "MISSING")

if [ "${SERVICE_EXISTS}" = "ACTIVE" ]; then
  echo "  Updating existing ECS service..."
  aws ecs update-service \
    --cluster "${CLUSTER}" \
    --service "${SERVICE}" \
    --task-definition "${TASK_ARN}" \
    --desired-count 1 \
    --force-new-deployment \
    --region "${AWS_REGION}" --profile "${AWS_PROFILE}" > /dev/null
else
  echo "  Creating ECS service..."
  aws ecs create-service \
    --cluster "${CLUSTER}" \
    --service-name "${SERVICE}" \
    --task-definition "${TASK_ARN}" \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[${SUBNETS}],securityGroups=[${ECS_SG}],assignPublicIp=ENABLED}" \
    --load-balancers "targetGroupArn=${TG_ARN},containerName=${APP},containerPort=80" \
    --region "${AWS_REGION}" --profile "${AWS_PROFILE}" > /dev/null
fi

# ── Done ───────────────────────────────────────────────────────────────────
echo ""
echo "=============================================="
echo "  Deployment complete!"
echo "  ALB DNS:  ${ALB_DNS}"
echo ""
echo "  Next: point Route 53 A record to the ALB."
echo "  ALB hosted zone: check with:"
echo "  aws elbv2 describe-load-balancers --names ${APP}-alb --profile ${AWS_PROFILE}"
echo "=============================================="
