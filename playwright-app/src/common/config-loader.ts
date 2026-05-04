import dotenv from 'dotenv';
import path from 'path';
import logger from './logger';

// 環境変数をロード
dotenv.config();

export interface AppConfig {
  nodeEnv: string;
  logLevel: string;
  siteName: string;
  awsRegion: string;
  awsS3Bucket: string;
  awsAccessKeyId?: string;
  awsSecretAccessKey?: string;
  browserHeadless: boolean;
  pageTimeout: number;
}

export interface SiteConfig {
  name: string;
  baseUrl: string;
  selectors: {
    title: string;
    [key: string]: string;
  };
  [key: string]: any;
}

/**
 * アプリケーション設定をロード
 */
export function loadAppConfig(): AppConfig {
  const config: AppConfig = {
    nodeEnv: process.env.NODE_ENV || 'development',
    logLevel: process.env.LOG_LEVEL || 'info',
    siteName: process.env.SITE_NAME || 'yahoo',
    awsRegion: process.env.AWS_REGION || 'ap-northeast-1',
    awsS3Bucket: process.env.AWS_S3_BUCKET || 'PlaywrightOutput',
    awsAccessKeyId: process.env.AWS_ACCESS_KEY_ID,
    awsSecretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
    browserHeadless: process.env.BROWSER_HEADLESS !== 'false',
    pageTimeout: parseInt(process.env.PAGE_TIMEOUT || '30000', 10),
  };

  logger.info('アプリケーション設定をロードしました', {
    nodeEnv: config.nodeEnv,
    logLevel: config.logLevel,
    siteName: config.siteName,
    awsRegion: config.awsRegion,
    awsS3Bucket: config.awsS3Bucket,
  });

  return config;
}

/**
 * サイト設定をロード
 */
export function loadSiteConfig(siteName: string): SiteConfig {
  try {
    // サイト設定ファイルのパス
    const configPath = path.join(__dirname, '..', 'site', siteName, 'config.json');

    // 設定ファイルをロード
    const siteConfig = require(configPath);

    logger.info(`サイト設定をロードしました: ${siteName}`, {
      baseUrl: siteConfig.baseUrl,
      selectors: Object.keys(siteConfig.selectors),
    });

    return siteConfig;
  } catch (error) {
    const errorMessage = `サイト設定のロードに失敗しました: ${siteName}`;
    logger.error(errorMessage, error);
    throw new Error(errorMessage);
  }
}

export default {
  loadAppConfig,
  loadSiteConfig,
};
