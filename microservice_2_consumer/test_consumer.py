import json
import unittest
from unittest.mock import patch, MagicMock

import consumer_app as worker


class TestWorkerService(unittest.TestCase):
    @patch('consumer_app.s3_client')
    @patch('consumer_app.sqs_client')
    def test_process_single_message_happy_path(self, mock_sqs, mock_s3):
        worker.BUCKET_NAME = "test-bucket"
        worker.SQS_QUEUE_URL = "https://sqs.us-east-1.amazonaws.com/123/test-queue"

        msg = {
            "Body": json.dumps({
                "email_sender": "Tester",
                "email_timestream": "12345",
                "email_content": "Hello"
            }),
            "ReceiptHandle": "rh-123"
        }

        worker.process_single_message(msg)

        mock_s3.put_object.assert_called_once()
        put_kwargs = mock_s3.put_object.call_args.kwargs
        self.assertEqual(put_kwargs["Bucket"], "test-bucket")
        self.assertEqual(put_kwargs["Key"], "Tester_12345.json")

        mock_sqs.delete_message.assert_called_once_with(
            QueueUrl=worker.SQS_QUEUE_URL,
            ReceiptHandle="rh-123"
        )

    @patch('consumer_app.sqs_client')
    def test_process_single_message_invalid_json(self, mock_sqs):
        worker.SQS_QUEUE_URL = "https://sqs.us-east-1.amazonaws.com/123/test-queue"

        msg = {
            "Body": "not-json",
            "ReceiptHandle": "rh-bad"
        }

        worker.process_single_message(msg)

        mock_sqs.delete_message.assert_called_once_with(
            QueueUrl=worker.SQS_QUEUE_URL,
            ReceiptHandle="rh-bad"
        )

    @patch('consumer_app.s3_client')
    def test_process_single_message_missing_timestamp(self, mock_s3):
        worker.BUCKET_NAME = "test-bucket"

        msg = {
            "Body": json.dumps({
                "email_sender": "Tester",
                "email_content": "Hello"
            }),
            "ReceiptHandle": "rh-999"
        }

        with patch('consumer_app.sqs_client') as mock_sqs:
            worker.SQS_QUEUE_URL = "https://sqs.us-east-1.amazonaws.com/123/test-queue"
            worker.process_single_message(msg)

        mock_s3.put_object.assert_called_once()
        put_kwargs = mock_s3.put_object.call_args.kwargs
        self.assertTrue(put_kwargs["Key"].startswith("Tester_"))
