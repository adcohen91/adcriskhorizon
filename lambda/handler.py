import json
import boto3
import urllib.parse

ses = boto3.client('ses', region_name='us-east-1')

FROM_EMAIL = 'info@adcriskhorizon.com'
TO_EMAIL   = 'info@adcriskhorizon.com'

def lambda_handler(event, context):
    headers = {
        'Access-Control-Allow-Origin': 'https://adcriskhorizon.com',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Allow-Methods': 'POST, OPTIONS'
    }

    if event.get('requestContext', {}).get('http', {}).get('method') == 'OPTIONS':
        return {'statusCode': 200, 'headers': headers, 'body': ''}

    try:
        body = event.get('body', '')
        if event.get('isBase64Encoded'):
            import base64
            body = base64.b64decode(body).decode('utf-8')

        params = urllib.parse.parse_qs(body)

        form_type = params.get('form_type', ['contact'])[0]

        if form_type == 'subscribe':
            email = params.get('EMAIL', [''])[0]
            subject = 'New Newsletter Subscriber – ADC Risk Horizon'
            message = f'New subscriber:\n\nEmail: {email}'
        else:
            name    = params.get('name', [''])[0]
            email   = params.get('email', [''])[0]
            message_text = params.get('message', [''])[0]
            subject = f'New Contact Form Submission – ADC Risk Horizon'
            message = f'New message from the website:\n\nName: {name}\nEmail: {email}\n\nMessage:\n{message_text}'

        ses.send_email(
            Source=FROM_EMAIL,
            Destination={'ToAddresses': [TO_EMAIL]},
            Message={
                'Subject': {'Data': subject},
                'Body':    {'Text': {'Data': message}}
            },
            ReplyToAddresses=[email] if email else []
        )

        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({'ok': True})
        }

    except Exception as e:
        print(f'Error: {e}')
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'ok': False, 'error': str(e)})
        }
