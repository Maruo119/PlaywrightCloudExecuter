# アーキテクチャ

## システム全体図

```
┌─────────────────────────────────────────────────────────────────┐
│                    AWS CloudWatch                                │
│              (実行ログ、メトリクス監視)                         │
└─────────────────────────────────────────────────────────────────┘
                         ▲
                         │ ログ送信
                         │
┌─────────────────────────────────────────────────────────────────┐
│                    EventBridge                                   │
│              (1時間ごとにLambda関数を実行)                      │
└────────────────────────────┬────────────────────────────────────┘
                             │ RunTask命令
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│              AWS Lambda (Python)                                │
│         (Fargateタスクをすぐに起動して終了)                    │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│         AWS ECS Fargate                                          │
│    (0.5vCPU / 1GB メモリでコンテナ実行)                        │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Playwright Cloud Executer Container                    │  │
│  │                                                          │  │
│  │  ├─ browser-manager.ts (Playwright制御)               │  │
│  │  ├─ logger.ts (Winston ロギング)                       │  │
│  │  ├─ error-handler.ts (エラー・リトライ)              │  │
│  │  ├─ config-loader.ts (設定管理)                       │  │
│  │  └─ site/yahoo/scraper.ts (Yahoo スクレイパー)       │  │
│  │     └─ title タグ取得 → S3 保存                       │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         ▼                   ▼                   ▼
 ┌──────────────┐  ┌─────────────────┐  ┌────────────┐
 │ Chromium     │  │ CloudWatch Logs │  │  AWS S3    │
 │ (ブラウザ)  │  │   (実行ログ)    │  │  (結果)    │
 └──────────────┘  └─────────────────┘  └────────────┘
         │
    https://www.yahoo.co.jp/
    (スクレイプ対象)
```

---

## コンポーネント説明

### 1. Playwright Cloud Executer (Node.js)

**役割**: Web スクレイピング自動化

**実装済み機能:**

```typescript
// ブラウザ管理
BrowserManager
├── launchBrowser()      // Chromium 起動
├── createPage()         // 新規ページ作成
├── navigate()           // URL アクセス
└── closeBrowser()       // リソース解放

// ログ機能
Logger (Winston)
├── info()              // 情報ログ
├── warn()              // 警告ログ
├── error()             // エラーログ
└── JSON フォーマット対応（CloudWatch）

// エラーハンドリング
ErrorHandler
├── PlaywrightError     // カスタムエラークラス
├── executeWithRetry()  // リトライロジック（最大3回）
└── ErrorCode enum      // エラーコード分類

// 設定管理
ConfigLoader
├── loadAppConfig()     // 環境変数から読み込み
└── loadSiteConfig()    // サイト別設定読み込み
```

### 2. Yahoo スクレイパー

**処理フロー:**

```
1. ブラウザセッション開始
2. https://www.yahoo.co.jp/ にアクセス
3. page.title() で title タグを取得
   → 「Yahoo! JAPAN」
4. S3 に保存
   キー: yahoo/title_1777901450774.txt
   内容:
   ─────────────────────────────
   Site Name: yahoo
   Base URL: https://www.yahoo.co.jp/
   Title: Yahoo! JAPAN
   Scraped At: 2025-01-01T12:34:56.789Z
   Timestamp: 1777901450774
   ─────────────────────────────
5. ブラウザセッション終了
```

**実装ファイル:**
- `src/site/yahoo/scraper.ts` - スクレイパーロジック
- `src/site/yahoo/config.json` - Yahoo 設定

#### 2.1 config.json の構造と利用方法

**ファイル**: `src/site/yahoo/config.json`

```json
{
  "name": "yahoo",
  "baseUrl": "https://www.yahoo.co.jp/",
  "description": "Yahoo Japan ホームページ",
  "selectors": {
    "title": "title"
  },
  "retryCount": 3,
  "timeout": 30000
}
```

**各フィールドの用途:**

| フィールド | 値 | 使用箇所 | 説明 |
|-----------|-----|--------|------|
| **name** | "yahoo" | scraper.ts | S3 キーの先頭パス |
| **baseUrl** | "https://www.yahoo.co.jp/" | index.ts, scraper.ts | ブラウザアクセス先 URL |
| **description** | "Yahoo Japan..." | ドキュメント | サイトの説明（参考用） |
| **selectors** | { "title": "title" } | scraper.ts | データ抽出用セレクタ（将来拡張用） |
| **retryCount** | 3 | error-handler.ts | リトライ回数設定 |
| **timeout** | 30000 | config-loader.ts | ページ操作タイムアウト（ms） |

**データロードフロー:**

```typescript
// 1. 環境変数から siteName を取得
const appConfig = loadAppConfig();  // SITE_NAME=yahoo

// 2. config.json をロード
const siteConfig = loadSiteConfig(appConfig.siteName);
// → src/site/yahoo/config.json が JSON.parse される

// 3. ロード結果
siteConfig = {
  name: "yahoo",
  baseUrl: "https://www.yahoo.co.jp/",
  selectors: { title: "title" },
  ...
}

// 4. 各処理で使用
browserManager.navigate(page, siteConfig.baseUrl);
// → "https://www.yahoo.co.jp/" にアクセス

new YahooScraper(siteConfig);
// → scraper 内で config.name が S3 キー生成に使用
```

**コード内での使用例:**

```typescript
// src/index.ts - config.json から baseUrl を取得
await browserManager.navigate(page, siteConfig.baseUrl);

// src/site/yahoo/scraper.ts - config.json から name を使用
const s3Key = `${this.config.name}/title_${data.timestamp}.txt`;
// → "yahoo/title_1777901450774.txt"

// S3 保存時にメタデータとして記録
const command = new PutObjectCommand({
  Bucket: s3Bucket,
  Key: s3Key,
  Body: content,
  Metadata: {
    'Site-Name': this.config.name,  // "yahoo"
    'Scraped-At': data.scrapedAt,
  },
});
```

**ログ出力例:**

```
] サイト設定をロードしました: yahoo
] Site: yahoo
] URL: https://www.yahoo.co.jp/
] S3に保存しています: s3://PlaywrightOutput/yahoo/title_1777901450774.txt
```

#### 2.2 複数サイト対応への拡張性

config.json の設計により、複数サイト対応が容易です。

**新しいサイト追加例（Amazon）:**

```
src/site/
├── yahoo/
│   ├── config.json
│   └── scraper.ts
└── amazon/
    ├── config.json           ← 新規作成
    └── scraper.ts            ← 新規作成
```

**amazon/config.json の例:**

```json
{
  "name": "amazon",
  "baseUrl": "https://www.amazon.co.jp/",
  "description": "Amazon Japan",
  "selectors": {
    "title": "title",
    "price": "span.a-price"
  },
  "retryCount": 3,
  "timeout": 30000
}
```

**環境変数で切り替え:**

```powershell
# Yahoo を実行
$env:SITE_NAME="yahoo"
npm run dev

# Amazon を実行
$env:SITE_NAME="amazon"
npm run dev
```

#### 2.3 将来の selectors 拡張

現在、selectors は `title` のみですが、将来複数データ抽出時に拡張可能：

```json
{
  "selectors": {
    "title": "title",
    "description": "meta[name='description']",
    "keywords": "meta[name='keywords']",
    "ogImage": "meta[property='og:image']"
  }
}
```

対応する scraper.ts の拡張：

```typescript
async scrapeMultipleData(page: Page): Promise<ScrapedData> {
  const data: ScrapedData = {
    title: await page.title(),
    description: await page.locator(this.config.selectors.description).textContent(),
    keywords: await page.locator(this.config.selectors.keywords).getAttribute('content'),
    ...
  };
  return data;
}
```

**メリット:**
- セレクタをコードから分離
- サイトごとの違いを config.json で管理
- 新しいサイト追加時の実装が簡潔
- 複数開発者でも一貫性を保ちやすい

### 3. EventBridge

**役割**: 定期スケジュール実行

- **スケジュール**: 1時間ごと（Cron: `0 * * * ? *`）
- **ターゲット**: Lambda 関数 `playwright-scheduler`
- **トランスフォーメーション**: `{ "site_name": "yahoo" }`

### 4. Lambda 関数（Python）

**役割**: Fargate タスク起動

- **ランタイム**: Python 3.11
- **タイムアウト**: 60秒
- **メモリ**: 128 MB
- **動作**: ECS RunTask → すぐに終了（タスク実行を待たない）

### 5. AWS S3 (PlaywrightOutput)

**役割**: スクレイプ結果保存

- **バケット名**: PlaywrightOutput
- **キー構造**: `{サイト名}/title_{タイムスタンプ}.txt`
- **例**: `yahoo/title_1777901450774.txt`

### 6. CloudWatch Logs

**役割**: 実行ログ記録

- **ロググループ**: `/ecs/playwright-cloud-executer`
- **リテンション**: 30日
- **ログ形式**: JSON（アプリケーションより）

---

## データフロー（実装済み）

```
実行開始
  │
  ▼
環境変数ロード ✓
  │ NODE_ENV, AWS_REGION, AWS_S3_BUCKET等
  ▼
サイト設定ロード ✓
  │ src/site/yahoo/config.json
  ▼
ロガー初期化 ✓
  │ Winston ロギング設定
  ▼
ブラウザ起動 ✓
  │ Chromium 起動（--disable-dev-shm-usage フラグ）
  │ メモリ効率化（0.5vCPU/1GB 環境対応）
  ▼
ページ作成 ✓
  │ 言語設定: 日本語
  │ タイムアウト: 30秒
  ▼
URL アクセス ✓
  │ https://www.yahoo.co.jp/
  │ waitUntil: 'load'
  ▼
Title 取得 ✓
  │ page.title() → 「Yahoo! JAPAN」
  │ リトライロジック: 最大3回（失敗時）
  ▼
S3 保存 ⏳
  │ PutObjectCommand
  │ キー: yahoo/title_{timestamp}.txt
  │ エラーハンドリング実装済み
  ▼
ブラウザ終了 ✓
  │ リソース解放
  ▼
実行終了 ✓
```

---

## セキュリティ考慮事項

### IAM 権限（フェーズ4で実装）

**Playwright-Role** (ECS 実行用):
- S3 読取・書込権限
- CloudWatch Logs 書込権限
- ECR 読取権限

**Playwright_User** (開発者用):
- ECS 操作権限
- ECR 管理権限
- CloudWatch Logs 読取権限

### ネットワーク

- VPC 内での実行（既存 VPC 使用）
- セキュリティグループで HTTPS (443) アウトバウンド許可
- NAT Gateway 経由でインターネットアクセス（プライベートサブネット実行時）

### リソース保護

- すべての AWS リソースに `PlaywrightCloudExecuter` タグ付与
- 環境変数で AWS クレデンシャル管理
- ログ保持期間: 30日（CloudWatch）

---

## リソース制限への対応（0.5vCPU / 1GB メモリ）

### ブラウザ最適化

```typescript
// メモリ効率化フラグ
const browserArgs = [
  '--disable-dev-shm-usage',      // メモリ使用量削減
  '--no-sandbox',                 // サンドボックス無効化
  '--disable-setuid-sandbox',     // セキュリティ機能簡略化
];
```

### タイムアウト設定

- **ページ読み込み**: 30秒以下
- **JavaScript 実行**: 30秒以下
- **リトライ待機**: 1秒間隔 × 最大3回

### メモリリーク防止

```typescript
// 確実なリソース解放
await browserManager.closePage(page);   // ページ明示的クローズ
await browserManager.closeBrowser();    // ブラウザ明示的クローズ
```

---

## スケーリング構想

### 複数サイト対応

```
EventBridge規則1 → Lambda1 → Fargate Task1 (yahoo)
EventBridge規則2 → Lambda2 → Fargate Task2 (site-a)
EventBridge規則3 → Lambda3 → Fargate Task3 (site-b)
```

### ディレクトリ構造（拡張可能）

```
src/site/
├── yahoo/
│   ├── scraper.ts
│   └── config.json
├── site-a/
│   ├── scraper.ts
│   └── config.json
└── site-b/
    ├── scraper.ts
    └── config.json
```

---

## エラーハンドリング

### リトライメカニズム（実装済み）

```typescript
executeWithRetry(fn, maxRetries = 3, delayMs = 1000)
│
├─ 試行 1/3 ✓ 成功 → リターン
├─ 試行 1/3 ✗ 失敗 → 1秒待機
├─ 試行 2/3 ✗ 失敗 → 1秒待機
├─ 試行 3/3 ✗ 失敗 → PlaywrightError スロー
```

### エラーコード分類（実装済み）

```typescript
enum ErrorCode {
  BROWSER_LAUNCH_ERROR,      // ブラウザ起動失敗
  PAGE_NAVIGATION_ERROR,     // ページアクセス失敗
  PAGE_EXTRACTION_ERROR,     // データ抽出失敗
  S3_UPLOAD_ERROR,          // S3 保存失敗
  RETRY_EXCEEDED_ERROR,      // リトライ超過
  ...
}
```

### ログレベル（実装済み）

| レベル | 出力内容 | ログレベル設定 |
|-------|--------|--------------|
| INFO | 処理進捗・完了メッセージ | LOG_LEVEL=info |
| WARN | リトライ時のメッセージ | LOG_LEVEL=warn |
| ERROR | エラー発生時のメッセージ | LOG_LEVEL=error |
| DEBUG | 詳細なデバッグ情報 | LOG_LEVEL=debug |

---

## 日本語対応（実装済み）

### ロケール設定

```typescript
// Dockerfile 内
ENV LANG=ja_JP.UTF-8
ENV LANGUAGE=ja_JP:ja
ENV LC_ALL=ja_JP.UTF-8
ENV TZ=Asia/Tokyo

// ユーザーエージェント
navigator.language = 'ja'
```

### エンコーディング

- **全ファイル**: UTF-8（統一）
- **S3 メタデータ**: UTF-8
- **ログ出力**: UTF-8

---

## 監視・アラート（フェーズ4以降）

### CloudWatch メトリクス

- タスク実行数
- 成功/失敗数
- 平均実行時間
- エラー率

### CloudWatch Logs

- アプリケーションログ
- エラースタックトレース
- S3 保存結果

### アラート設定（推奨）

- 失敗時の SNS 通知
- エラー率異常検知
- 実行時間異常検知

---

## デプロイメント構成

### フェーズ1: ローカル開発 ✓ 実装完了

```
npm install
npx playwright install
npm run dev
```

### フェーズ2: Docker コンテナ化 ✓ 実装完了

```
docker build -t playwright-cloud-executer:latest .
docker run --rm playwright-cloud-executer:latest
```

### フェーズ3-4: AWS デプロイ ⏳ 次ステップ

```
ECR プッシュ → ECS Fargate デプロイ → Lambda 連携 → EventBridge スケジュール
```

---

## パフォーマンス最適化

### 実行時間目標

- **Yahoo title 取得**: 5分以内
- **ブラウザ起動**: 10秒以内
- **ページロード**: 20秒以内
- **S3 保存**: 2秒以内

### メモリ使用量目標

- **Chromium**: 300-400 MB
- **Node.js アプリ**: 100-150 MB
- **合計**: 500-600 MB（1GB 以下）

### 実装済みの最適化

```typescript
// マルチステージ Docker ビルド
FROM playwright:v1.40.0 AS builder
  └─ ビルド時の不要なファイル削除

// Playwright 最適化フラグ
--disable-dev-shm-usage    // /dev/shm メモリ使用を回避
--no-sandbox               // サンドボックス無効化（セキュリティ許容範囲内）
```
