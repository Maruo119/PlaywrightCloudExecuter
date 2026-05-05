# ============================================================================
# deploy-docker-to-ecr.ps1
# ============================================================================
# フェーズ2: Docker イメージをビルドして ECR へプッシュするスクリプト
#
# 使用方法:
#   .\scripts\deploy-docker-to-ecr.ps1
#
# 前提条件:
#   - Docker Desktop がインストール・起動していること
#   - AWS CLI がインストール済みであること
#   - AWS CLI プロファイル (default) が設定済みであること
# ============================================================================

param(
    [string]$Profile = "default",
    [string]$Region = "ap-northeast-1",
    [string]$ImageName = "playwright-cloud-executer",
    [string]$ImageTag = "latest",
    [switch]$DryRun = $false
)

# ============================================================================
# 設定
# ============================================================================

# AWS アカウント ID を取得
Write-Host "AWS アカウント情報を取得中..." -ForegroundColor Cyan
try {
    $AwsAccountId = aws sts get-caller-identity --query Account --output text --profile $Profile
    if (-not $AwsAccountId) {
        throw "AWS アカウント ID の取得に失敗しました"
    }
    Write-Host "✓ AWS アカウント ID: $AwsAccountId" -ForegroundColor Green
} catch {
    Write-Host "✗ エラー: $_" -ForegroundColor Red
    exit 1
}

# ECR リポジトリ URI を構築
$EcrRegistry = "$AwsAccountId.dkr.ecr.$Region.amazonaws.com"
$EcrRepository = "$EcrRegistry/$ImageName"
$ImageUri = "$EcrRepository`:$ImageTag"
$ImageUriLatest = "$EcrRepository`:latest"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "フェーズ2: Docker イメージのビルド・プッシュ" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "AWS Account ID: $AwsAccountId" -ForegroundColor Yellow
Write-Host "Region: $Region" -ForegroundColor Yellow
Write-Host "ECR Registry: $EcrRegistry" -ForegroundColor Yellow
Write-Host "Image URI: $ImageUri" -ForegroundColor Yellow
Write-Host ""

# ============================================================================
# ステップ1: ECR へのログイン
# ============================================================================

Write-Host "ステップ1: ECR へのログイン..." -ForegroundColor Cyan

$EcrLoginCmd = "aws ecr get-login-password --region $Region --profile $Profile | docker login --username AWS --password-stdin $EcrRegistry"

if ($DryRun) {
    Write-Host "[DRY RUN] $EcrLoginCmd" -ForegroundColor Yellow
} else {
    try {
        Write-Host "実行: aws ecr get-login-password | docker login..." -ForegroundColor Gray
        Invoke-Expression $EcrLoginCmd
        Write-Host "✓ ECR ログイン成功" -ForegroundColor Green
    } catch {
        Write-Host "✗ ECR ログイン失敗: $_" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# ============================================================================
# ステップ2: Docker イメージのビルド
# ============================================================================

Write-Host "ステップ2: Docker イメージをビルド..." -ForegroundColor Cyan

$BuildCmd = "docker build -t $ImageName`:$ImageTag ."

if ($DryRun) {
    Write-Host "[DRY RUN] $BuildCmd" -ForegroundColor Yellow
} else {
    try {
        # playwright-app ディレクトリに移動
        $PlaywrightAppPath = ".\playwright-app"
        if (-not (Test-Path $PlaywrightAppPath)) {
            throw "playwright-app ディレクトリが見つかりません: $PlaywrightAppPath"
        }

        Write-Host "実行: $BuildCmd" -ForegroundColor Gray
        Push-Location $PlaywrightAppPath
        Invoke-Expression $BuildCmd
        Pop-Location

        Write-Host "✓ Docker イメージビルド成功: $ImageName`:$ImageTag" -ForegroundColor Green
    } catch {
        Write-Host "✗ Docker イメージビルド失敗: $_" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# ============================================================================
# ステップ3: イメージへのタグ付け
# ============================================================================

Write-Host "ステップ3: イメージにタグを付与..." -ForegroundColor Cyan

$TagCmd1 = "docker tag $ImageName`:$ImageTag $ImageUri"
$TagCmd2 = "docker tag $ImageName`:$ImageTag $ImageUriLatest"

if ($DryRun) {
    Write-Host "[DRY RUN] $TagCmd1" -ForegroundColor Yellow
    Write-Host "[DRY RUN] $TagCmd2" -ForegroundColor Yellow
} else {
    try {
        Write-Host "実行: docker tag ... $ImageUri" -ForegroundColor Gray
        Invoke-Expression $TagCmd1

        Write-Host "実行: docker tag ... $ImageUriLatest" -ForegroundColor Gray
        Invoke-Expression $TagCmd2

        Write-Host "✓ イメージタグ付け成功" -ForegroundColor Green
    } catch {
        Write-Host "✗ イメージタグ付け失敗: $_" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# ============================================================================
# ステップ4: ECR へのプッシュ
# ============================================================================

Write-Host "ステップ4: イメージを ECR へプッシュ..." -ForegroundColor Cyan

$PushCmd1 = "docker push $ImageUri"
$PushCmd2 = "docker push $ImageUriLatest"

if ($DryRun) {
    Write-Host "[DRY RUN] $PushCmd1" -ForegroundColor Yellow
    Write-Host "[DRY RUN] $PushCmd2" -ForegroundColor Yellow
} else {
    try {
        Write-Host "実行: docker push $ImageUri" -ForegroundColor Gray
        Invoke-Expression $PushCmd1

        Write-Host "実行: docker push $ImageUriLatest" -ForegroundColor Gray
        Invoke-Expression $PushCmd2

        Write-Host "✓ ECR へのプッシュ成功" -ForegroundColor Green
    } catch {
        Write-Host "✗ ECR へのプッシュ失敗: $_" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# ============================================================================
# 完了
# ============================================================================

Write-Host "========================================" -ForegroundColor Green
Write-Host "✓ フェーズ2 完了！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "ECR にアップロード完了:"
Write-Host "  - Image URI: $ImageUri" -ForegroundColor Green
Write-Host "  - Latest Tag: $ImageUriLatest" -ForegroundColor Green
Write-Host ""
Write-Host "次のステップ: フェーズ3 でタスク定義を登録してください" -ForegroundColor Yellow
Write-Host "  .\scripts\register-task-definition.ps1" -ForegroundColor Yellow
Write-Host ""
