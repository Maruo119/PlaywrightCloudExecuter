/**
 * アプリケーション設定（シークレット情報以外の定数）
 *
 * このファイルはソースコードに直接ハードコードするか、別の設定ファイルで管理される
 * アプリケーション設定値を定義します。
 *
 * シークレット情報（AWS認証情報など）は .env ファイルで管理してください。
 */

/**
 * Node環境
 */
export const DEFAULT_NODE_ENV = 'development';

/**
 * ログレベル
 */
export const DEFAULT_LOG_LEVEL = 'info';

/**
 * スクレイピング対象サイト名
 */
export const DEFAULT_SITE_NAME = 'yahoo';

/**
 * Playwright設定
 */
export const DEFAULT_BROWSER_HEADLESS = true;
export const DEFAULT_PAGE_TIMEOUT = 30000; // ミリ秒

/**
 * 設定オブジェクト（まとめた形）
 */
export const DEFAULT_CONFIG = {
  nodeEnv: DEFAULT_NODE_ENV,
  logLevel: DEFAULT_LOG_LEVEL,
  siteName: DEFAULT_SITE_NAME,
  browserHeadless: DEFAULT_BROWSER_HEADLESS,
  pageTimeout: DEFAULT_PAGE_TIMEOUT,
} as const;
