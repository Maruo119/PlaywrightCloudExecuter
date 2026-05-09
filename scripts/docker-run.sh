#!/bin/bash

# ============================================================
# Docker Run Script
# AWS 認証情報を環境変数で渡し、Playwright コンテナを実行
# ============================================================

set -e

# デフォルト値
IMAGE_NAME="${IMAGE_NAME:-playwright-cloud-executer:latest}"
SITE_NAME="${SITE_NAME:-yahoo}"
AWS_PROFILE="${AWS_PROFILE:-default}"
REGION="${REGION:-ap-northeast-1}"

# 色付き出力用
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ログ出力関数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 使用方法
usage() {
    cat << 'EOF'
使用方法:
  ./scripts/docker-run.sh [OPTIONS]

オプション:
  -s, --site SITE_NAME              サイト名 (デフォルト: yahoo)
  -p, --profile AWS_PROFILE         AWS CLI プロファイル (デフォルト: default)
  -r, --region AWS_REGION           AWS リージョン (デフォルト: ap-northeast-1)
  -i, --image IMAGE_NAME            Docker イメージ名 (デフォルト: playwright-cloud-executer:latest)
  --dry-run                          実行コマンドを表示するのみ
  -h, --help                         このヘルプを表示

例:
  # デフォルト設定で実行
  ./scripts/docker-run.sh

  # 異なるプロファイルで実行
  ./scripts/docker-run.sh --profile my-aws-profile

  # サイト名を指定して実行
  ./scripts/docker-run.sh --site yahoo --profile default
EOF
    exit 0
}

# オプションパース
DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--site)
            SITE_NAME="$2"
            shift 2
            ;;
        -p|--profile)
            AWS_PROFILE="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -i|--image)
            IMAGE_NAME="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
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

log_info "Docker実行スクリプト開始"
log_info "サイト名: $SITE_NAME"
log_info "AWS プロファイル: $AWS_PROFILE"
log_info "リージョン: $REGION"
log_info "イメージ: $IMAGE_NAME"

# AWS CLI プロファイルの存在確認
if ! aws configure list --profile "$AWS_PROFILE" > /dev/null 2>&1; then
    log_error "AWS プロファイル '$AWS_PROFILE' が見つかりません"
    exit 1
fi

# AWS 認証情報を取得
log_info "AWS 認証情報を取得中..."
AWS_ACCESS_KEY=$(aws configure get aws_access_key_id --profile "$AWS_PROFILE")
AWS_SECRET_KEY=$(aws configure get aws_secret_access_key --profile "$AWS_PROFILE")
AWS_SESSION_TOKEN=$(aws configure get aws_session_token --profile "$AWS_PROFILE" 2>/dev/null || echo "")

if [ -z "$AWS_ACCESS_KEY" ] || [ -z "$AWS_SECRET_KEY" ]; then
    log_error "AWS 認証情報を取得できません"
    exit 1
fi

log_info "AWS 認証情報の取得に成功しました"

# Docker 実行コマンドの構築
DOCKER_RUN_CMD=(
    "docker" "run" "--rm"
    "-e" "SITE_NAME=$SITE_NAME"
    "-e" "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY"
    "-e" "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_KEY"
    "-e" "AWS_DEFAULT_REGION=$REGION"
)

# セッショントークンがある場合は追加
if [ -n "$AWS_SESSION_TOKEN" ]; then
    DOCKER_RUN_CMD+=("-e" "AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN")
fi

DOCKER_RUN_CMD+=("$IMAGE_NAME")

# ドライランモードの場合は実行コマンドを表示のみ
if [ "$DRY_RUN" = true ]; then
    log_info "ドライラン: 以下のコマンドを実行予定です"
    echo ""
    echo "docker run --rm \\"
    echo "  -e SITE_NAME=$SITE_NAME \\"
    echo "  -e AWS_ACCESS_KEY_ID=<masked> \\"
    echo "  -e AWS_SECRET_ACCESS_KEY=<masked> \\"
    echo "  -e AWS_DEFAULT_REGION=$REGION"
    if [ -n "$AWS_SESSION_TOKEN" ]; then
        echo "  -e AWS_SESSION_TOKEN=<masked> \\"
    fi
    echo "  $IMAGE_NAME"
    echo ""
    exit 0
fi

# Docker イメージの存在確認
if ! docker image inspect "$IMAGE_NAME" > /dev/null 2>&1; then
    log_warn "Docker イメージ '$IMAGE_NAME' が見つかりません"
    log_info "イメージをビルドしますか? (y/n)"
    read -r response
    if [[ "$response" == "y" || "$response" == "Y" ]]; then
        log_info "ビルドを実行中..."
        bash "$(dirname "$0")/docker-build.sh" || exit 1
    else
        log_error "イメージが見つからないため、実行を中止しました"
        exit 1
    fi
fi

log_info "Docker コンテナを実行中..."
echo ""

# Docker コンテナを実行
"${DOCKER_RUN_CMD[@]}"

log_info "実行完了"
