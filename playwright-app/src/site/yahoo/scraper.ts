import { Page } from 'playwright';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import logger from '../../common/logger';
import { SiteConfig } from '../../common/config-loader';
import { executeWithRetry, PlaywrightError, ErrorCode } from '../../common/error-handler';

interface ScrapedData {
  siteName: string;
  baseUrl: string;
  title: string;
  scrapedAt: string;
  timestamp: number;
}

class YahooScraper {
  private s3Client: S3Client;
  private config: SiteConfig;

  constructor(config: SiteConfig, awsRegion: string = 'ap-northeast-1') {
    this.config = config;
    this.s3Client = new S3Client({ region: awsRegion });
  }

  /**
   * Yahooサイトから title を取得
   */
  async scrapeTitle(page: Page): Promise<string> {
    try {
      logger.info('title タグを取得しています...');

      // title タグを取得
      const title = await page.title();

      if (!title) {
        throw new PlaywrightError(
          'title タグが見つかりません',
          ErrorCode.PAGE_EXTRACTION_ERROR
        );
      }

      logger.info(`title を取得しました: ${title}`);
      return title;
    } catch (error) {
      if (error instanceof PlaywrightError) {
        throw error;
      }
      throw new PlaywrightError(
        `title 取得エラー: ${error instanceof Error ? error.message : String(error)}`,
        ErrorCode.PAGE_EXTRACTION_ERROR,
        error instanceof Error ? error : undefined
      );
    }
  }

  /**
   * スクレイプ結果をS3に保存
   */
  async saveToS3(
    data: ScrapedData,
    s3Bucket: string
  ): Promise<void> {
    try {
      // S3キーの構成: yahoo/title_<timestamp>.txt
      const s3Key = `${this.config.name}/title_${data.timestamp}.txt`;

      // テキスト内容
      const content = this._formatContent(data);

      logger.info(`S3に保存しています: s3://${s3Bucket}/${s3Key}`);

      const command = new PutObjectCommand({
        Bucket: s3Bucket,
        Key: s3Key,
        Body: content,
        ContentType: 'text/plain; charset=utf-8',
        Metadata: {
          'Site-Name': this.config.name,
          'Scraped-At': data.scrapedAt,
        },
      });

      await this.s3Client.send(command);

      logger.info(`S3への保存が完了しました: ${s3Key}`);
    } catch (error) {
      const errorMessage = `S3保存エラー: ${error instanceof Error ? error.message : String(error)}`;
      logger.error(errorMessage);
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
  ): Promise<ScrapedData> {
    try {
      // title を取得（リトライ付き）
      const title = await executeWithRetry(
        () => this.scrapeTitle(page),
        3,
        1000,
        ErrorCode.PAGE_EXTRACTION_ERROR
      );

      // スクレイプデータの作成
      const now = new Date();
      const data: ScrapedData = {
        siteName: this.config.name,
        baseUrl: this.config.baseUrl,
        title,
        scrapedAt: now.toISOString(),
        timestamp: now.getTime(),
      };

      // S3に保存
      await this.saveToS3(data, s3Bucket);

      logger.info('スクレイプ処理が完了しました', data);
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

  /**
   * スクレイプ結果をテキスト形式でフォーマット
   */
  private _formatContent(data: ScrapedData): string {
    const lines = [
      `Site Name: ${data.siteName}`,
      `Base URL: ${data.baseUrl}`,
      `Title: ${data.title}`,
      `Scraped At: ${data.scrapedAt}`,
      `Timestamp: ${data.timestamp}`,
    ];
    return lines.join('\n');
  }
}

export default YahooScraper;
