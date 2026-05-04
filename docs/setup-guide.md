# セットアップガイド

## ✅ 実装状況

- ✓ Node.js / TypeScript 開発環境
- ✓ Playwright ブラウザ自動化
- ✓ Yahoo スクレイパー（title 取得）
- ✓ S3 連携コード実装
- ✓ ログ機能（Winston）
- ✓ エラーハンドリング・リトライロジック
- ✓ Docker コンテナ化対応
- ⏳ AWS Fargate / Lambda デプロイ（フェーズ4以降）

---

## ローカル開発環境

### 前提条件

- **Node.js 18+** ✓ 動作確認済み（v25.8.0）
- **npm 10+** ✓ 動作確認済み
- Docker（コンテナ実行時）
- AWS CLI v2（AWS デプロイ時）

### ステップ1: 依存パッケージのインストール

```powershell
cd C:\Users\umesk\OneDrive\ドキュメント\Claude\Projects\PlaywrightCloudExecuter\playwright-app
npm install
```

### ステップ2: Playwright ブラウザをインストール

```powershell
npx playwright install
```

**重要**: Chromium などのブラウザバイナリをダウンロードします（3-5分、400-500MB）

### ステップ3: 環境変数を設定

```powershell
cp .env.example .env
```

`.env` ファイルを編集：

```env
NODE_ENV=development
AWS_REGION=ap-northeast-1
AWS_S3_BUCKET=PlaywrightOutput
AWS_ACCESS_KEY_ID=your_access_key_here
AWS_SECRET_ACCESS_KEY=your_secret_key_here
LOG_LEVEL=info
SITE_NAME=yahoo
BROWSER_HEADLESS=true
PAGE_TIMEOUT=30000
```

### ステップ4: 開発モードで実行

```powershell
npm run dev
```

**期待される出力:**
```
] アプリケーション設定をロードしました
] ブラウザが正常に起動しました
] https://www.yahoo.co.jp/ へのアクセスが完了しました
] title を取得しました: Yahoo! JAPAN
] S3に保存しています: s3://PlaywrightOutput/yahoo/title_xxxx.txt
```

### ステップ5: 本番モードで実行（ビルド後）

```powershell
npm run build
node dist/index.js
```

---

## Docker でのテスト

### イメージビルド

```powershell
docker build -t playwright-cloud-executer:latest .
```

### コンテナ実行

```powershell
docker run --rm -e SITE_NAME=yahoo playwright-cloud-executer:latest
```

**環境変数を指定して実行:**

```powershell
docker run --rm `
  -e SITE_NAME=yahoo `
  -e AWS_REGION=ap-northeast-1 `
  -e AWS_S3_BUCKET=PlaywrightOutput `
  -e AWS_ACCESS_KEY_ID=your_key `
  -e AWS_SECRET_ACCESS_KEY=your_secret `
  playwright-cloud-executer:latest
```

---

## トラブルシューティング

### 「ts-node: command not found」

**原因:** npm install が完全に完了していない

**解決:**
```powershell
npm install
```

### 「Executable doesn't exist」（Chromium が見つからない）

**原因:** Playwright ブラウザがインストールされていない

**解決:**
```powershell
npx playwright install
```

### 「Cannot find name 'navigator'」（TypeScript エラー）

**原因:** tsconfig.json に DOM 型定義がない

**解決:** `tsconfig.json` の `lib` に `"dom"` を追加済み

### S3 エラー「The specified bucket does not exist」

**原因:** S3 バケット `PlaywrightOutput` がまだ AWS に作成されていない

**解決:** AWS フェーズ4 で S3 バケットを作成
- または、AWS 認証情報を修正

### S3 エラー「The AWS Access Key Id you provided does not exist」

**原因:** `.env` の AWS 認証情報が正しくない

**解決:**
1. AWS IAM ユーザー `Playwright_User` のアクセスキーを確認
2. `.env` に正しく入力
3. IAM ユーザーが `S3FullAccess` ポリシーを持つか確認

---

## 実装済み機能

### ログ機能

Winston ロギングで以下が出力されます：

```
[timestamp] [INFO] メッセージ
[timestamp] [ERROR] エラーメッセージ
```

CloudWatch Logs 互換の JSON フォーマットでも出力可能

### エラーハンドリング

- **リトライロジック**: 失敗時に最大3回まで自動リトライ（1秒間隔）
- **カスタムエラークラス**: `PlaywrightError` でエラーコード管理
- **スタックトレース**: 詳細なエラー情報をログに記録

### 日本語対応

- タイムゾーン: Asia/Tokyo
- ロケール: ja_JP.UTF-8
- エンコーディング: UTF-8 統一
- ユーザーエージェント: 日本語設定

---

## 次のステップ

### フェーズ2: ローカル動作確認（現在）

- ✅ `npm run dev` で実行確認
- ✅ Yahoo から title 取得確認
- ✅ ログ出力確認

### フェーズ3: Docker テスト

```bash
docker build -t playwright-cloud-executer:latest .
docker run --rm playwright-cloud-executer:latest
```

### フェーズ4: AWS 環境構築

- IAM ロール・ユーザー作成
- ECR リポジトリ作成
- S3 バケット作成（PlaywrightOutput）
- ECS Fargate クラスター・タスク定義作成
- Lambda 関数作成
- EventBridge 規則設定

---

## よくある質問

**Q: S3 認証情報がないままテストできますか？**

A: はい。スクレイパーで S3 保存までのロジックを確認できます。S3 エラーは想定通りです。

**Q: 複数のサイトをスクレイプしたいです**

A: `src/site/` 配下に新しいサイトフォルダを追加してください。
```
src/site/
├── yahoo/
└── your-site-name/
    ├── scraper.ts
    └── config.json
```

**Q: ローカルではうまく動作するが、Docker で動作しない**

A: 以下を確認してください：
- `.env` が Docker 環境変数として設定されているか
- AWS 認証情報が正しいか
- S3 バケットが存在するか

---

## 環境変数リファレンス

| 変数 | 説明 | デフォルト | 必須 |
|------|------|----------|------|
| NODE_ENV | 実行環境（development/production） | development | - |
| LOG_LEVEL | ログレベル（debug/info/warn/error） | info | - |
| SITE_NAME | スクレイプ対象サイト | yahoo | ○ |
| AWS_REGION | AWS リージョン | ap-northeast-1 | ○ |
| AWS_S3_BUCKET | S3 バケット名 | PlaywrightOutput | ○ |
| AWS_ACCESS_KEY_ID | AWS アクセスキー | - | ○ (S3 保存時) |
| AWS_SECRET_ACCESS_KEY | AWS シークレットキー | - | ○ (S3 保存時) |
| BROWSER_HEADLESS | ヘッドレスモード | true | - |
| PAGE_TIMEOUT | ページタイムアウト（ms） | 30000 | - |
