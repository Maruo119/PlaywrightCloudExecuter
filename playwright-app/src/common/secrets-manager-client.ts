import {
  SecretsManagerClient,
  GetSecretValueCommand,
} from '@aws-sdk/client-secrets-manager';
import logger from './logger';

export interface SecretsConfig {
  infraAwsRegion: string;
  infraAwsS3Bucket: string;
  infraAwsAccessKeyId: string;
  infraSecretAccessKey: string;
}

/**
 * AWS Secrets Manager からシークレット情報を取得
 */
export async function getSecretsFromManager(): Promise<SecretsConfig> {
  try {
    // Secrets Manager クライアントを初期化
    // IAM ロールを使用して認証（Fargate タスク実行ロール）
    const client = new SecretsManagerClient({ region: 'ap-northeast-1' });

    // シークレット値を取得するための ID リスト
    const secretIds = [
      'INFRA_AWS_REGION',
      'INFRA_AWS_S3_BUCKET',
      'INFRA_AWS_ACCESS_KEY_ID',
      'INFRA_SECRET_ACCESS_KEY',
    ];

    const secrets: Record<string, string> = {};

    // 各シークレット値を取得
    for (const secretId of secretIds) {
      try {
        const command = new GetSecretValueCommand({
          SecretId: secretId,
        });

        const response = await client.send(command);

        // シークレット値を取得
        if (response.SecretString) {
          secrets[secretId] = response.SecretString;
        } else if (response.SecretBinary) {
          // バイナリシークレットの場合は Base64 デコード
          const binaryBuffer = Buffer.from(response.SecretBinary as any, 'base64');
          secrets[secretId] = binaryBuffer.toString('utf-8');
        }

        logger.info(`Secrets Manager からシークレットを取得しました: ${secretId}`);
      } catch (error) {
        const errorMessage = `Secrets Manager からシークレット「${secretId}」の取得に失敗しました`;
        logger.error(errorMessage, error);
        throw new Error(errorMessage);
      }
    }

    // 取得したシークレット値を設定オブジェクトにマップ
    const config: SecretsConfig = {
      infraAwsRegion: secrets['INFRA_AWS_REGION'],
      infraAwsS3Bucket: secrets['INFRA_AWS_S3_BUCKET'],
      infraAwsAccessKeyId: secrets['INFRA_AWS_ACCESS_KEY_ID'],
      infraSecretAccessKey: secrets['INFRA_SECRET_ACCESS_KEY'],
    };

    // 必須値の検証
    if (
      !config.infraAwsRegion ||
      !config.infraAwsS3Bucket ||
      !config.infraAwsAccessKeyId ||
      !config.infraSecretAccessKey
    ) {
      throw new Error('Secrets Manager から取得したシークレット値に不足があります');
    }

    logger.info('AWS インフラ設定をSecrets Manager から取得しました');
    return config;
  } catch (error) {
    const errorMessage = 'Secrets Manager への接続またはシークレット取得に失敗しました';
    logger.error(errorMessage, error);
    throw new Error(errorMessage);
  }
}
