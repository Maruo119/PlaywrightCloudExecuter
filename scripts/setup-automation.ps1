param(
    [string]$AWSProfile = "default",
    [string]$AWSRegion = "ap-northeast-1",
    [switch]$DryRun = $false
)

# ============================================
# Playwright Cloud Executer - Automation Setup
# ============================================
# This script sets up EventBridge + Lambda for hourly automation

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "フェーズ4: EventBridge + Lambda 自動化設定" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Helper function: AWS CLI command execution
function Invoke-AwsCommand {
    param(
        [string]$Command,
        [string]$Description
    )

    Write-Host "[INFO] $Description" -ForegroundColor Yellow

    if ($DryRun) {
        Write-Host "  [DRY-RUN] $Command" -ForegroundColor Gray
        return $null
    }

    $result = Invoke-Expression $Command 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [ERROR] $Description failed" -ForegroundColor Red
        Write-Host "  $result" -ForegroundColor Red
        return $null
    }

    Write-Host "  [✓] $Description success" -ForegroundColor Green
    return $result
}

# ============================================
# Step 1: Retrieve AWS Account Information
# ============================================
Write-Host ""
Write-Host "ステップ1: AWS アカウント情報の取得..." -ForegroundColor Cyan

$awsAccountId = Invoke-AwsCommand `
    -Command "aws sts get-caller-identity --query Account --output text --profile $AWSProfile" `
    -Description "AWS Account ID を取得"

if (-not $awsAccountId) {
    Write-Host "[ERROR] Failed to retrieve AWS Account ID" -ForegroundColor Red
    exit 1
}

Write-Host "  AWS Account ID: $awsAccountId"
Write-Host "  Region: $AWSRegion"
Write-Host ""

# ============================================
# Step 2: Verify Lambda Function Exists
# ============================================
Write-Host "ステップ2: Lambda 関数の確認..." -ForegroundColor Cyan

$lambdaFunctionName = "playwright-scheduler"

$lambdaInfo = Invoke-AwsCommand `
    -Command "aws lambda get-function --function-name $lambdaFunctionName --region $AWSRegion --profile $AWSProfile --output json" `
    -Description "Lambda 関数『$lambdaFunctionName』を確認"

if (-not $lambdaInfo) {
    Write-Host "[ERROR] Lambda function '$lambdaFunctionName' not found" -ForegroundColor Red
    Write-Host "  Lambda 関数が存在しません。AWS Console から作成してください。" -ForegroundColor Red
    exit 1
}

$lambdaArn = $lambdaInfo | ConvertFrom-Json | Select-Object -ExpandProperty Configuration | Select-Object -ExpandProperty FunctionArn
Write-Host "  Lambda ARN: $lambdaArn"
Write-Host ""

# ============================================
# Step 3: Get VPC and Network Information
# ============================================
Write-Host "ステップ3: VPC・ネットワーク情報の取得..." -ForegroundColor Cyan

$defaultVpc = Invoke-AwsCommand `
    -Command "aws ec2 describe-vpcs --filters 'Name=isDefault,Values=true' --query 'Vpcs[0].VpcId' --output text --region $AWSRegion --profile $AWSProfile" `
    -Description "デフォルト VPC を取得"

if (-not $defaultVpc) {
    Write-Host "[ERROR] Default VPC not found" -ForegroundColor Red
    exit 1
}

$subnetId = Invoke-AwsCommand `
    -Command "aws ec2 describe-subnets --filters 'Name=vpc-id,Values=$defaultVpc' --query 'Subnets[0].SubnetId' --output text --region $AWSRegion --profile $AWSProfile" `
    -Description "Subnet を取得"

$securityGroupId = Invoke-AwsCommand `
    -Command "aws ec2 describe-security-groups --filters 'Name=vpc-id,Values=$defaultVpc' --query 'SecurityGroups[0].GroupId' --output text --region $AWSRegion --profile $AWSProfile" `
    -Description "Security Group を取得"

Write-Host "  VPC ID: $defaultVpc"
Write-Host "  Subnet ID: $subnetId"
Write-Host "  Security Group ID: $securityGroupId"
Write-Host ""

if (-not $subnetId -or -not $securityGroupId) {
    Write-Host "[ERROR] Failed to retrieve subnet or security group" -ForegroundColor Red
    exit 1
}

# ============================================
# Step 4: Get Lambda Execution Role
# ============================================
Write-Host "ステップ4: Lambda 実行ロールの確認..." -ForegroundColor Cyan

$lambdaRoleInfo = $lambdaInfo | ConvertFrom-Json | Select-Object -ExpandProperty Configuration | Select-Object -ExpandProperty Role
$lambdaRoleArn = $lambdaRoleInfo
$lambdaRoleName = $lambdaRoleArn.Split("/")[-1]

Write-Host "  Lambda Role Name: $lambdaRoleName"
Write-Host "  Lambda Role ARN: $lambdaRoleArn"
Write-Host ""

# ============================================
# Step 5: Add ECS Permissions to Lambda Role
# ============================================
Write-Host "ステップ5: Lambda 実行ロールに ECS 権限を追加..." -ForegroundColor Cyan

# Check if inline policy already exists
$inlinePolicies = Invoke-AwsCommand `
    -Command "aws iam list-role-policies --role-name $lambdaRoleName --profile $AWSProfile --output json" `
    -Description "Lambda ロールのインラインポリシーを確認"

if ($inlinePolicies) {
    $policyList = $inlinePolicies | ConvertFrom-Json | Select-Object -ExpandProperty PolicyNames
    if ($policyList -contains "playwright-ecs-execution") {
        Write-Host "  [✓] ECS policy already attached" -ForegroundColor Green
    } else {
        Write-Host "  [INFO] Adding ECS execution policy..."

        $ecsPolicy = @{
            Version = "2012-10-17"
            Statement = @(
                @{
                    Effect = "Allow"
                    Action = @("ecs:RunTask")
                    Resource = "arn:aws:ecs:${AWSRegion}:${awsAccountId}:task-definition/playwright-cloud-executer:*"
                },
                @{
                    Effect = "Allow"
                    Action = @("iam:PassRole")
                    Resource = "arn:aws:iam::${awsAccountId}:role/Playwright-Role"
                }
            )
        } | ConvertTo-Json -Depth 10

        $policyFile = [System.IO.Path]::GetTempFileName()
        Set-Content -Path $policyFile -Value $ecsPolicy

        Invoke-AwsCommand `
            -Command "aws iam put-role-policy --role-name $lambdaRoleName --policy-name playwright-ecs-execution --policy-document file://$policyFile --profile $AWSProfile" `
            -Description "ECS 実行権限をアタッチ"

        Remove-Item $policyFile
    }
}

Write-Host ""

# ============================================
# Step 6: Update Lambda Environment Variables
# ============================================
Write-Host "ステップ6: Lambda 環境変数を更新..." -ForegroundColor Cyan

$envVarsJson = @{
    Variables = @{
        "AWS_REGION" = $AWSRegion
        "SUBNET_ID" = $subnetId
        "SECURITY_GROUP_ID" = $securityGroupId
        "ECS_CLUSTER" = "playwright-cloud-executer-cluster"
        "TASK_DEFINITION" = "playwright-cloud-executer:1"
    }
} | ConvertTo-Json

Invoke-AwsCommand `
    -Command "aws lambda update-function-configuration --function-name $lambdaFunctionName --region $AWSRegion --environment '{""Variables"":{""AWS_REGION"":""$AWSRegion"",""SUBNET_ID"":""$subnetId"",""SECURITY_GROUP_ID"":""$securityGroupId"",""ECS_CLUSTER"":""playwright-cloud-executer-cluster"",""TASK_DEFINITION"":""playwright-cloud-executer:1""}}' --profile $AWSProfile" `
    -Description "Lambda 環境変数を更新"

Write-Host ""

# ============================================
# Step 7: Create/Update EventBridge Rule
# ============================================
Write-Host "ステップ7: EventBridge ルール『playwright-hourly-schedule』を作成..." -ForegroundColor Cyan

$ruleName = "playwright-hourly-schedule"
$cronExpression = "0 * * * ? *"  # Every hour at minute 0 (UTC)

# Create rule
Invoke-AwsCommand `
    -Command "aws events put-rule --name $ruleName --schedule-expression 'cron($cronExpression)' --state ENABLED --region $AWSRegion --profile $AWSProfile --tags Key=PlaywrightCloudExecuter,Value=true" `
    -Description "EventBridge ルール『$ruleName』を作成"

Write-Host "  Cron Expression: $cronExpression (毎時0分 UTC)"
Write-Host "  Timezone: Asia/Tokyo (コンソールから設定してください)"
Write-Host ""

# ============================================
# Step 8: Create Lambda Permission for EventBridge
# ============================================
Write-Host "ステップ8: Lambda に EventBridge の呼び出し権限を許可..." -ForegroundColor Cyan

Invoke-AwsCommand `
    -Command "aws lambda add-permission --function-name $lambdaFunctionName --statement-id AllowEventBridgeInvoke --action lambda:InvokeFunction --principal events.amazonaws.com --source-arn arn:aws:events:${AWSRegion}:${awsAccountId}:rule/${ruleName} --region $AWSRegion --profile $AWSProfile 2>&1 | Select-String -Pattern 'error|already' -Quiet" `
    -Description "EventBridge が Lambda を呼び出す権限を追加"

Write-Host ""

# ============================================
# Step 9: Add EventBridge Target to Lambda
# ============================================
Write-Host "ステップ9: EventBridge ターゲットに Lambda を指定..." -ForegroundColor Cyan

$targetConfig = @{
    Arn = $lambdaArn
    RoleArn = "arn:aws:iam::${awsAccountId}:role/service-role/EventBridgeServiceRole"
    Input = '{"site_name":"yahoo"}'
} | ConvertTo-Json

Invoke-AwsCommand `
    -Command "aws events put-targets --rule $ruleName --targets 'Id=1,Arn=$lambdaArn,Input={""site_name"":""yahoo""}' --region $AWSRegion --profile $AWSProfile 2>&1 | Select-String -Pattern 'error|FailedEntry' -Quiet" `
    -Description "EventBridge ターゲットを設定"

Write-Host ""

# ============================================
# Step 10: Verify Setup
# ============================================
Write-Host "ステップ10: セットアップ結果の確認..." -ForegroundColor Cyan

$ruleInfo = Invoke-AwsCommand `
    -Command "aws events describe-rule --name $ruleName --region $AWSRegion --profile $AWSProfile --output json" `
    -Description "EventBridge ルールを確認"

if ($ruleInfo) {
    $rule = $ruleInfo | ConvertFrom-Json
    Write-Host "  Rule Name: $($rule.Name)"
    Write-Host "  Rule State: $($rule.State)"
    Write-Host "  Schedule: $($rule.ScheduleExpression)"
}

Write-Host ""

# ============================================
# Summary
# ============================================
Write-Host "========================================" -ForegroundColor Green
Write-Host "✓ フェーズ4 完了！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "セットアップ完了。以下が自動実行設定されました：" -ForegroundColor Green
Write-Host ""
Write-Host "  EventBridge Rule: $ruleName" -ForegroundColor Cyan
Write-Host "  Schedule: 毎時0分 UTC（Asia/Tokyo タイムゾーンで 09:00, 10:00, ... など）" -ForegroundColor Cyan
Write-Host "  Lambda Function: $lambdaFunctionName" -ForegroundColor Cyan
Write-Host "  ECS Cluster: playwright-cloud-executer-cluster" -ForegroundColor Cyan
Write-Host "  Fargate Task: playwright-cloud-executer" -ForegroundColor Cyan
Write-Host ""
Write-Host "次のステップ:" -ForegroundColor Cyan
Write-Host "  1. AWS Console で EventBridge ルール『$ruleName』のタイムゾーンを Asia/Tokyo に設定" -ForegroundColor Yellow
Write-Host "  2. CloudWatch Logs で実行ログを監視" -ForegroundColor Yellow
Write-Host "  3. 手動テスト (下記コマンドで Lambda を実行):" -ForegroundColor Yellow
Write-Host ""
Write-Host "     aws lambda invoke --function-name $lambdaFunctionName --region $AWSRegion --profile $AWSProfile response.json" -ForegroundColor Gray
Write-Host ""
