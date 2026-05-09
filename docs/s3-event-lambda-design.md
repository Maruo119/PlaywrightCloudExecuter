# S3 イベント駆動型の差分検出・Slack 通知システム

## 概要

ECS で実行される Playwright アプリケーションが S3 にニュース記事の JSON ファイルを登録する際に、前回との差分を自動検出し、差分があれば Slack に通知するシステムです。

## システムアーキテクチャ

```
ECS (Playwright実行)
  ↓
S3 に articles_*.json を登録
  ↓
S3 PutObject イベント発火
  ↓
Lambda トリガー起動
  ├→ S3 から新規ファイルを取得
  ├→ DynamoDB から前回のスナップショットを取得
  ├→ articles の URL で差分を検出
  ├→ 差分があれば Slack に通知
  └→ DynamoDB に新規スナップショットを保存
```

## ファイル構成

```
lambda-function/
├── src/
│   ├── diff_detector.py              # 差分検出ロジック
│   ├── slack_notifier.py             # Slack 通知処理
│   └── dynamodb_snapshot_manager.py  # DynamoDB スナップショット管理
├── lambda_handler.py                 # S3 イベント処理用 Lambda 関数
├── index.py                          # 既存: Fargate 起動用 Lambda 関数
├── requirements.txt                  # Python 依存関係
└── README.md

docs/
└── s3-event-lambda-design.md        # このファイル

scripts/
└── setup-dynamodb-snapshot.sh        # DynamoDB テーブル初期化スクリプト
```

## モジュール説明

### 1. diff_detector.py

**責務**: 新規と前回の articles を比較して差分を検出

**主要メソッド**:
- `extract_urls()`: articles 配列から URL セットを抽出
- `detect_diff()`: 前回のデータと新規データを比較

**差分判定ルール**:
- URL をユニークキーとして扱う
- 新規記事: 新規ファイルに存在し、前回にない URL
- 削除記事: 前回に存在し、新規ファイルにない URL
- 順序変更は差分として扱わない

**戻り値**:
```python
{
    'new_articles': [...],           # 新規記事リスト
    'deleted_articles': [...],       # 削除記事リスト
    'has_diff': bool,                # 差分有無
    'summary': str                   # サマリー文字列
}
```

### 2. slack_notifier.py

**責務**: Slack Webhook を通じて差分情報を通知

**主要メソッド**:
- `send_notification()`: Slack にメッセージを送信
- `_build_message()`: Slack メッセージペイロードを構築

**メッセージ形式**:
- Header: サイト名と更新情報
- Summary: 記事数の変化（前回 → 現在）
- New Articles セクション: 新規記事（最大 5 件表示）
- Deleted Articles セクション: 削除記事（最大 5 件表示）

**Webhook URL 取得**:
- AWS Secrets Manager から `SLACK_WEBHOOK_URL` シークレットを取得
- シークレット名: `SLACK_WEBHOOK_URL`
- ⚠️ **重要**: webhook URL はコードに絶対に記載しない。Secrets Manager で管理

### 3. dynamodb_snapshot_manager.py

**責務**: DynamoDB にスナップショット（前回のデータ）を保存・取得

**テーブル仕様**:

| 属性名 | 型 | 説明 |
|--------|-----|------|
| site | String (PK) | サイト名 (例: news-yahoo) |
| articles | String | articles 配列を JSON 文字列で保存 |
| articleCount | Number | 記事数 |
| scrapedAt | String | スクレイピング実行時刻（ISO 8601） |
| timestamp | Number | Unix タイムスタンプ |
| lastUpdatedAt | String | 最後に更新した時刻（ISO 8601） |

**主要メソッド**:
- `get_snapshot()`: 前回のスナップショットを取得
- `save_snapshot()`: 現在のデータをスナップショットとして保存
- `ensure_table_exists()`: テーブル存在確認

### 4. lambda_handler.py

**責務**: S3 イベントの受信と全体フロー制御

**トリガー**: S3 PutObject イベント

**イベント形式**:
```json
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
```

**処理フロー**:
1. S3 イベントからバケット名とオブジェクトキーを抽出
2. オブジェクトキーからサイト名を抽出（`news-yahoo/articles_*.json` → `news-yahoo`）
3. S3 から新規ファイルをダウンロード
4. DynamoDB から前回のスナップショットを取得
5. 差分を検出
6. 差分があれば Slack に通知
7. DynamoDB に新規スナップショットを保存

**エラーハンドリング**:
- DynamoDB テーブルが存在しない場合: 通知なし、スナップショット保存のみ
- Slack 通知失敗時: ログに記録、処理は続行
- S3 ダウンロード失敗: エラーレスポンスを返す

## セットアップ手順

### 1. DynamoDB テーブルの作成

```bash
# AWS プロファイルを指定して実行（AWS CLI が必要）
AWS_PROFILE=your-profile-name ./scripts/setup-dynamodb-snapshot.sh
```

テーブル名: `playwright-news-snapshot`
- パーティションキー: `site` (String)
- ビリングモード: オンデマンド（PAY_PER_REQUEST）

### 2. Slack Webhook URL を Secrets Manager に登録

以下のコマンドで Slack webhook URL をシークレットとして登録します：

```bash
aws secretsmanager create-secret \
  --name SLACK_WEBHOOK_URL \
  --secret-string '<your-slack-webhook-url-here>' \
  --region ap-northeast-1 \
  --profile your-profile-name
```

**重要**: `<your-slack-webhook-url-here>` は実際の webhook URL で置き換えてください。

webhook URL は Slack ワークスペースの Incoming Webhooks 設定で取得できます。

### 3. Lambda 関数のデプロイ

Lambda 関数 `lambda_handler.py` を AWS Lambda にデプロイします：

**要件**:
- Python 3.11 以上
- IAM 権限:
  - `s3:GetObject` (playwright-output-bucket)
  - `dynamodb:GetItem` (playwright-news-snapshot テーブル)
  - `dynamodb:PutItem` (playwright-news-snapshot テーブル)
  - `secretsmanager:GetSecretValue` (SLACK_WEBHOOK_URL)

### 4. S3 イベント通知の設定

S3 バケット `playwright-output-bucket` のイベント設定：

**イベント**: `s3:ObjectCreated:*`
**フィルター**: `news-yahoo/articles_*.json`
**デスティネーション**: Lambda 関数

AWS Console または AWS CLI で設定：

```bash
# イベント通知設定（例）
aws s3api put-bucket-notification-configuration \
  --bucket playwright-output-bucket \
  --notification-configuration '{
    "LambdaFunctionConfigurations": [
      {
        "LambdaFunctionArn": "arn:aws:lambda:ap-northeast-1:ACCOUNT_ID:function:lambda_handler",
        "Events": ["s3:ObjectCreated:*"],
        "Filter": {
          "Key": {
            "FilterRules": [
              {
                "Name": "prefix",
                "Value": "news-yahoo/"
              },
              {
                "Name": "suffix",
                "Value": ".json"
              }
            ]
          }
        }
      }
    ]
  }' \
  --region ap-northeast-1
```

※ `ACCOUNT_ID` は実際の AWS アカウント ID で置き換えてください

## 処理フロー詳細

### 初回実行時

1. ECS が S3 に `news-yahoo/articles_1777991557552.json` を登録
2. Lambda がトリガーされる
3. DynamoDB に `site=news-yahoo` のレコードがない
4. 通知は送信されない
5. DynamoDB にスナップショットを保存

### 2 回目以降の実行時

1. ECS が新しい JSON ファイルを登録（例: `articles_1778034978358.json`）
2. Lambda がトリガー
3. DynamoDB から前回のスナップショット（前々回のデータ）を取得
4. 新規ファイルと比較して URL 差分を検出
5. 差分があれば Slack に通知
6. DynamoDB に新規スナップショットを保存（次回用）

### 例: 新規記事が追加された場合

```
前回の articles: [記事A, 記事B, 記事C]
現在の articles: [記事A, 記事B, 記事C, 記事D]

差分検出結果:
- new_articles: [記事D]
- deleted_articles: []
- has_diff: true
- summary: "1 new article(s)"

Slack 通知内容:
- Article Count: 3 → 4
- New Articles: 1
- Deleted Articles: 0
- [記事D のタイトルと URL を表示]
```

## セキュリティに関する注意事項

### シークレット情報の管理

❌ **以下のことは絶対にしないでください**:
- Slack webhook URL をコード内に記載
- Secrets Manager の値をログに出力
- GitHub などのパブリックリポジトリに webhook URL を含むファイルをコミット

✅ **推奨される方法**:
- AWS Secrets Manager を使用して webhook URL を管理
- Lambda 実行ロールに `secretsmanager:GetSecretValue` 権限を付与
- `.gitignore` で `.env` や `.secret` ファイルを除外

### IAM 権限の最小化

Lambda 実行ロールには、必要最小限の権限のみを付与してください：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::playwright-output-bucket/news-yahoo/*"
    },
    {
      "Effect": "Allow",
      "Action": ["dynamodb:GetItem", "dynamodb:PutItem"],
      "Resource": "arn:aws:dynamodb:ap-northeast-1:ACCOUNT_ID:table/playwright-news-snapshot"
    },
    {
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": "arn:aws:secretsmanager:ap-northeast-1:ACCOUNT_ID:secret:SLACK_WEBHOOK_URL-*"
    }
  ]
}
```

## トラブルシューティング

### DynamoDB テーブルが見つからないエラー

```
[ERROR] Table playwright-news-snapshot does not exist
```

**対処法**:
```bash
./scripts/setup-dynamodb-snapshot.sh
```

### Slack Webhook が見つからないエラー

```
[ERROR] Failed to fetch webhook URL fro