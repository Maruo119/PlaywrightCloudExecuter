# Lambda 関数

このディレクトリには 2 つの異なる用途の Lambda 関数があります。

## 1. EventBridge トリガー用（既存）

**ファイル**: `index.py`

EventBridge の定期スケジュール（デフォルト: 1 時間ごと）でトリガーされ、ECS 上の Fargate タスクを起動します。

### 環境変数

- `AWS_REGION`: AWS リージョン（デフォルト: ap-northeast-1）
- `ECS_CLUSTER`: ECS クラスタ名
- `TASK_DEFINITION`: ECS タスク定義名
- `SUBNET_ID`: VPC サブネット ID
- `SECURITY_GROUP_ID`: セキュリティグループ ID

## 2. S3 イベント駆動型（新規）

**ファイル**: `lambda_handler.py`

S3 の PutObject イベント（ファイル登録）でトリガーされ、記事の差分を検出して Slack に通知します。

### 構成

```
lambda_handler.py          # メイン関数
src/
  ├── diff_detector.py              # 差分検出ロジック
  ├── slack_notifier.py             # Slack 通知処理
  └── dynamodb_snapshot_manager.py  # DynamoDB スナップショット管理
```

### セットアップ手順

#### 1. DynamoDB テーブルの作成

```bash
./scripts/setup-dynamodb-snapshot.sh
```

#### 2. Slack Webhook URL を Secrets Manager に登録

```bash
aws secretsmanager create-secret \
  --name SLACK_WEBHOOK_URL \
  --secret-string '<your-slack-webhook-url-here>' \
  --region ap-northeast-1
```

**注意**: `<your-slack-webhook-url-here>` は実際の webhook URL で置き換えてください。

#### 3. Lambda 関数のデプロイ

##### パッケージ作成

```bash
# プロジェクトルートから実行
cd lambda-function

# 依存関係をインストール
pip install -r requirements.txt -t package/

# ソースファイルをパッケージにコピー
cp lambda_handler.py package/
cp -r src package/

# ZIP ファイルを作成
cd package
zip -r ../lambda_handler.zip .
cd ..
```

##### AWS Lambda にデプロイ

```bash
aws lambda create-function \
  --function-name playwright-s3-diff-detector \
  --runtime python3.11 \
  --role arn:aws:iam::ACCOUNT_ID:role/lambda-execution-role \
  --handler lambda_handler.lambda_handler \
  --zip-file fileb://lambda_handler.zip \
  --timeout 60 \
  --memory-size 256 \
  --region ap-northeast-1
```

または、既存関数を更新:

```bash
aws lambda update-function-code \
  --function-name playwright-s3-diff-detector \
  --zip-file fileb://lambda_handler.zip \
  --region ap-northeast-1
```

#### 4. IAM 実行ロールの権限設定

Lambda 実行ロールに以下の権限を追加します（`ACCOUNT_ID` は実際の AWS アカウント ID に置き換え）:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject"
      ],
      "Resource": "arn:aws:s3:::playwright-output-bucket/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem"
      ],
      "Resource": "arn:aws:dynamodb:ap-northeast-1:ACCOUNT_ID:table/playwright-news-snapshot"
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:ap-northeast-1:ACCOUNT_ID:secret:SLACK_WEBHOOK_URL*"
    }
  ]
}
```

#### 5. S3 イベント通知の設定

AWS Console または AWS CLI で S3 バケットのイベント通知を設定します（`ACCOUNT_ID` は実際の AWS アカウント ID に置き換え）:

```bash
aws s3api put-bucket-notification-configuration \
  --bucket playwright-output-bucket \
  --notification-configuration '{
    "LambdaFunctionConfigurations": [
      {
        "LambdaFunctionArn": "arn:aws:lambda:ap-northeast-1:ACCOUNT_ID:function:playwright-s3-diff-detector",
        "Events": ["s3:ObjectCreated:*"],
        "Filter": {
          "Key": {
            "FilterRules": [
              {"Name": "prefix", "Value": "news-yahoo/"},
              {"Name": "suffix", "Value": ".json"}
            ]
          }
        }
      }
    ]
  }' \
  --region ap-northeast-1
```

### 処理フロー

1. ECS が S3 に `news-yahoo/articles_*.json` を登録
2. S3 PutObject イベントが発火
3. Lambda 関数 `lambda_handler.py` がトリガー
4. DynamoDB から前回のスナップショットを取得
5. articles の URL で差分を検出
6. 差分があれば Slack に通知
7. DynamoDB に新規スナップショットを保存

### エラーハンドリング

| エラー | 対処法 |
|--------|--------|
| DynamoDB テーブルが見つからない | `./scripts/setup-dynamodb-snapshot.sh` を実行 |
| Slack Webhook URL が見つからない | Secrets Manager に `SLACK_WEBHOOK_URL` を登録 |
| S3 オブジェクトが見つからない | CloudWatch Logs を確認 |
| Lambda に S3 アクセス権限がない | IAM 実行ロール権限を確認 |

### ローカルテスト

Lambda 関数をローカルでテストする場合:

```bash
cd lambda-function

# テスト用に環境変数を設定
export AWS_REGION=ap-northeast-1
export AWS_PROFILE=your-profile-name

# Python スクリプトを直接実行
python lambda_handler.py
```
