import unittest
import json
from unittest.mock import patch, MagicMock
import producer_app as app  # Import your application
from botocore.exceptions import ClientError

class TestApiService(unittest.TestCase):

    def setUp(self):
        # 1. Reset the Global Cache so the app is forced to fetch a new token
        app.CACHED_TOKEN = None 
        
        # 2. Setup Flask Client
        self.app = app.app.test_client()
        self.app.testing = True

    @patch('producer_app.ssm_client') 
    @patch('producer_app.sqs_client') 
    def test_happy_path(self, mock_sqs, mock_ssm):
        """Test a perfect request with valid token and data."""
        
        # Mock SSM to return our specific test token
        mock_ssm.get_parameter.return_value = {
            'Parameter': {'Value': 'VALID_TOKEN'}
        }

        # Payload with Token at Root Level (Matches your latest code)
        payload = {
            "token": "VALID_TOKEN",
            "data": {
                "email_sender": "test@example.com",
                "email_subject": "Unit Test",
                "email_timestream": "12345",
                "email_content": "Content"
            }
        }

        response = self.app.post('/', 
                                 data=json.dumps(payload),
                                 content_type='application/json')

        # Assertions
        self.assertEqual(response.status_code, 200)
        self.assertIn("Successfully processed", response.get_data(as_text=True))
        
        # Verify SQS call
        mock_sqs.send_message.assert_called_once()

    @patch('producer_app.ssm_client')
    def test_invalid_token(self, mock_ssm):
        """Test that a wrong token returns 403."""
        
        mock_ssm.get_parameter.return_value = {'Parameter': {'Value': 'REAL_TOKEN'}}

        payload = {
            "token": "WRONG_TOKEN",
            "data": { 
                "email_sender": "hacker@example.com",
                "email_subject": "Bad",
                "email_timestream": "12345",
                "email_content": "Bad"
            }
        }

        response = self.app.post('/', 
                                 data=json.dumps(payload),
                                 content_type='application/json')

        self.assertEqual(response.status_code, 403)

    @patch('producer_app.ssm_client')
    def test_missing_fields(self, mock_ssm):
        """Test that missing required fields returns 400."""
        
        mock_ssm.get_parameter.return_value = {'Parameter': {'Value': 'VALID_TOKEN'}}

        # Missing 'email_subject'
        payload = {
            "token": "VALID_TOKEN",  # Token is valid...
            "data": {
                "email_sender": "test@example.com",
                # Subject is missing!
                "email_timestream": "12345",
                "email_content": "Content"
            }
        }

        response = self.app.post('/', 
                                 data=json.dumps(payload),
                                 content_type='application/json')

        self.assertEqual(response.status_code, 400)
        self.assertIn("Missing fields", response.get_data(as_text=True))

    @patch('producer_app.ssm_client')
    def test_invalid_json(self, mock_ssm):
        """Test invalid JSON returns 400."""
        mock_ssm.get_parameter.return_value = {'Parameter': {'Value': 'VALID_TOKEN'}}

        response = self.app.post('/',
                                 data="not-json",
                                 content_type='application/json')

        self.assertEqual(response.status_code, 400)
        self.assertIn("Invalid JSON", response.get_data(as_text=True))

    @patch('producer_app.ssm_client')
    def test_missing_data(self, mock_ssm):
        """Test missing data field returns 400."""
        mock_ssm.get_parameter.return_value = {'Parameter': {'Value': 'VALID_TOKEN'}}

        payload = {"token": "VALID_TOKEN"}
        response = self.app.post('/',
                                 data=json.dumps(payload),
                                 content_type='application/json')

        self.assertEqual(response.status_code, 400)
        self.assertIn("Missing 'data' field", response.get_data(as_text=True))

    @patch('producer_app.sqs_client')
    @patch('producer_app.ssm_client')
    def test_invalid_timestamp(self, mock_ssm, mock_sqs):
        """Test invalid timestamp returns 400."""
        mock_ssm.get_parameter.return_value = {'Parameter': {'Value': 'VALID_TOKEN'}}

        payload = {
            "token": "VALID_TOKEN",
            "data": {
                "email_sender": "test@example.com",
                "email_subject": "Unit Test",
                "email_timestream": "not-a-number",
                "email_content": "Content"
            }
        }

        response = self.app.post('/',
                                 data=json.dumps(payload),
                                 content_type='application/json')

        self.assertEqual(response.status_code, 400)
        self.assertIn("Invalid Date Format", response.get_data(as_text=True))
        mock_sqs.send_message.assert_not_called()

    @patch('producer_app.ssm_client')
    def test_ssm_failure(self, mock_ssm):
        """Test SSM failure returns 500."""
        mock_ssm.get_parameter.side_effect = ClientError(
            {"Error": {"Code": "AccessDeniedException", "Message": "Denied"}},
            "GetParameter"
        )

        payload = {
            "token": "ANY",
            "data": {
                "email_sender": "test@example.com",
                "email_subject": "Unit Test",
                "email_timestream": "12345",
                "email_content": "Content"
            }
        }

        response = self.app.post('/',
                                 data=json.dumps(payload),
                                 content_type='application/json')

        self.assertEqual(response.status_code, 500)
        self.assertIn("Server error", response.get_data(as_text=True))

    @patch('producer_app.sqs_client')
    @patch('producer_app.ssm_client')
    def test_sqs_failure(self, mock_ssm, mock_sqs):
        """Test SQS failure returns 500."""
        mock_ssm.get_parameter.return_value = {'Parameter': {'Value': 'VALID_TOKEN'}}
        mock_sqs.send_message.side_effect = ClientError(
            {"Error": {"Code": "ServiceUnavailable", "Message": "SQS down"}},
            "SendMessage"
        )

        payload = {
            "token": "VALID_TOKEN",
            "data": {
                "email_sender": "test@example.com",
                "email_subject": "Unit Test",
                "email_timestream": "12345",
                "email_content": "Content"
            }
        }

        response = self.app.post('/',
                                 data=json.dumps(payload),
                                 content_type='application/json')

        self.assertEqual(response.status_code, 500)
        self.assertIn("Failed to queue message", response.get_data(as_text=True))

if __name__ == '__main__':
    unittest.main()
