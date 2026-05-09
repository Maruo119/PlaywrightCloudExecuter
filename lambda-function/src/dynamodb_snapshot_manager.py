import json
import boto3
from typing import Dict, List, Optional
from datetime import datetime


class DynamoDBSnapshotManager:
    """
    Manages article snapshots in DynamoDB for diff tracking.
    """

    TABLE_NAME = 'playwright-news-snapshot'

    def __init__(self, region_name: str = 'ap-northeast-1'):
        """
        Initialize DynamoDB manager.

        Args:
            region_name: AWS region
        """
        self.dynamodb = boto3.resource('dynamodb', region_name=region_name)
        self.table = self.dynamodb.Table(self.TABLE_NAME)

    def get_snapshot(self, site: str) -> Optional[Dict]:
        """
        Retrieve previous snapshot from DynamoDB.

        Args:
            site: Site name (e.g., 'news-yahoo')

        Returns:
            Previous snapshot dictionary or None if not found
        """
        try:
            response = self.table.get_item(Key={'site': site})

            if 'Item' in response:
                item = response['Item']
                print(f'[INFO] Retrieved snapshot for {site} from DynamoDB')

                # Parse articles from JSON string
                articles_json = item.get('articles', '[]')
                if isinstance(articles_json, str):
                    item['articles'] = json.loads(articles_json)

                return item
            else:
                print(f'[INFO] No previous snapshot found for {site}')
                return None

        except Exception as e:
            print(f'[ERROR] Failed to get snapshot from DynamoDB: {str(e)}')
            return None

    def save_snapshot(self, site: str, articles: List[Dict], metadata: Dict) -> bool:
        """
        Save current articles snapshot to DynamoDB.

        Args:
            site: Site name (e.g., 'news-yahoo')
            articles: List of article dictionaries
            metadata: Article metadata (articleCount, scrapedAt, timestamp)

        Returns:
            True if save was successful, False otherwise
        """
        try:
            item = {
                'site': site,
                'articles': json.dumps(articles),  # Store as JSON string
                'articleCount': metadata.get('articleCount', 0),
                'scrapedAt': metadata.get('scrapedAt'),
                'timestamp': metadata.get('timestamp'),
                'lastUpdatedAt': datetime.utcnow().isoformat() + 'Z'
            }

            self.table.put_item(Item=item)
            print(f'[INFO] Snapshot saved for {site} to DynamoDB')
            return True

        except Exception as e:
            print(f'[ERROR] Failed to save snapshot to DynamoDB: {str(e)}')
            return False

    def ensure_table_exists(self) -> bool:
        """
        Check if DynamoDB table exists. If not, raise error with instructions.

        Returns:
            True if table exists
        """
        try:
            self.table.load()
            print(f'[INFO] Table {self.TABLE_NAME} exists')
            return True
        except Exception as e:
            print(f'[ERROR] Table {self.TABLE_NAME} does not exist: {str(e)}')
            print('[ERROR] Please run setup-dynamodb-snapshot.sh to create the table')
            return False
