import { Page } from 'playwright';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import logger from '../../common/logger';
import { executeWithRetry, PlaywrightError, ErrorCode } from '../../common/error-handler';

interface Article {
  title: string;
  url: string;
}

interface ScrapedNewsData {
  siteName: string;
  baseUrl: string;
  articleCount: number;
  articles: Article[];
  scrapedAt: string;
  timestamp: number;
}

class NewsYahooScraper {
  private s3Client: S3Client;
  private readonly siteName = 'news-yahoo';
  private readonly baseUrl = 'https://news.yahoo.co.jp/';

  constructor(awsRegion: string = 'ap-northeast-1') {
    this.s3Client = new S3Client({ region: awsRegion });
  }

  /**
   * Yahoo Newsのトピックスセクションからニュース一覧を抽出
   */
  async scrapeArticles(page: Page): Promise<Article[]> {
    try {
      logger.info('[news-yahoo] ニュース一覧を取得しています...');

      // トピックスセクションを特定
      const topicsSection = page.locator('section#uamods-topics');
      const sectionCount = await topicsSection.count();

      if (sectionCount === 0) {
        throw new PlaywrightError(
          'トピックスセクション（section#uamods-topics）が見つかりません',
          ErrorCode.PAGE_EXTRACTION_ERROR
        );
      }

      // ニュースアイテム（li要素）を取得
      const newsItems = topicsSection.locator('li');
      const itemCount = await newsItems.count();

      if (itemCount === 0) {
        logger.warn('[news-yahoo] ニュースアイテムが見つかりません');
        return [];
      }

      logger.info(`[news-yahoo] ${itemCount}件のニュースアイテムを検出`);

      const articles: Article[] = [];

      // 各ニュースアイテムを走査
      for (let i = 0; i < itemCount; i++) {
        try {
          const item = newsItems.nth(i);
          const link = item.locator('a').first();

          // href 属性を取得
          const url = await link.getAttribute('href');

          // textContent を取得（タイトル）
          const titleContent = await link.textContent();

          if (url && titleContent) {
            // textContent にはスペースや改行が含まれるため、トリム
            const title = titleContent.trim();

            articles.push({
              title,
              url,
            });

            logger.debug(`[news-yahoo] 抽出: ${title.substring(0, 50)}... → ${url}`);
          }
        } catch (itemError) {
          logger.warn(`[news-yahoo] アイテム ${i} の抽出に失敗しました: ${itemError}`);
          // 1つのアイテム失敗では全体を失敗させない
          continue;
        }
      }

      logger.info(`[news-yahoo] ${articles.length}件のニュースを抽出しました`);
      return articles;
    } catch (error) {
      if (error instanceof PlaywrightError) {
        throw error;
      }
      throw new PlaywrightError(
        `ニュース一覧取得エラー: ${error instanceof Error ? error.message : String(error)}`,
        ErrorCode.PAGE_EXTRACTION_ERROR,
        error instanceof Error ? error : undefined
      );
    }
  }

  /**
   * スクレイプ結果を S3 に保存
   */
  async saveToS3(
    data: ScrapedNewsData,
    s3Bucket: string
  ): Promise<void> {
    try {
      // S3キーの構成: news-yahoo/articles_<timestamp>.json
      const s3Key = `${this.siteName}/articles_${data.timestamp}.json`;

      // JSON コンテンツ
      const content = JSON.stringify(data, null, 2);

      logger.info(`[news-yahoo] S3に保存しています: s3://${s3Bucket}/${s3Key}`);

      const command = new PutObjectCommand({
        Bucket: s3Bucket,
        Key: s3Key,
        Body: content,
        ContentType: 'application/json; charset=utf-8',
        Metadata: {
          'Site-Name': this.siteName,
          'Article-Count': data.articleCount.toString(),
          'Scraped-At': data.scrapedAt,
        },
      });

      await this.s3Client.send(command);

      logger.info(`[news-yahoo] S3への保存が完了しました: ${s3Key}`);
    } catch (error) {
      const errorMessage = `S3保存エラー: ${error instanceof Error ? error.message : String(error)}`;
      logger.error(`[news-yahoo] ${errorMessage}`);
      throw new PlaywrightError(
        errorMessage,
        ErrorCode.S3_UPLOAD_ERROR,
        error instanceof Error ? error : undefined
      );
    }
  }

  /**
   * スクレイプ処理のメイン
   */
  async scrape(
    page: Page,
    s3Bucket: string
  ): Promise<ScrapedNewsData> {
    try {
      // ニュース一覧を取得（リトライ付き）
      const articles = await executeWithRetry(
        () => this.scrapeArticles(page),
        3,
        1000,
        ErrorCode.PAGE_EXTRACTION_ERROR
      );

      // スクレイプデータの作成
      const now = new Date();
      const data: ScrapedNewsData = {
        siteName: this.siteName,
        baseUrl: this.baseUrl,
        articleCount: articles.length,
        articles,
        scrapedAt: now.toISOString(),
        timestamp: now.getTime(),
      };

      // S3に保存
      await this.saveToS3(data, s3Bucket);

      logger.info(`[news-yahoo] スクレイプ処理が完了しました`);
      return data;
    } catch (error) {
      if (error instanceof PlaywrightError) {
        throw error;
      }
      throw new PlaywrightError(
        `スクレイプエラー: ${error instanceof Error ? error.message : String(error)}`,
        ErrorCode.UNKNOWN_ERROR,
        error instanceof Error ? error : undefined
      );
    }
  }
}

export default NewsYahooScraper;
