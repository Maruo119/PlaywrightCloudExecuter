import json
from typing import Dict, List, Tuple, Optional


class DiffDetector:
    """
    Detects differences between current and previous articles based on URLs.
    """

    def __init__(self):
        pass

    @staticmethod
    def extract_urls(articles: List[Dict]) -> set:
        """
        Extract URL set from articles list.

        Args:
            articles: List of article dictionaries with 'url' key

        Returns:
            Set of URLs
        """
        return {article.get('url') for article in articles if article.get('url')}

    @staticmethod
    def detect_diff(
        current_articles: List[Dict],
        previous_articles: Optional[List[Dict]] = None
    ) -> Dict:
        """
        Detect differences between current and previous articles.

        Args:
            current_articles: Current articles list
            previous_articles: Previous articles list (None for first run)

        Returns:
            Dictionary containing:
            - new_articles: List of newly added articles
            - deleted_articles: List of deleted articles
            - has_diff: Boolean indicating if there are differences
            - summary: String summary of changes
        """
        current_urls = DiffDetector.extract_urls(current_articles)

        # First run: no previous data
        if previous_articles is None:
            return {
                'new_articles': [],
                'deleted_articles': [],
                'has_diff': False,
                'summary': 'First run - no previous data to compare'
            }

        previous_urls = DiffDetector.extract_urls(previous_articles)

        # Find new and deleted articles
        new_urls = current_urls - previous_urls
        deleted_urls = previous_urls - current_urls

        new_articles = [
            article for article in current_articles
            if article.get('url') in new_urls
        ]

        deleted_articles = [
            article for article in previous_articles
            if article.get('url') in deleted_urls
        ]

        has_diff = len(new_articles) > 0 or len(deleted_articles) > 0

        # Generate summary
        summary_parts = []
        if new_articles:
            summary_parts.append(f'{len(new_articles)} new article(s)')
        if deleted_articles:
            summary_parts.append(f'{len(deleted_articles)} deleted article(s)')

        summary = ', '.join(summary_parts) if summary_parts else 'No changes'

        return {
            'new_articles': new_articles,
            'deleted_articles': deleted_articles,
            'has_diff': has_diff,
            'summary': summary
        }
