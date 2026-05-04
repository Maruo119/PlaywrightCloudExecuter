# Playwright Cloud Executer

PlaywrightをAWS Fargateで定期実行するシステムです。EventBridgeで1時間ごとにLambda関数を実行し、Fargateでコンテナを起動してPlaywrightタスクを実行します。

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

1. **依存パッケージのインストール**
```bash
cd playwright-app
npm install
```

2. **環境変数ファイルの作成**
```bash
cp .env.example .env
# .envファイルを編集して必要な情報を入力
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

## 環境変数

```
NODE_ENV=production
AWS_REGION=ap-northeast-1
AWS_S3_BUCKET=PlaywrightOutput
AWS_ACCESS_KEY_ID=<your-key>
AWS_SECRET_ACCESS_KEY=<your-secret>
LOG_LEVEL=info
SITE_NAME=yahoo
BROWSER_HEADLESS=true
PAGE_TIMEOUT=30000
```

## トラブルシューティング

ドキュメント内のトラブルシューティングガイドを参照してください。

## ライセンス

ISC
