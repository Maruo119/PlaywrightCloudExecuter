import dotenv from 'dotenv';
import path from 'path';
import logger from './logger';
import { getSecretsFromManager } from './secrets-manager-client';
import {
  DEFAULT_NODE_ENV,
  DEFAULT_LOG_LEVEL,
  DEFAULT_SITE_NAME,
  DEFAULT_BROWSER_HEADLESS,
  DEFAULT_PAGE_TIMEOUT,
} from '../config/nonsecret_const';

// 環境変数をロード（ローカル開発環境用）
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
 * AWS Secrets Manager からシークレット情報を取得します
 */
export async function loadAppConfig(): Promise<AppConfig> {
  try {
    // AWS Secrets Manager からシークレット情報を取得
    const secrets = await getSecretsFromManager();

    const config: AppConfig = {
      nodeEnv: process.env.NODE_ENV || DEFAULT_NODE_ENV,
      logLevel: process.env.LOG_LEVEL || DEFAULT_LOG_LEVEL,
      siteName: process.env.SITE_NAME || DEFAULT_SITE_NAME,
      awsRegion: secrets.infraAwsRegion,
      awsS3Bucket: secrets.infraAwsS3Bucket,
      awsAccessKeyId: secrets.infraAwsAccessKeyId,
      awsSecretAccessKey: secrets.infraSecretAccessKey,
      browserHeadless: process.env.BROWSER_HEADLESS !== 'false' ? DEFAULT_BROWSER_HEADLESS : false,
      pageTimeout: parseInt(process.env.PAGE_TIMEOUT || String(DEFAULT_PAGE_TIMEOUT), 10),
    };

    logger.info('アプリケーション設定をロードしました（AWS Secrets Manager から取得）', {
      nodeEnv: config.nodeEnv,
      logLevel: config.logLevel,
      siteName: config.siteName,
      awsRegion: config.awsRegion,
      awsS3Bucket: config.awsS3Bucket,
    });

    return config;
  } catch (error) {
    const errorMessage = 'アプリケーション設定のロードに失敗しました';
    logger.error(errorMessage, error);
    throw new Error(errorMessage);
  }
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
  loadAppConfig,  // 注: 非同期関数に変更されました。呼び出し時は await を使用してください
  loadSiteConfig,
};
