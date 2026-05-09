"""
Lambda handler for S3 PutObject event.
Detects article changes and sends Slack notification.
"""

import json
import boto3
import os
from datetime import datetime

# Import custom modules
import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from diff_detector import DiffDetector
from slack_notifier import SlackNotifier
from dynamodb_snapshot_manager import DynamoDBSnapshotManager


s3_client = boto3.client('s3')


def lambda_handler(event, context):
    """
    S3 PutObject event handler.
    Triggered when a new article JSON file is uploaded to S3.

    Event format (S3 Notification):
    {
        "Records": [
            {
                "s3": {
                    "bucket": {"name": "playwright-output-bucket"},
                    "object": {"key": "news-yahoo/articles_1234567890.json"}
                }
            }
        ]
    }
    """
    print('[INFO] Lambda handler started')

    try:
        # Parse S3 event
        records = event.get('Records', [])
        if not records:
            print('[WARNING] No S3 records in event')
            return build_response(400, 'No S3 records found')

        # Process first record (should be only one per invocation)
        s3_record = records[0]['s3']
        bucket_name = s3_record['bucket']['name']
        object_key = s3_record['object']['key']

        print(f'[INFO] Processing S3 object: s3://{bucket_name}/{object_key}')

        # Extract site name from object key (e.g., 'news-yahoo' from 'news-yahoo/articles_*.json')
        site_name = object_key.split('/')[0]
        print(f'[INFO] Site name: {site_name}')

        # Only process article files
        if not object_key.endswith('.json'):
            print('[INFO] Skipping non-JSON file')
            return build_response(200, 'Skipped non-JSON file')

        # Download and parse the new file
        current_data = download_s3_file(bucket_name, object_key)
        if not current_data:
            return build_response(400, 'Failed to download S3 file')

        current_articles = current_data.get('articles', [])
        current_count = current_data.get('articleCount', 0)

        print(f'[INFO] Current articles count: {current_count}')

        # Initialize DynamoDB manager
        db_manager = DynamoDBSnapshotManager()

        # Check if table exists
        if not db_manager.ensure_table_exists():
            print('[WARNING] DynamoDB table does not exist. Saving snapshot without diff detection.')
            # Still save the snapshot for next run
            db_manager.save_snapshot(site_name, current_articles, {
                'articleCount': current_count,
                'scrapedAt': current_data.get('scrapedAt'),
                'timestamp': current_data.get('timestamp')
            })
            return build_response(200, 'Snapshot saved (table missing, no diff sent)')

        # Get previous snapshot
        previous_snapshot = db_manager.get_snapshot(site_name)
        previous_articles = None
        previous_count = 0

        if previous_snapshot:
            previous_articles = previous_snapshot.get('articles', [])
            previous_count = previous_snapshot.get('articleCount', 0)
            print(f'[INFO] Previous articles count: {previous_count}')
        else:
            print('[INFO] No previous snapshot found (first run)')

        # Detect differences
        diff_result = DiffDetector.detect_diff(current_articles, previous_articles)

        print(f'[INFO] Diff detection result:')
        print(f'  - Has diff: {diff_result["has_diff"]}')
        print(f'  - Summary: {diff_result["summary"]}')

        # Send Slack notification if diff detected
        if diff_result['has_diff']:
            print('[INFO] Difference detected. Sending Slack notification...')
            notifier = SlackNotifier()
            notifier.send_notification(
                site_name=site_name,
                new_articles=diff_result['new_articles'],
                deleted_articles=diff_result['deleted_articles'],
                current_count=current_count,
                previous_count=previous_count
            )
        else:
            print('[INFO] No difference detected. Skipping Slack notification.')

        # Always save current snapshot for next run
        save_success = db_manager.save_snapshot(site_name, current_articles, {
            'articleCount': current_count,
            'scrapedAt': current_data.get('scrapedAt'),
            'timestamp': current_data.get('timestamp')
        })

        if not save_success:
            print('[WARNING] Failed to save snapshot to DynamoDB')

        return build_response(200, {
            'message': 'Processing completed',
            'site': site_name,
            'has_diff': diff_result['has_diff'],
            'summary': diff_result['summary'],
            'snapshot_saved': save_success
        })

    except Exception as e:
        error_msg = f'Error processing S3 event: {str(e)}'
        print(f'[ERROR] {error_msg}')
        print(f'[ERROR] Exception type: {type(e).__name__}')
        import traceback
        traceback.print_exc()
        return build_response(500, {'error': error_msg})


def download_s3_file(bucket_name: str, object_key: str) -> dict:
    """
    Download and parse JSON file from S3.

    Args:
        bucket_name: S3 bucket name
        object_key: S3 object key

    Returns:
        Parsed JSON data or None if failed
    """
    try:
        response = s3_client.get_object(Bucket=bucket_name, Key=object_key)
        content = response['Body'].read().decode('utf-8')
        data = json.loads(content)
        print(f'[INFO] Successfully downloaded and parsed S3 object')
        return data
    except Exception as e:
        print(f'[ERROR] Failed to download/parse S3 file: {str(e)}')
        return None


def build_response(status_code: int, body) -> dict:
    """
    Build Lambda response.

    Args:
        status_code: HTTP status code
        body: Response body (dict or string)

    Returns:
        Lambda response dict
    """
    if isinstance(body, dict):
        body = json.dumps(body)
    elif not isinstance(body, str):
        body = json.dumps({'message': str(body)})

    return {
        'statusCode': status_code,
        'body': body,
        'timestamp': datetime.utcnow().isoformat()
    }


# For local testing
if __name__ == '__main__':
    test_event = {
        'Records': [
            {
                's3': {
                    'bucket': {'name': 'playwright-output-bucket'},
                    'object': {'key': 'news-yahoo/articles_1777991557552.json'}
                }
            }
        ]
    }
    result = lambda_handler(test_event, None)
    print(json.dumps(result, indent=2))
