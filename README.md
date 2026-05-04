# Playwright Cloud Executer

PlaywrightをAWS Fargateで定期実行するシステムです。EventBridgeで1時間ごとにLambda関数を実行し、Fargateでコンテナを起動してPlaywrightタスクを実行します。

✅ **フェーズ1 実装完了**
- TypeScript 開発環境セットアップ完了
- Playwright ブラウザ自動化実装完了
- Yahoo スクレイパー実装完了（title 取得→S3 保存）
- ローカル動作確認済み

✅ **フェーズ2 実装完了**
- AWS Secrets Manager への移行完了
- ローカル・本番環境ともに Secrets Manager でシークレット管理

## プロジェクト構成

```
PlaywrightCloudExecuter/
├── playwright-app/          # Playwrightアプリケーション本体
│   ├── src/
│   │   ├── common/          # 共通処理（ブラウザ管理、ロギング等）
│   │   ├── site/            # サイト別処理
│   │   │   └── yahoo/       # Yahoo サイト処理
│   │   └── utils/           # ユーティリティ関数
│   ├── Dockerfile
│   ├── package.json
│   └── tsconfig.json
├── lambda-function/         # EventBridge連携Lambda関数（Python）
│   └── requirements.txt
└── docs/                    # ドキュメント
    ├── architecture.md
    ├── setup-guide.md
    └── aws-resources.md
```

## 機能

- **Playwrightによる自動化**: https://www.yahoo.co.jp/ から title タグを取得
- **S3への保存**: 取得結果をPlaywrightOutputバケットに格納
- **定期実行**: EventBridgeで1時間ごとに自動実行
- **スケーラビリティ**: サイト追加により複数サイトに対応可能
- **日本語対応**: 日本語コンテンツの正確な処理に対応
- **ログ記録**: CloudWatch Logsに実行ログを記録

## セットアップ

### ローカル開発環境での実行

本アプリケーションはすべての環境で **AWS Secrets Manager** を使用してシークレット情報を管理しています。

#### 前提条件

- AWS CLI がインストールされていること
- AWS アカウントに認証済みの AWS CLI プロファイルが設定されていること

#### AWS CLI プロファイルの設定

1. **AWS 認証情報を設定**
```bash
# AWS CLI の認証設定
aws configure --profile your-profile-name
# または既存プロファイルを使用
```

2. **環境変数で AWS プロファイルを指定**
```bash
export AWS_PROFILE=your-profile-name
```

#### アプリケーション実行手順

1. **依存パッケージのインストール**
```bash
cd playwright-app
npm install
```

2. **AWS Secrets Manager にシークレット値を事前登録**

アプリケーションは以下のシークレット値を Secrets Manager から読み込みます：

| シークレット ID | 説明 |
|--------------|------|
| `INFRA_AWS_REGION` | AWS リージョン（例：ap-northeast-1） |
| `INFRA_AWS_S3_BUCKET` | S3 バケット名（例：PlaywrightOutput） |
| `INFRA_AWS_ACCESS_KEY_ID` | AWS アクセスキー |
| `INFRA_SECRET_ACCESS_KEY` | AWS シークレットアクセスキー |

```bash
# 例：Secrets Manager にシークレットを作成
aws secretsmanager create-secret \
  --name INFRA_AWS_REGION \
  --secret-string "ap-northeast-1" \
  --profile your-profile-name

aws secretsmanager create-secret \
  --name INFRA_AWS_S3_BUCKET \
  --secret-string "PlaywrightOutput" \
  --profile your-profile-name

# その他のシークレットも同様に登録...
```

3. **TypeScriptのコンパイルと実行**
```bash
npm run dev
```

### Docker での実行

```bash
cd playwright-app
docker build -t playwright-cloud-executer:latest .
docker run --rm -e SITE_NAME=yahoo playwright-cloud-executer:latest
```

## AWS デプロイメント

詳細はdocs/に含まれるセットアップガイドを参照してください。

- `docs/setup-guide.md` : 初期セットアップ手順
- `docs/architecture.md` : アーキテクチャ説明
- `docs/aws-resources.md` : AWSリソース一覧

## 主な技術スタック

- **Playwright** (v1.40.0): ブラウザ自動化
- **Node.js**: アプリケーション開発
- **TypeScript**: 型安全性
- **AWS Fargate**: コンテナ実行基盤
- **AWS Lambda**: スケジューラー
- **EventBridge**: 定期実行トリガー
- **S3**: 結果保存先
- **CloudWatch**: ログ記録
- **AWS Secrets Manager**: シークレット情報管理

## 環境変数と設定

### シークレット管理（AWS Secrets Manager）

以下の設定値は **AWS Secrets Manager** で管理されます：

- `INFRA_AWS_REGION`: AWS リージョン
- `INFRA_AWS_S3_BUCKET`: S3 バケット名
- `INFRA_AWS_ACCESS_KEY_ID`: AWS アクセスキー
- `INFRA_SECRET_ACCESS_KEY`: AWS シークレットアクセスキー

### アプリケーション環境変数

以下の環境変数は通常の環境変数として設定できます：

```
NODE_ENV=production
LOG_LEVEL=info
SITE_NAME=yahoo
BROWSER_HEADLESS=true
PAGE_TIMEOUT=30000
AWS_PROFILE=your-profile-name  # ローカル開発時の AWS CLI プロファイル
```

## トラブルシューティング

ドキュメント内のトラブルシューティングガイドを参照してください。

## ライセンス

ISC
