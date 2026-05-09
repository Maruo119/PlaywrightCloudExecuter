# Playwright Cloud Executer - システムアーキテクチャ

## 概要

このシステムは、AWS 上で Playwright を使用した Web スクレイピングを定期実行し、結果を S3 に保存した後、自動的に差分検出して Slack で通知するエンドツーエンドのワークフローです。

## システムアーキテクチャ全体

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  ┌──────────────┐                                              │
│  │ EventBridge  │                                              │
│  │(1時間ごと)   │                                              │
│  └──────┬───────┘                                              │
│         │                                                      │
│         ▼                                                      │
│  ┌──────────────────────────────────────────┐                 │
│  │  Lambda (index.py)                       │                 │
│  │  Fargate Task Launcher                   │                 │
│  └──────────┬───────────────────────────────┘                 │
│             │                                                  │
│             ▼                                                  │
│  ┌──────────────────────────────────────────┐                 │
│  │  ECS Fargate Container                   │                 │
│  │  ├─ Playwright実行 (フェーズ1-3)         │                 │
│  │  ├─ Yahoo スクレイピング                 │                 │
│  │  └─ S3 へ保存                            │                 │
│  └──────────┬───────────────────────────────┘                 │
│             │                                                  │
│             ▼                                                  │
│         ┌─────────────┐                                       │
│         │   S3        │                                       │
│         │ playwright- │  articles_*.json                      │
│         │ output-     │  ┌─────────────┐                      │
│         │ bucket      │  │news-yahoo/  │                      │
│         └──────┬──────┘  │articles_... │                      │
│                │         └─────────────┘                      │
│                │ PutObject Event                              │
│                │                                              │
│                ▼                                              │
│         ┌─────────────────────────────────────┐               │
│         │  Lambda (lambda_handler.py)         │               │
│         │  S3 Event Processor (フェーズ4)    │               │
│         │  ├─ S3 ファイルダウンロード         │               │
│         │  ├─ 差分検出                       │               │
│         │  ├─ DynamoDB スナップショット更新 │               │
│         │  └─ Slack 通知                     │               │
│         └──────┬────────────────────────────┘               │
│                │                                              │
│    ┌───────────┼───────────┐                                 │
│    ▼           ▼           ▼                                 │
│  ┌─────────┐ ┌──────────┐ ┌────────────────┐                │
│  │DynamoDB │ │CloudWatch│ │ Slack Webhook  │                │
│  │snapshot │ │  Logs    │ │ (Notification) │                │
│  └─────────┘ └──────────┘ └────────────────┘                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## フェーズ別実装

### フェーズ 1-3: Playwright スクレイピング

#### 実行フロー

```
EventBridge (定期トリガー: 毎時00分)
  ↓
Lambda (index.py) - ECS タスク起動
  ↓
ECS Fargate Task
  ├─ Phase 1: Yahoo ホームページスクレイピング
  │  ├─ URL: https://www.yahoo.co.jp/
  │  ├─ 対象: <title> タグ
  │  └─ 出力: S3://playwright-output-bucket/yahoo/title_{timestamp}.txt
  │
  └─ Phase 2: Yahoo ニューススクレイピング
     ├─ URL: https://news.yahoo.co.jp/
     ├─ 対象: ニュース記事タイトル・URL
     └─ 出力: S3://playwright-output-bucket/news-yahoo/articles_{timestamp}.json
```

#### 主要コンポーネント

| コンポーネント | 責務 | 技術スタック |
|--------------|------|-------------|
| `playwright-app/src/site/yahoo/scraper.ts` | Yahoo ホームページスクレイピング | Playwright, TypeScript |
| `playwright-app/src/site/news-yahoo/scraper.ts` | Yahoo ニューススクレイピング | Playwright, TypeScript |
| `playwright-app/src/common/` | ブラウザ管理、ロギング、エラー処理 | TypeScript |
| `lambda-function/index.py` | ECS タスク起動 | Python, boto3 |
| EventBridge | 1 時間ごとのスケジュール実行 | AWS Events |

#### データフォーマット

**Phase 2 出力（news-yahoo/articles_*.json）**:
```json
{
  "siteName": "news-yahoo",
  "baseUrl": "https://news.yahoo.co.jp/",
  "articleCount": 8,
  "articles": [
    {
      "title": "記事タイトル",
      "url": "https://news.yahoo.co.jp/pickup/XXXXXX"
    }
  ],
  "scrapedAt": "2026-05-09T14:30:00.000Z",
  "timestamp": 1777991557552
}
```

---

### フェーズ 4: S3 イベント駆動型の差分検出・Slack 通知

#### 実行フロー

```
ECS (Phase 1-3) が S3 に articles_*.json を登録
  ↓
S3 PutObject Event (news-yahoo/articles_*.json)
  ↓
Lambda Trigger (lambda_handler.py)
  ├─ ① S3 からファイルをダウンロード・解析
  ├─ ② DynamoDB から前回のスナップショットを取得
  ├─ ③ 記事 URL で差分検出
  │  ├─ New URLs: 前回にないURL（新規記事）
  │  └─ Deleted URLs: 今回にないURL（削除記事）
  ├─ ④ 差分がある場合 → Slack Webhook で通知
  └─ ⑤ DynamoDB に新規スナップショットを保存（次回用）
```

#### 主要コンポーネント

| コンポーネント | 責務 | 技術スタック |
|--------------|------|-------------|
| `lambda-function/lambda_handler.py` | S3 イベント処理・全体フロー制御 | Python, Lambda |
| `lambda-function/src/diff_detector.py` | 差分検出エンジン（URL比較） | Python |
| `lambda-function/src/slack_notifier.py` | Slack Webhook 通知 | Python, requests |
| `lambda-function/src/dynamodb_snapshot_manager.py` | スナップショット管理 | Python, boto3 |

#### 差分検出ロジック

```python
# URL セットで比較（タイムスタンプなし）
current_urls = {article['url'] for article in current_articles}
previous_urls = {article['url'] for article in previous_articles}

new_urls = current_urls - previous_urls        # 新規記事
deleted_urls = previous_urls - current_urls    # 削除記事
```

**判定ルール**:
- ✅ URL をユニークキーとして扱う
- ✅ 記事の順序変更は差分として扱わない
- ✅ タイトル変更のみの場合も差分なし

#### DynamoDB スナップショット

**テーブル**: `playwright-news-snapshot`

| 属性 | 型 | 説明 |
|------|-----|------|
| `site` | String (PK) | サイト名（例: `news-yahoo`） |
| `articles` | String | 前回の articles 配列を JSON 文字列で保存 |
| `articleCount` | Number | 前回の記事数 |
| `scrapedAt` | String | スクレイピング実行時刻（ISO 8601） |
| `timestamp` | Number | Unix タイムスタンプ |
| `lastUpdatedAt` | String | スナップショット更新時刻 |

**実行パターン**:

| 実行回 | DynamoDB | 動作 |
|--------|----------|------|
| 初回（1回目） | レコードなし | スナップショット保存のみ（通知なし） |
| 2回目以降 | 前回のレコード存在 | 差分検出 → 通知判定 → スナップショット更新 |

---

## AWS リソース構成

### コンピュート

| リソース | 用途 | 設定 |
|---------|------|------|
| **EventBridge** | スケジュール実行トリガー | 毎時 00 分（Cron: `0 * * * ? *`） |
| **Lambda (index.py)** | ECS Fargate タスク起動（フェーズ1-3） | Python 3.11, 256 MB, 60 秒 |
| **Lambda (lambda_handler.py)** | S3 イベント駆動型差分検出（フェーズ4） | Python 3.11, 256 MB, 60 秒 |
| **ECS Fargate** | Playwright スクレイピング実行 | 0.5 vCPU, 1 GB メモリ |
| **ECR** | Docker イメージレジストリ | `playwright-cloud-executer:latest` |

### ストレージ・データベース

| リソース | 用途 | 設定 |
|---------|------|------|
| **S3** `playwright-output-bucket` | スクレイピング結果、JSON ファイル保存 | 標準ストレージクラス |
| **DynamoDB** `playwright-news-snapshot` | 記事スナップショット保存 | オンデマンド課金 |

### セキュリティ・管理

| リソース | 用途 |
|---------|------|
| **Secrets Manager** | Slack Webhook URL 管理（`SLACK_WEBHOOK_URL_NEW`） |
| **IAM Roles & Policies** | Lambda、ECS の実行権限制御 |

### ロギング・モニタリング

| リソース | 用途 |
|---------|------|
| **CloudWatch Logs** | Lambda、ECS 実行ログ記録 |
| **CloudWatch Metrics** | Lambda 実行回数、エラー率、実行時間 |

---

## セキュリティ設計

### シークレット管理

```
Slack Webhook URL
  ↓
AWS Secrets Manager (SLACK_WEBHOOK_URL_NEW)
  ↓ (Lambda で IAM Role経由でアクセス)
  ↓
slack_notifier.py で使用
```

**重要**:
- ✅ webhook URL はコードに含めない
- ✅ Secrets Manager で一元管理・暗号化
- ✅ CloudWatch Logs には出力しない
- ✅ GitHub にコミットされない設定

### IAM 最小権限原則

**Lambda 実行ロール (LambdaTriget_S3/S3updateDetectorForNewsUpdates)**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::playwright-output-bucket/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DescribeTable"
      ],
      "Resource": "arn:aws:dynamodb:ap-northeast-1:*:table/playwright-news-snapshot"
    },
    {
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": "arn:aws:secretsmanager:ap-northeast-1:*:secret:SLACK_WEBHOOK_URL_NEW*"
    }
  ]
}
```

### データ保護

- ✅ webhook URL は Secrets Manager で暗号化・保存
- ✅ DynamoDB はオンデマンド課金（スケーラブル）
- ✅ CloudWatch Logs のシークレット値は出力しない
- ✅ `.gitignore` で `.env` ファイルを除外

---

## 拡張性とスケーラビリティ

### 新しいスクレイピング対象の追加

```
1. playwright-app/src/site/{site-name}/ に新規スクレイパー実装
2. lambda-function/index.py で新しいフェーズを追加
3. S3 出力パス: {site-name}/articles_{timestamp}.json
4. DynamoDB: site キーで自動的に対応
5. S3 イベント通知フィルターに {site-name}/ prefix を追加
```

### 複数 Slack チャネル対応

```
1. Secrets Manager: SLACK_WEBHOOK_URL_{site-name} を複数作成
2. slack_notifier.py で site に応じて Webhook URL を切り替え
3. サイトごとに異なるチャネルに通知可能
```

### パフォーマンスチューニング

| パラメータ | 推奨値 | 理由 |
|----------|-------|------|
| Lambda タイムアウト | 60 秒 | DynamoDB、S3 API レスポンス時間を考慮 |
| Lambda メモリ | 256 MB | JSON パース・Slack 通知に十分 |
| DynamoDB 課金 | On-demand | 不定期の実行パターンに対応 |
| S3 イベント | news-yahoo/ prefix | 不要なトリガーを回避 |

---

## 処理フロー例

### ユースケース: 新規記事が 1 件追加された場合

```
【フェーズ 1-3】
時刻 14:00: ECS が Yahoo ニュースをスクレイピング
  前回: [記事A, 記事B, 記事C]（3件）
  新規: [記事A, 記事B, 記事C, 記事D]（4件）
  ↓
時刻 14:00: S3 に articles_1778256429268.json を保存
  ↓
【フェーズ 4】
S3 PutObject イベント発火
  ↓
Lambda (lambda_handler.py) トリガー
  ① S3 から articles_1778256429268.json をダウンロード
  ② DynamoDB から前回のスナップショット取得
     [記事A, 記事B, 記事C]
  ③ URL で差分検出
     新規: [記事D]（前回にない URL）
     削除: []
  ④ 差分あり → Slack 通知
     「📰 news-yahoo - News Article Update
      Article Count: 3 → 4
      New Articles: 1
      • 記事D のタイトル」
  ⑤ DynamoDB スナップショット更新
     [記事A, 記事B, 記事C, 記事D]

【次回実行時（15:00）】
DynamoDB から前回のスナップショット取得
  [記事A, 記事B, 記事C, 記事D]
↓
新規スクレイピング結果と比較
↓
差分有無を判定・通知
```

---

## トラブルシューティング

### 症状: 差分検出されない

**原因**: 前回と今回で同じ URL セット

**確認方法**:
```bash
aws logs tail /aws/lambda/playground-s3-diff-detector --follow
# ログに「No difference detected」が出力される → 正常
```

### 症状: Slack 通知されない

**確認項目**:
1. Secrets Manager に `SLACK_WEBHOOK_URL_NEW` が存在するか確認
2. webhook URL が正しい形式か（`https://hooks.slack.com/services/...`）
3. Lambda 実行ロールに `secretsmanager:GetSecretValue` 権限があるか確認
4. CloudWatch Logs でエラーメッセージを確認

### 症状: Lambda がトリガーされない

**確認項目**:
1. S3 イベント通知設定を確認
   ```bash
   aws s3api get-bucket-notification-configuration \
     --bucket playwright-output-bucket
   ```
2. イベントフィルター（prefix: `news-yahoo/`, suffix: `.json`）が正しいか確認
3. Lambda に `s3:GetObject` 権限があるか確認

---

## 参考ドキュメント

- `docs/setup-guide.md` - 初期セットアップ手順
- `docs/s3-event-lambda-design.md` - フェーズ 4 詳細設計書
- `docs/lambda-console-setup-guide.md` - Lambda 作成手順（AWS Console UI）
- `docs/aws-resources.md` - AWS リソース一覧
- `lambda-function/README.md` - Lambda 関数デプロイガイド
