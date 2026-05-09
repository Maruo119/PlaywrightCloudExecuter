import logger from './common/logger';
import BrowserManager from './common/browser-manager';
import { loadAppConfig, loadSiteConfig } from './common/config-loader';
import { handleError, PlaywrightError } from './common/error-handler';
import YahooScraper from './site/yahoo/scraper';
import NewsYahooScraper from './site/news-yahoo/scraper';

/**
 * メインアプリケーション
 * 複数サイトを直列処理で実行
 */
async function main(): Promise<void> {
  const appConfig = await loadAppConfig();

  logger.info('='.repeat(60));
  logger.info('Playwright Cloud Executer を起動しました');
  logger.info('='.repeat(60));
  logger.info(`AWS Region: ${appConfig.awsRegion}`);
  logger.info(`S3 Bucket: ${appConfig.awsS3Bucket}`);
  logger.info('='.repeat(60));

  const browserManager = new BrowserManager({
    headless: appConfig.browserHeadless,
    timeout: appConfig.pageTimeout,
  });

  try {
    // ブラウザを起動（複数サイト共有）
    await browserManager.launchBrowser();

    // ========== Phase 1: Yahoo ホームページ ==========
    logger.info('='.repeat(60));
    logger.info('【Phase 1】 Yahoo スクレイピング開始');
    logger.info('='.repeat(60));

    const yahooConfig = loadSiteConfig('yahoo');
    const yahooPage = await browserManager.createPage();

    try {
      // Yahoo にアクセス
      await browserManager.navigate(yahooPage, yahooConfig.baseUrl);

      // Yahoo スクレイパーを実行
      const yahooScraper = new YahooScraper(yahooConfig, appConfig.awsRegion);
      const yahooResult = await yahooScraper.scrape(yahooPage, appConfig.awsS3Bucket);

      logger.info('='.repeat(60));
      logger.info('【Phase 1 完了】 Yahoo スクレイピング成功');
      logger.info('='.repeat(60));
      logger.info(`取得したTitle: ${yahooResult.title}`);
      logger.info(`保存先: s3://${appConfig.awsS3Bucket}/${yahooResult.siteName}/title_${yahooResult.timestamp}.txt`);
      logger.info('='.repeat(60));
    } catch (error) {
      logger.error('='.repeat(60));
      logger.error('【Phase 1 失敗】 Yahoo スクレイピングに失敗しました');
      logger.error('='.repeat(60));
      if (error instanceof PlaywrightError) {
        logger.error(`Error Code: ${error.code}`);
      }
      // Phase 1 失敗時も Phase 2 を続行する
    } finally {
      await browserManager.closePage(yahooPage);
    }

    // ========== Phase 2: Yahoo ニュース ==========
    logger.info('='.repeat(60));
    logger.info('【Phase 2】 Yahoo ニュース スクレイピング開始');
    logger.info('='.repeat(60));

    const newsYahooPage = await browserManager.createPage();

    try {
      // Yahoo ニュースにアクセス
      const newsYahooBaseUrl = 'https://news.yahoo.co.jp/';
      await browserManager.navigate(newsYahooPage, newsYahooBaseUrl);

      // Yahoo ニュース スクレイパーを実行
      const newsYahooScraper = new NewsYahooScraper(appConfig.awsRegion);
      const newsYahooResult = await newsYahooScraper.scrape(newsYahooPage, appConfig.awsS3Bucket);

      logger.info('='.repeat(60));
      logger.info('【Phase 2 完了】 Yahoo ニュース スクレイピング成功');
      logger.info('='.repeat(60));
      logger.info(`取得ニュース数: ${newsYahooResult.articleCount}件`);
      logger.info(`保存先: s3://${appConfig.awsS3Bucket}/${newsYahooResult.siteName}/articles_${newsYahooResult.timestamp}.json`);
      logger.info('='.repeat(60));
    } catch (error) {
      logger.error('='.repeat(60));
      logger.error('【Phase 2 失敗】 Yahoo ニュース スクレイピングに失敗しました');
      logger.error('='.repeat(60));
      if (error instanceof PlaywrightError) {
        logger.error(`Error Code: ${error.code}`);
      }
      // Phase 2 失敗時もプロセスを継続
    } finally {
      await browserManager.closePage(newsYahooPage);
    }

    // 全処理完了
    logger.info('='.repeat(60));
    logger.info('すべての処理が完了しました');
    logger.info('='.repeat(60));

    process.exit(0);
  } catch (error) {
    handleError(error, 'Main');
    logger.error('='.repeat(60));
    logger.error('予期しないエラーが発生しました');
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
