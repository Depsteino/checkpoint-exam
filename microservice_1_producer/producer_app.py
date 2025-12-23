import os
import json
import logging
import boto3
from datetime import datetime
import re
from flask import Flask, request, jsonify
from botocore.exceptions import ClientError

# --- Configuration ----
app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = app.logger

# Environment Variables
REGION = os.getenv('AWS_REGION', 'us-east-1')
SQS_QUEUE_URL = os.getenv('SQS_QUEUE_URL')
SSM_PARAM_NAME = os.getenv('SSM_PARAM_NAME', 'auth_token')
APP_VERSION = os.getenv('APP_VERSION', 'unknown')

# AWS Clients (with LocalStack support via ENDPOINT_URL) #
ENDPOINT_URL = os.getenv('AWS_ENDPOINT_URL')
sqs_client = boto3.client('sqs', region_name=REGION, endpoint_url=ENDPOINT_URL)
ssm_client = boto3.client('ssm', region_name=REGION, endpoint_url=ENDPOINT_URL)

CACHED_TOKEN = None

def get_server_token():
    global CACHED_TOKEN
    if CACHED_TOKEN:
        return CACHED_TOKEN
    try:
        # Test Mode Helper
        if os.getenv('TEST_MODE') == 'true':
             return "TEST_TOKEN"

        logger.info(f"Fetching token from SSM: {SSM_PARAM_NAME}")
        response = ssm_client.get_parameter(Name=SSM_PARAM_NAME, WithDecryption=True)
        CACHED_TOKEN = response['Parameter']['Value']
        return CACHED_TOKEN
    except ClientError as e:
        logger.error(f"Failed to fetch token: {e}")
        return None

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({
        "status": "healthy",
        "version": APP_VERSION  # <--- The magic line
    }), 200

@app.route('/', methods=['POST'])
def ingest_data():
    req_data = request.get_json(silent=True)
    
    if not req_data:
        return jsonify({"error": "Invalid JSON"}), 400

    # --- 1. Parse the Structure ---
    # Structure: { "data": {...}, "token": "..." }
    
    data_payload = req_data.get('data')
    incoming_token = req_data.get('token') # <--- Getting token from Root Level

    # --- 2. Validate Token ---
    server_token = get_server_token()
    
    if not server_token:
        return jsonify({"error": "Server error (Missing SSM Token)"}), 500
        
    if incoming_token != server_token:
        logger.warning("Invalid token attempt")
        return jsonify({"error": "Unauthorized: Invalid Token"}), 403

    # --- 3. Validate Data Content ---
    if not data_payload:
        return jsonify({"error": "Missing 'data' field"}), 400

    required_fields = ["email_subject", "email_sender", "email_timestream", "email_content"]
    missing_fields = [field for field in required_fields if field not in data_payload]

    if missing_fields:
        return jsonify({"error": f"Missing fields: {missing_fields}"}), 400

    # Validate email sender format
    email_sender = data_payload.get("email_sender", "")
    if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email_sender):
        return jsonify({"error": "Invalid email address"}), 400

    # START ADDITION: Validate Timestamp Format
    try:
        timestamp_value = float(data_payload['email_timestream'])
        if not (timestamp_value > 0):
            raise ValueError("Timestamp must be positive")
        # Ensure it maps to a real datetime (raises if out of range)
        datetime.utcfromtimestamp(timestamp_value)
    except (ValueError, OSError, OverflowError):
        return jsonify({"error": "Invalid Date Format (email_timestream must be a valid Unix timestamp)"}), 400
    # END ADDITION

    # --- 4. Push to SQS ---
    # The prompt says: "The data of the payload should be published to the SQS"
    # So we send ONLY the 'data' block, stripping the token.
    try:
        sqs_client.send_message(
            QueueUrl=SQS_QUEUE_URL,
            MessageBody=json.dumps(data_payload)
        )
        logger.info(f"Message queued for sender: {data_payload.get('email_sender')}")
        return jsonify({"message": "Successfully processed"}), 200
        
    except ClientError as e:
        logger.error(f"SQS Error: {e}")
        return jsonify({"error": "Failed to queue message"}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
