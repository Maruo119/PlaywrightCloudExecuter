import logger from './common/logger';
import BrowserManager from './common/browser-manager';
import { loadAppConfig, loadSiteConfig } from './common/config-loader';
import { handleError, PlaywrightError } from './common/error-handler';
import YahooScraper from './site/yahoo/scraper';

/**
 * メインアプリケーション
 */
async function main(): Promise<void> {
  const appConfig = await loadAppConfig();
  const siteConfig = loadSiteConfig(appConfig.siteName);

  logger.info('='.repeat(60));
  logger.info('Playwright Cloud Executer を起動しました');
  logger.info('='.repeat(60));
  logger.info(`Site: ${appConfig.siteName}`);
  logger.info(`URL: ${siteConfig.baseUrl}`);
  logger.info(`S3 Bucket: ${appConfig.awsS3Bucket}`);
  logger.info('='.repeat(60));

  const browserManager = new BrowserManager({
    headless: appConfig.browserHeadless,
    timeout: appConfig.pageTimeout,
  });

  try {
    // ブラウザを起動
    await browserManager.launchBrowser();

    // ページを作成
    const page = await browserManager.createPage();

    try {
      // URLにアクセス
      await browserManager.navigate(page, siteConfig.baseUrl);

      // スクレイパーのインスタンス化
      const scraper = new YahooScraper(siteConfig, appConfig.awsRegion);

      // スクレイプ実行
      const result = await scraper.scrape(page, appConfig.awsS3Bucket);

      logger.info('='.repeat(60));
      logger.info('処理が正常に完了しました');
      logger.info('='.repeat(60));
      logger.info(`取得したTitle: ${result.title}`);
      logger.info(`保存先: s3://${appConfig.awsS3Bucket}/${result.siteName}/title_${result.timestamp}.txt`);
      logger.info('='.repeat(60));

      process.exit(0);
    } finally {
      // ページを閉じる
      await browserManager.closePage(page);
    }
  } catch (error) {
    handleError(error, 'Main');
    logger.error('='.repeat(60));
    logger.error('処理が失敗しました');
    logger.error('='.repeat(60));

    if (error instanceof PlaywrightError) {
      logger.error(`Error Code: ${error.code}`);
    }

    process.exit(1);
  } finally {
    // ブラウザを閉じる
    await browserManager.closeBrowser();
  }
}

// アプリケーション実行
main().catch((error) => {
  logger.error('予期しないエラーが発生しました:', error);
  process.exit(1);
});
