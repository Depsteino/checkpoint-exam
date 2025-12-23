import os
import json
import time
import logging
import boto3
from botocore.exceptions import ClientError

# --- Config ---
# Configure logging to stdout so Docker logs show it
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger()

REGION = os.getenv('AWS_REGION', 'us-east-1')
SQS_QUEUE_URL = os.getenv('SQS_QUEUE_URL')
BUCKET_NAME = os.getenv('S3_BUCKET_NAME')

# --- MOCK SYSTEM (For Local Testing) ---
if os.getenv('TEST_MODE') == 'true':
    logger.warning("⚠️  RUNNING IN TEST MODE: MOCKING SQS & S3 ⚠️")
    
    class FakeBoto:
        def receive_message(self, **kwargs):
            # Return a fake message every 5 seconds
            time.sleep(2)
            return {
                'Messages': [{
                    'Body': json.dumps({
                        'email_sender': 'TestUser', 
                        'email_timestream': '123456', 
                        'email_content': 'Mock Data'
                    }),
                    'ReceiptHandle': 'mock_handle_123'
                }]
            }
        
        def put_object(self, **kwargs):
            print(f"💾 [MOCK S3] Uploaded file to Bucket '{kwargs['Bucket']}': {kwargs['Key']}")
        
        def delete_message(self, **kwargs):
            print(f"🗑️  [MOCK SQS] Deleted message: {kwargs['ReceiptHandle']}")

    sqs_client = FakeBoto()
    s3_client = FakeBoto()
else:
    # Real AWS Clients
    sqs_client = boto3.client('sqs', region_name=REGION)
    s3_client = boto3.client('s3', region_name=REGION)

# --- Worker Logic ---
def process_messages():
    logger.info("Worker Service Started. Polling SQS...")
    
    while True:
        try:
            # 1. Poll SQS (Long Polling for 20s is best practice to save API calls)
            response = sqs_client.receive_message(
                QueueUrl=SQS_QUEUE_URL,
                MaxNumberOfMessages=1,
                WaitTimeSeconds=20 if os.getenv('TEST_MODE') != 'true' else 1
            )

            if 'Messages' in response:
                for msg in response['Messages']:
                    process_single_message(msg)
            else:
                # No messages, just loop again
                logger.info("No messages found. Waiting...")
                
        except ClientError as e:
            logger.error(f"AWS Error: {e}")
            time.sleep(5)  # Backoff on error
        except Exception as e:
            logger.error(f"Unexpected Error: {e}")
            time.sleep(5)

def process_single_message(msg):
    try:
        body = json.loads(msg['Body'])
        receipt_handle = msg['ReceiptHandle']
        
        sender = body.get('email_sender', 'unknown')
        timestream = body.get('email_timestream', str(int(time.time())))
        
        # 2. Upload to S3
        # Naming convention: Sender_Timestamp.json
        file_name = f"{sender}_{timestream}.json"
        
        logger.info(f"Processing message from {sender}...")
        
        s3_client.put_object(
            Bucket=BUCKET_NAME,
            Key=file_name,
            Body=json.dumps(body)
        )
        
        # 3. Delete from SQS (Crucial! Otherwise it processes forever)
        sqs_client.delete_message(
            QueueUrl=SQS_QUEUE_URL,
            ReceiptHandle=receipt_handle
        )
        logger.info(f"Successfully uploaded {file_name} and deleted from queue.")

    except json.JSONDecodeError:
        logger.error("Failed to decode JSON body. Deleting bad message.")
        # Optionally delete bad messages so they don't clog the queue
        sqs_client.delete_message(QueueUrl=SQS_QUEUE_URL, ReceiptHandle=msg['ReceiptHandle'])

if __name__ == '__main__':
    process_messages()