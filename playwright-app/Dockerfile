# ステージ1: ビルドステージ
FROM mcr.microsoft.com/playwright:v1.40.0-focal AS builder

WORKDIR /app

# Node.jsとnpmの確認
RUN node --version && npm --version

# 依存パッケージのインストール
COPY package.json package-lock.json* ./
RUN npm install

# TypeScriptのコンパイル
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# ステージ2: ランタイムステージ
FROM mcr.microsoft.com/playwright:v1.40.0-focal

WORKDIR /app

# 日本語フォントのインストール
RUN apt-get update && apt-get install -y \
    fonts-noto-cjk \
    locales \
    && locale-gen ja_JP.UTF-8 \
    && update-locale LANG=ja_JP.UTF-8 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 環境変数設定
ENV LANG=ja_JP.UTF-8
ENV LANGUAGE=ja_JP:ja
ENV LC_ALL=ja_JP.UTF-8
ENV TZ=Asia/Tokyo
ENV NODE_ENV=production

# シークレット情報は AWS Secrets Manager から取得するため、.env ファイルは含めない
# IAM ロール（Fargate タスク実行ロール）を使用して Secrets Manager にアクセスします

# ビルドステージからファイルをコピー
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package.json ./package.json

# アプリケーション実行
ENTRYPOINT ["node", "dist/index.js"]
