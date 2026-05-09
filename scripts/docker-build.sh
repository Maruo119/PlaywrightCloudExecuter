#!/bin/bash

# ============================================================
# Docker Build Script
# Playwright アプリケーションの Docker イメージをビルド
# ============================================================

set -e

# デフォルト値
IMAGE_NAME="${IMAGE_NAME:-playwright-cloud-executer:latest}"
DOCKERFILE_PATH="${DOCKERFILE_PATH:-./playwright-app/Dockerfile}"
BUILD_CONTEXT="${BUILD_CONTEXT:-./playwright-app}"

# 色付き出力用
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ログ出力関数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 使用方法
usage() {
    cat << 'EOF'
使用方法:
  ./scripts/docker-build.sh [OPTIONS]

オプション:
  -i, --image IMAGE_NAME            Docker イメージ名 (デフォルト: playwright-cloud-executer:latest)
  -f, --file DOCKERFILE_PATH        Dockerfile のパス (デフォルト: ./playwright-app/Dockerfile)
  -c, --context BUILD_CONTEXT       ビルドコンテキスト (デフォルト: ./playwright-app)
  --no-cache                        キャッシュを使用せずビルド
  -h, --help                        このヘルプを表示

例:
  # デフォルト設定でビルド
  ./scripts/docker-build.sh

  # キャッシュを使用せずビルド
  ./scripts/docker-build.sh --no-cache
EOF
    exit 0
}

# オプションパース
NO_CACHE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--image)
            IMAGE_NAME="$2"
            shift 2
            ;;
        -f|--file)
            DOCKERFILE_PATH="$2"
            shift 2
            ;;
        -c|--context)
            BUILD_CONTEXT="$2"
            shift 2
            ;;
        --no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "未知のオプション: $1"
            usage
            ;;
    esac
done

log_info "Docker Build スクリプト開始"
log_info "イメージ名: $IMAGE_NAME"
log_info "Dockerfile: $DOCKERFILE_PATH"
log_info "ビルドコンテキスト: $BUILD_CONTEXT"

# Dockerfile の存在確認
if [ ! -f "$DOCKERFILE_PATH" ]; then
    log_error "Dockerfile が見つかりません: $DOCKERFILE_PATH"
    exit 1
fi

# ビルドコンテキストの存在確認
if [ ! -d "$BUILD_CONTEXT" ]; then
    log_error "ビルドコンテキストが見つかりません: $BUILD_CONTEXT"
    exit 1
fi

log_info "Docker イメージをビルド中..."
echo ""

# Docker イメージをビルド
docker build \
    $NO_CACHE \
    -f "$DOCKERFILE_PATH" \
    -t "$IMAGE_NAME" \
    "$BUILD_CONTEXT"

log_info "ビルド完了: $IMAGE_NAME"
docker image inspect "$IMAGE_NAME" | grep -E "Size|RepoTags" || true
