import json
import re
import time
import boto3
import urllib.parse

ses = boto3.client('ses', region_name='us-east-1')

FROM_EMAIL = 'info@adcriskhorizon.com'
TO_EMAIL   = 'info@adcriskhorizon.com'

# ── In-memory rate limiting ───────────────────────────────────────────────
# Limits per IP: max 5 submissions per 10-minute window.
# Resets when the Lambda container recycles (typically every few hours).
RATE_LIMIT_MAX    = 5
RATE_LIMIT_WINDOW = 600  # seconds
_rate_store: dict[str, list[float]] = {}

def _is_rate_limited(ip: str) -> bool:
    now = time.time()
    window_start = now - RATE_LIMIT_WINDOW
    timestamps = [t for t in _rate_store.get(ip, []) if t > window_start]
    if len(timestamps) >= RATE_LIMIT_MAX:
        return True
    timestamps.append(now)
    _rate_store[ip] = timestamps
    return False

# ── Validation helpers ────────────────────────────────────────────────────
EMAIL_RE = re.compile(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')

def _validate_email(email: str) -> bool:
    return bool(EMAIL_RE.match(email)) and len(email) <= 254

def _clean(value: str, max_len: int) -> str:
    return value.strip()[:max_len]

# ── CORS headers ──────────────────────────────────────────────────────────
HEADERS = {
    'Access-Control-Allow-Origin':  'https://adcriskhorizon.com',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

def _resp(status: int, ok: bool, msg: str = '') -> dict:
    return {
        'statusCode': status,
        'headers': HEADERS,
        'body': json.dumps({'ok': ok, 'message': msg}),
    }

# ── Handler ───────────────────────────────────────────────────────────────
def lambda_handler(event, context):
    method = event.get('requestContext', {}).get('http', {}).get('method', '')

    if method == 'OPTIONS':
        return {'statusCode': 200, 'headers': HEADERS, 'body': ''}

    if method != 'POST':
        return _resp(405, False, 'Method not allowed')

    # Rate limit by source IP
    ip = event.get('requestContext', {}).get('http', {}).get('sourceIp', 'unknown')
    if _is_rate_limited(ip):
        return _resp(429, False, 'Too many requests — please wait a few minutes.')

    # Parse body
    try:
        body = event.get('body', '')
        if event.get('isBase64Encoded'):
            import base64
            body = base64.b64decode(body).decode('utf-8')
        params = urllib.parse.parse_qs(body, keep_blank_values=True)
    except Exception:
        return _resp(400, False, 'Invalid request body')

    def get(key: str) -> str:
        return params.get(key, [''])[0].strip()

    # Honeypot — bots fill this hidden field, humans don't
    if get('website'):
        return _resp(200, True)  # Silently succeed so bots don't retry

    form_type = get('form_type') or 'contact'

    if form_type == 'subscribe':
        email = _clean(get('EMAIL'), 254)
        if not email:
            return _resp(400, False, 'Email is required.')
        if not _validate_email(email):
            return _resp(400, False, 'Please enter a valid email address.')

        subject = 'New Newsletter Subscriber – ADC Risk Horizon'
        message = f'New subscriber:\n\nEmail: {email}'
        reply_to = [email]

    else:
        name    = _clean(get('name'), 100)
        email   = _clean(get('email'), 254)
        message_text = _clean(get('message'), 2000)

        if not name:
            return _resp(400, False, 'Name is required.')
        if not email or not _validate_email(email):
            return _resp(400, False, 'Please enter a valid email address.')
        if not message_text:
            return _resp(400, False, 'Message is required.')

        subject = f'New Contact Form Submission – ADC Risk Horizon'
        message = (
            f'New message from the website:\n\n'
            f'Name:    {name}\n'
            f'Email:   {email}\n\n'
            f'Message:\n{message_text}'
        )
        reply_to = [email]

    try:
        ses.send_email(
            Source=FROM_EMAIL,
            Destination={'ToAddresses': [TO_EMAIL]},
            Message={
                'Subject': {'Data': subject},
                'Body':    {'Text': {'Data': message}},
            },
            ReplyToAddresses=reply_to,
        )
        return _resp(200, True, 'Message sent successfully.')

    except Exception as e:
        print(f'SES error: {e}')
        return _resp(500, False, 'Failed to send — please try again.')
