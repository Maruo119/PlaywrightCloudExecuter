import logger from './logger';

// エラーコード定義
export enum ErrorCode {
  BROWSER_LAUNCH_ERROR = 'BROWSER_LAUNCH_ERROR',
  PAGE_NAVIGATION_ERROR = 'PAGE_NAVIGATION_ERROR',
  PAGE_EXTRACTION_ERROR = 'PAGE_EXTRACTION_ERROR',
  S3_UPLOAD_ERROR = 'S3_UPLOAD_ERROR',
  CONFIG_LOAD_ERROR = 'CONFIG_LOAD_ERROR',
  INVALID_SITE_ERROR = 'INVALID_SITE_ERROR',
  RETRY_EXCEEDED_ERROR = 'RETRY_EXCEEDED_ERROR',
  UNKNOWN_ERROR = 'UNKNOWN_ERROR',
}

// カスタムエラークラス
export class PlaywrightError extends Error {
  public code: ErrorCode;
  public originalError: Error | null;

  constructor(message: string, code: ErrorCode, originalError?: Error) {
    super(message);
    this.code = code;
    this.originalError = originalError || null;
    this.name = 'PlaywrightError';
  }

  toJSON() {
    return {
      name: this.name,
      message: this.message,
      code: this.code,
      timestamp: new Date().toISOString(),
      originalError: this.originalError?.message,
    };
  }
}

// リトライ機能付きの関数実行
export async function executeWithRetry<T>(
  fn: () => Promise<T>,
  maxRetries: number = 3,
  delayMs: number = 1000,
  errorCode: ErrorCode = ErrorCode.UNKNOWN_ERROR
): Promise<T> {
  let lastError: Error | null = null;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      logger.info(`試行 ${attempt}/${maxRetries}...`);
      return await fn();
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
      logger.warn(`試行 ${attempt} が失敗しました: ${lastError.message}`);

      if (attempt < maxRetries) {
        logger.info(`${delayMs}ms 待機してリトライします...`);
        await new Promise((resolve) => setTimeout(resolve, delayMs));
      }
    }
  }

  // すべてのリトライが失敗した場合
  const errorMessage = `${maxRetries}回のリトライ後も処理に失敗しました: ${lastError?.message}`;
  logger.error(errorMessage);
  throw new PlaywrightError(errorMessage, ErrorCode.RETRY_EXCEEDED_ERROR, lastError || undefined);
}

// エラーハンドラー
export function handleError(error: unknown, context: string): void {
  if (error instanceof PlaywrightError) {
    logger.error(`[${context}] PlaywrightError: ${error.message}`, {
      code: error.code,
      originalError: error.originalError?.message,
    });
  } else if (error instanceof Error) {
    logger.error(`[${context}] Error: ${error.message}`, error);
  } else {
    logger.error(`[${context}] Unknown error:`, error);
  }
}

export default {
  ErrorCode,
  PlaywrightError,
  executeWithRetry,
  handleError,
};
