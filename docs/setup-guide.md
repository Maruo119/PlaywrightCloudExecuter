# セットアップガイド

## ローカル開発環境

### 前提条件
- Node.js 18+ がインストールされていること
- npm または yarn がインストールされていること
- Docker がインストールされていること（コンテナ実行時）
- AWS CLI v2 がインストールされていること（AWS連携時）

### 1. 依存パッケージのインストール

```bash
cd playwright-app
npm install
```

### 2. 環境変数の設定

```bash
cp .env.example .env
```

`.env` ファイルを編集して、以下を設定：

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

### 3. ローカルでの実行

**開発モード（TypeScript直接実行）**
```bash
npm run dev
```

**本番モード（ビルド後実行）**
```bash
npm run start
```

### 4. ビルド

```bash
npm run build
```

ビルド後、`dist/` ディレクトリに JavaScript ファイルが生成されます。

## Docker でのローカルテスト

### 1. Docker イメージのビルド

```bash
cd playwright-app
docker build -t playwright-cloud-executer:latest .
```

ビルドに 3-5 分かかります。

### 2. Docker コンテナの実行

```bash
docker run --rm -e SITE_NAME=yahoo playwright-cloud-executer:latest
```

### 3. 環境変数を指定しての実行（S3連携）

```bash
docker run --rm \
  -e SITE_NAME=yahoo \
  -e AWS_REGION=ap-northeast-1 \
  -e AWS_S3_BUCKET=PlaywrightOutput \
  -e AWS_ACCESS_KEY_ID=your_access_key \
  -e AWS_SECRET_ACCESS_KEY=your_secret_key \
  playwright-cloud-executer:latest
```

## AWS リソースのセットアップ

詳細は `docs/aws-resources.md` を参照してください。

### 概要

1. **IAM設定**
   - ロール: `Playwright-Role`
   - ユーザー: `Playwright_User`

2. **ECR リポジトリ作成**
   - リポジトリ名: `playwright-cloud-executer`

3. **CloudWatch Logs グループ作成**
   - ロググループ名: `/ecs/playwright-cloud-executer`

4. **ECS Fargate クラスター・タスク定義作成**
   - クラスター: `playwright-cloud-executer-cluster`
   - タスク定義: `playwright-cloud-executer`

5. **Lambda 関数作成**
   - 関数名: `playwright-scheduler`

6. **EventBridge 規則作成**
   - 規則名: `playwright-hourly-schedule`
   - スケジュール: `0 * * * ? *` (毎時0分)

## トラブルシューティング

### Node.js コンパイルエラー

**エラー: `npm ERR! ERR! code ERESOLVE`**

解決方法：
```bash
npm install --legacy-peer-deps
```

### Docker ビルド失敗

**エラー: `no space left on device`**

解決方法：
```bash
docker system prune -a
docker image prune -a
```

### Playwright ブラウザ起動エラー

**エラー: `Chromium is not available`**

解決方法：
- Dockerfile が `mcr.microsoft.com/playwright:v1.40.0-focal` ベースイメージを使用していることを確認
- Docker イメージを再ビルド

### S3 アクセスエラー

**エラー: `The AWS Access Key Id you provided does not exist`**

解決方法：
- `.env` の `AWS_ACCESS_KEY_ID` と `AWS_SECRET_ACCESS_KEY` を確認
- IAM ユーザーが `S3 Read/Write` 権限を持っていることを確認
- Playwright_User に適切な IAM ポリシーが付与されていることを確認

### CloudWatch Logs にログが出力されない

解決方法：
- ECS タスク実行ロール（Playwright-Role）が `CloudWatchLogsFullAccess` ポリシーを持っていることを確認
- CloudWatch ロググループ `/ecs/playwright-cloud-executer` が作成されていることを確認
- Lambda 関数がタスク定義の `logConfiguration` を正しく設定していることを確認

## 動作確認チェックリスト

ローカルデプロイ時の確認項目：

- [ ] `npm install` が成功している
- [ ] `npm run dev` でアプリが起動できる
- [ ] `docker build` でイメージビルドが成功している
- [ ] `docker run` でコンテナが起動し、エラーなく終了している
- [ ] Docker ログに "処理が正常に完了しました" というメッセージが表示されている

AWS デプロイ時の確認項目：

- [ ] IAM ロール・ユーザーが作成されている
- [ ] ECR リポジトリが作成されている
- [ ] Docker イメージが ECR にプッシュされている
- [ ] ECS クラスター・タスク定義が作成されている
- [ ] Lambda 関数が作成されている
- [ ] EventBridge 規則が作成されている
- [ ] Lambda 関数テスト実行で Fargate タスクが起動している
- [ ] CloudWatch Logs にログが出力されている
- [ ] S3 PlaywrightOutput バケットに結果ファイルが保存されている

## よくある質問

**Q: どのくらいの頻度でスクレイプできるか？**
A: EventBridge で1時間ごとに実行されます。より頻繁に実行したい場合は、EventBridge 規則の Cron 式を変更してください。

**Q: 複数のサイトをスクレイプできるか？**
A: はい。`src/site/` 配下に新しいサイトフォルダを追加し、対応する EventBridge 規則を作成することで対応できます。

**Q: スクレイプ結果はどこに保存されるか？**
A: AWS S3 の `PlaywrightOutput` バケットに保存されます。キーは `{サイト名}/title_{timestamp}.txt` 形式です。

**Q: エラーが発生した場合はどうするか？**
A: CloudWatch Logs の `/ecs/playwright-cloud-executer` ロググループを確認してください。詳細なエラーメッセージが記録されています。
