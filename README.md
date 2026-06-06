# ADC Risk Horizon — adcriskhorizon.com

Business consulting website hosted on AWS S3 + CloudFront, deployed via GitHub Actions.

## Stack

| Layer       | Service                        |
|-------------|-------------------------------|
| Hosting     | AWS S3 (static website)       |
| CDN / HTTPS | AWS CloudFront                |
| DNS         | AWS Route 53                  |
| SSL Cert    | AWS Certificate Manager (ACM) |
| CI/CD       | GitHub Actions                |

---

## First-Time AWS Setup

### 1. Create S3 Bucket

```bash
aws s3api create-bucket \
  --bucket adcriskhorizon.com \
  --region us-east-1

# Enable static website hosting
aws s3 website s3://adcriskhorizon.com \
  --index-document index.html \
  --error-document index.html

# Set bucket policy for public read
aws s3api put-bucket-policy \
  --bucket adcriskhorizon.com \
  --policy '{
    "Version": "2012-10-17",
    "Statement": [{
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::adcriskhorizon.com/*"
    }]
  }'
```

### 2. Request SSL Certificate (ACM)

> Must be in **us-east-1** for CloudFront.

```bash
aws acm request-certificate \
  --domain-name adcriskhorizon.com \
  --subject-alternative-names www.adcriskhorizon.com \
  --validation-method DNS \
  --region us-east-1
```

Add the DNS validation CNAME records to Route 53, then wait for status = ISSUED.

### 3. Create CloudFront Distribution

In the AWS Console:
- **Origin domain**: your S3 bucket website endpoint (e.g. `adcriskhorizon.com.s3-website-us-east-1.amazonaws.com`)
- **Viewer protocol policy**: Redirect HTTP to HTTPS
- **Alternate domain names (CNAMEs)**: `adcriskhorizon.com`, `www.adcriskhorizon.com`
- **SSL certificate**: select the ACM cert from step 2
- **Default root object**: `index.html`

Note the **Distribution ID** — you'll need it for GitHub secrets.

### 4. Route 53 DNS Records

In your `adcriskhorizon.com` hosted zone, add:

| Type  | Name              | Value                        |
|-------|-------------------|------------------------------|
| A     | adcriskhorizon.com | Alias → CloudFront distribution |
| A     | www.adcriskhorizon.com | Alias → CloudFront distribution |

---

## GitHub Secrets Setup

Go to your GitHub repo → **Settings → Secrets and variables → Actions** and add:

| Secret Name                  | Value                                      |
|------------------------------|--------------------------------------------|
| `AWS_ACCESS_KEY_ID`          | IAM user access key                        |
| `AWS_SECRET_ACCESS_KEY`      | IAM user secret key                        |
| `S3_BUCKET_NAME`             | `adcriskhorizon.com`                       |
| `CLOUDFRONT_DISTRIBUTION_ID` | Your CloudFront distribution ID (e.g. `E1ABC...`) |

### IAM Policy for GitHub Actions user

Create an IAM user with this policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::adcriskhorizon.com",
        "arn:aws:s3:::adcriskhorizon.com/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": ["cloudfront:CreateInvalidation"],
      "Resource": "*"
    }
  ]
}
```

---

## Deployment

Every push to `main` automatically:
1. Syncs all files to S3
2. Invalidates the CloudFront cache so changes go live immediately

### Manual deploy (if needed)
```bash
aws s3 sync . s3://adcriskhorizon.com --exclude ".git/*" --exclude ".github/*" --delete
```

---

## Third-Party Integrations

| Feature      | Service   | Setup                                              |
|--------------|-----------|----------------------------------------------------|
| Appointments | Calendly  | Replace `https://calendly.com` in `index.html`     |
| Newsletter   | Mailchimp | Replace form `action="#"` in `index.html`          |
| Chat widget  | Tidio / Crisp | Add embed script before `</body>` in `index.html` |

---

## Local Development

No build step needed — pure HTML/CSS/JS.

```bash
# Simple local server (Python)
python3 -m http.server 8080

# Or with Node
npx serve .
```

Then open http://localhost:8080
