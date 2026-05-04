import { chromium, Browser, Page } from 'playwright';
import logger from './logger';

interface BrowserConfig {
  headless?: boolean;
  timeout?: number;
  proxy?: {
    server: string;
  };
}

class BrowserManager {
  private browser: Browser | null = null;
  private config: BrowserConfig;

  constructor(config: BrowserConfig = {}) {
    this.config = {
      headless: config.headless !== false,
      timeout: config.timeout || 30000,
      ...config,
    };
  }

  /**
   * ブラウザを起動する
   */
  async launchBrowser(): Promise<Browser> {
    try {
      logger.info('ブラウザを起動しています...');

      const browserArgs: string[] = [
        '--disable-dev-shm-usage', // メモリ効率化（0.5vCPU/1GB環境対応）
        '--no-sandbox',             // サンドボックス無効化
        '--disable-setuid-sandbox',
      ];

      this.browser = await chromium.launch({
        headless: this.config.headless,
        args: browserArgs,
      });

      logger.info('ブラウザが正常に起動しました');
      return this.browser;
    } catch (error) {
      logger.error('ブラウザ起動エラー:', error);
      throw error;
    }
  }

  /**
   * 新しいページを作成する
   */
  async createPage(): Promise<Page> {
    if (!this.browser) {
      throw new Error('ブラウザがまだ起動していません。先にlaunchBrowser()を呼び出してください。');
    }

    try {
      const page = await this.browser.newPage();

      // ページタイムアウト設定
      page.setDefaultTimeout(this.config.timeout!);
      page.setDefaultNavigationTimeout(this.config.timeout!);

      // ユーザーエージェント設定（日本語環境）
      await page.context().addInitScript(() => {
        Object.defineProperty(navigator, 'language', {
          get: () => 'ja',
        });
      });

      logger.info('新しいページを作成しました');
      return page;
    } catch (error) {
      logger.error('ページ作成エラー:', error);
      throw error;
    }
  }

  /**
   * URLにアクセス
   */
  async navigate(page: Page, url: string): Promise<void> {
    try {
      logger.info(`${url} にアクセスしています...`);
      await page.goto(url, { waitUntil: 'load' });
      logger.info(`${url} へのアクセスが完了しました`);
    } catch (error) {
      logger.error(`${url} へのアクセスエラー:`, error);
      throw error;
    }
  }

  /**
   * ページを閉じる
   */
  async closePage(page: Page): Promise<void> {
    try {
      await page.close();
      logger.info('ページを閉じました');
    } catch (error) {
      logger.error('ページクローズエラー:', error);
    }
  }

  /**
   * ブラウザを閉じる
   */
  async closeBrowser(): Promise<void> {
    try {
      if (this.browser) {
        await this.browser.close();
        this.browser = null;
        logger.info('ブラウザを閉じました');
      }
    } catch (error) {
      logger.error('ブラウザクローズエラー:', error);
    }
  }

  /**
   * ブラウザが開いているかチェック
   */
  isOpen(): boolean {
    return this.browser !== null;
  }
}

export default BrowserManager;
