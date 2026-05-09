#!/bin/bash

# Setup script for DynamoDB snapshot table
# This script creates the 'playwright-news-snapshot' table for article diff tracking

set -e

# Configuration
TABLE_NAME="playwright-news-snapshot"
REGION="${AWS_REGION:-ap-northeast-1}"
PROFILE="${AWS_PROFILE:-default}"

echo "=========================================="
echo "DynamoDB Snapshot Table Setup"
echo "=========================================="
echo "Table Name: $TABLE_NAME"
echo "Region: $REGION"
echo "Profile: $PROFILE"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "[ERROR] AWS CLI is not installed"
    exit 1
fi

# Check if table already exists
echo "[INFO] Checking if table exists..."
if aws dynamodb describe-table \
    --table-name "$TABLE_NAME" \
    --region "$REGION" \
    --profile "$PROFILE" \
    &> /dev/null; then
    echo "[INFO] Table '$TABLE_NAME' already exists"
    exit 0
fi

# Create table
echo "[INFO] Creating table '$TABLE_NAME'..."
aws dynamodb create-table \
    --table-name "$TABLE_NAME" \
    --attribute-definitions \
        AttributeName=site,AttributeType=S \
    --key-schema \
        AttributeName=site,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION" \
    --profile "$PROFILE"

echo "[SUCCESS] Table created successfully"
echo ""
echo "Table Details:"
echo "  - Partition Key: site (String)"
echo "  - Billing Mode: Pay-per-request"
echo "  - Region: $REGION"
echo ""
echo "Attributes stored:"
echo "  - site: Site name (e.g., 'news-yahoo')"
echo "  - articles: JSON string of articles array"
echo "  - articleCount: Number of articles"
echo "  - scrapedAt: ISO 8601 timestamp"
echo "  - timestamp: Unix timestamp"
echo "  - lastUpdatedAt: Last update timestamp"
echo ""
echo "[INFO] Waiting for table to be active..."

# Wait for table to be active
aws dynamodb wait table-exists \
    --table-name "$TABLE_NAME" \
    --region "$REGION" \
    --profile "$PROFILE"

echo "[SUCCESS] Table is now active and ready to use"
