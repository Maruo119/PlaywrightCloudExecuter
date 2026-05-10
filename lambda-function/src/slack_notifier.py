import json
import requests
import boto3
from typing import Dict, List, Optional


class SlackNotifier:
    """
    Sends notifications to Slack webhook for article diff updates.
    """

    def __init__(self, webhook_url: Optional[str] = None):
        """
        Initialize Slack notifier.

        Args:
            webhook_url: Slack webhook URL. If None, will be fetched from Secrets Manager.
        """
        self.webhook_url = webhook_url
        if not self.webhook_url:
            self.webhook_url = self._get_webhook_from_secrets()

    @staticmethod
    def _get_webhook_from_secrets() -> str:
        """
        Fetch Slack webhook URL from AWS Secrets Manager.

        Returns:
            Webhook URL string
        """
        try:
            secrets_client = boto3.client('secretsmanager')
            response = secrets_client.get_secret_value(
                SecretId='SLACK_WEBHOOK_URL_NEW2'
            )
            webhook_url = response['SecretString']
            print('[INFO] Slack webhook URL retrieved from Secrets Manager')
            return webhook_url
        except Exception as e:
            print(f'[ERROR] Failed to fetch webhook URL from Secrets Manager: {str(e)}')
            raise

    def send_notification(
        self,
        site_name: str,
        new_articles: List[Dict],
        deleted_articles: List[Dict],
        current_count: int,
        previous_count: int
    ) -> bool:
        """
        Send notification to Slack about article changes.

        Args:
            site_name: Site name (e.g., 'news-yahoo')
            new_articles: List of newly added articles
            deleted_articles: List of deleted articles
            current_count: Current article count
            previous_count: Previous article count

        Returns:
            True if notification was sent successfully, False otherwise
        """
        try:
            message = self._build_message(
                site_name,
                new_articles,
                deleted_articles,
                current_count,
                previous_count
            )

            response = requests.post(
                self.webhook_url,
                json=message,
                timeout=10
            )

            if response.status_code == 200:
                print('[INFO] Slack notification sent successfully')
                return True
            else:
                print(
                    f'[ERROR] Slack notification failed with status {response.status_code}'
                )
                return False

        except Exception as e:
            print(f'[ERROR] Failed to send Slack notification: {str(e)}')
            return False

    @staticmethod
    def _build_message(
        site_name: str,
        new_articles: List[Dict],
        deleted_articles: List[Dict],
        current_count: int,
        previous_count: int
    ) -> Dict:
        """
        Build Slack message payload showing only new articles.
        """
        blocks = []

        if new_articles:
            article_text = ''
            for article in new_articles:
                title = article.get('title', 'Unknown')
                url = article.get('url', '')
                article_text += f'• <{url}|{title}>\n'

            blocks.append({
                'type': 'section',
                'text': {
                    'type': 'mrkdwn',
                    'text': article_text.rstrip()
                }
            })

        return {'blocks': blocks}
