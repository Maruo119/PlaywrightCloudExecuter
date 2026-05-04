import winston from 'winston';

const logLevel = process.env.LOG_LEVEL || 'info';

// ログフォーマット定義
const logFormat = winston.format.combine(
  winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
  winston.format.errors({ stack: true }),
  winston.format.printf(({ level, message, timestamp, stack }) => {
    if (stack) {
      return `${timestamp} [${level.toUpperCase()}] ${message}\n${stack}`;
    }
    return `${timestamp} [${level.toUpperCase()}] ${message}`;
  })
);

// Winstonロガーの作成
const logger = winston.createLogger({
  level: logLevel,
  format: logFormat,
  transports: [
    // コンソール出力
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        logFormat
      ),
    }),
  ],
});

// JSON形式でのログ出力（CloudWatch Logs対応）
const jsonLogger = winston.createLogger({
  level: logLevel,
  format: winston.format.json(),
  transports: [
    new winston.transports.Console({
      format: winston.format.json(),
    }),
  ],
});

export { logger, jsonLogger };
export default logger;
