# ============================================================================
# register-task-definition.ps1
# ============================================================================
# フェーズ3: ECS タスク定義を登録するスクリプト
#
# 使用方法:
#   .\scripts\register-task-definition.ps1
#
# 前提条件:
#   - AWS CLI がインストール済みであること
#   - AWS CLI プロファイル (default) が設定済みであること
#   - ecs-task-definition.json がプロジェクトルートに存在すること
# ============================================================================

param(
    [string]$Profile = "default",
    [string]$Region = "ap-northeast-1",
    [string]$TaskDefinitionFile = ".\ecs-task-definition.json",
    [switch]$DryRun = $false
)

# ============================================================================
# 設定の確認
# ============================================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "フェーズ3: ECS タスク定義の登録" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Region: $Region" -ForegroundColor Yellow
Write-Host "Task Definition File: $TaskDefinitionFile" -ForegroundColor Yellow
Write-Host ""

# ============================================================================
# ステップ1: タスク定義ファイルの確認
# ============================================================================

Write-Host "ステップ1: タスク定義ファイルを確認..." -ForegroundColor Cyan

if (-not (Test-Path $TaskDefinitionFile)) {
    Write-Host "✗ エラー: タスク定義ファイルが見つかりません: $TaskDefinitionFile" -ForegroundColor Red
    exit 1
}

try {
    $TaskDefinition = Get-Content $TaskDefinitionFile | ConvertFrom-Json
    Write-Host "✓ タスク定義ファイル読み込み成功" -ForegroundColor Green
    Write-Host "  - Family: $($TaskDefinition.family)" -ForegroundColor Gray
    Write-Host "  - CPU: $($TaskDefinition.cpu)" -ForegroundColor Gray
    Write-Host "  - Memory: $($TaskDefinition.memory)" -ForegroundColor Gray
} catch {
    Write-Host "✗ タスク定義ファイルの解析に失敗しました: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""

# ============================================================================
# ステップ2: タスク定義の登録
# ============================================================================

Write-Host "ステップ2: タスク定義を AWS に登録..." -ForegroundColor Cyan

$RegisterCmd = "aws ecs register-task-definition `
  --cli-input-json file://$TaskDefinitionFile `
  --region $Region `
  --profile $Profile"

if ($DryRun) {
    Write-Host "[DRY RUN] タスク定義登録コマンド:" -ForegroundColor Yellow
    Write-Host $RegisterCmd -ForegroundColor Yellow
} else {
    try {
        Write-Host "実行: aws ecs register-task-definition..." -ForegroundColor Gray
        $Result = Invoke-Expression $RegisterCmd | ConvertFrom-Json

        if ($Result.taskDefinition) {
            $TaskDefArn = $Result.taskDefinition.taskDefinitionArn
            $TaskDefRev = $Result.taskDefinition.revision

            Write-Host "✓ タスク定義登録成功" -ForegroundColor Green
            Write-Host "  - ARN: $TaskDefArn" -ForegroundColor Green
            Write-Host "  - Revision: $TaskDefRev" -ForegroundColor Green
        } else {
            throw "タスク定義の登録に失敗しました"
        }
    } catch {
        Write-Host "✗ タスク定義登録失敗: $_" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# ============================================================================
# ステップ3: 登録されたタスク定義を確認
# ============================================================================

Write-Host "ステップ3: 登録されたタスク定義を確認..." -ForegroundColor Cyan

$DescribeCmd = "aws ecs describe-task-definition `
  --task-definition playwright-cloud-executer `
  --region $Region `
  --profile $Profile"

if ($DryRun) {
    Write-Host "[DRY RUN] タスク定義確認コマンド:" -ForegroundColor Yellow
    Write-Host $DescribeCmd -ForegroundColor Yellow
} else {
    try {
        Write-Host "実行: aws ecs describe-task-definition..." -ForegroundColor Gray
        $DescribeResult = Invoke-Expression $DescribeCmd | ConvertFrom-Json

        if ($DescribeResult.taskDefinition) {
            $Family = $DescribeResult.taskDefinition.family
            $Revision = $DescribeResult.taskDefinition.revision
            $Status = $DescribeResult.taskDefinition.status
            $Image = $DescribeResult.taskDefinition.containerDefinitions[0].image

            Write-Host "✓ タスク定義確認成功" -ForegroundColor Green
            Write-Host "  - Family: $Family" -ForegroundColor Green
            Write-Host "  - Revision: $Revision" -ForegroundColor Green
            Write-Host "  - Status: $Status" -ForegroundColor Green
            Write-Host "  - Image: $Image" -ForegroundColor Green
        } else {
            throw "タスク定義の確認に失敗しました"
        }
    } catch {
        Write-Host "✗ タスク定義確認失敗: $_" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# ============================================================================
# 完了
# ============================================================================

Write-Host "========================================" -ForegroundColor Green
Write-Host "✓ フェーズ3 完了！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "タスク定義が登録されました:"
Write-Host "  - Family: playwright-cloud-executer" -ForegroundColor Green
Write-Host ""
Write-Host "次のステップ: フェーズ4 で Fargate タスクを手動実行してください" -ForegroundColor Yellow
Write-Host "  aws ecs run-task --cluster playwright-cloud-executer-cluster ..." -ForegroundColor Yellow
Write-Host ""
