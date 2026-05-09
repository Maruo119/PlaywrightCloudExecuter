param(
    [string]$AWSProfile = "default",
    [string]$AWSRegion = "ap-northeast-1"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "フェーズ4: EventBridge + Lambda 自動化設定" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Get AWS Account ID
Write-Host "ステップ1: AWS アカウント情報を取得..." -ForegroundColor Yellow
$awsAccountId = aws sts get-caller-identity --query Account --output text --profile $AWSProfile

if (-not $awsAccountId) {
    Write-Host "[ERROR] Failed to get AWS Account ID" -ForegroundColor Red
    exit 1
}

Write-Host "  AWS Account ID: $awsAccountId" -ForegroundColor Green
Write-Host "  Region: $AWSRegion" -ForegroundColor Green
Write-Host ""

# Step 2: Get VPC info
Write-Host "ステップ2: VPC・ネットワーク情報を取得..." -ForegroundColor Yellow
$vpcId = aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query "Vpcs[0].VpcId" --output text --region $AWSRegion --profile $AWSProfile

if (-not $vpcId) {
    Write-Host "[ERROR] Default VPC not found" -ForegroundColor Red
    exit 1
}

$subnetId = aws ec2 describe-subnets --filters Name=vpc-id,Values=$vpcId --query "Subnets[0].SubnetId" --output text --region $AWSRegion --profile $AWSProfile
$sgId = aws ec2 describe-security-groups --filters Name=vpc-id,Values=$vpcId --query "SecurityGroups[0].GroupId" --output text --region $AWSRegion --profile $AWSProfile

Write-Host "  VPC ID: $vpcId" -ForegroundColor Green
Write-Host "  Subnet ID: $subnetId" -ForegroundColor Green
Write-Host "  Security Group ID: $sgId" -ForegroundColor Green
Write-Host ""

if (-not $subnetId -or -not $sgId) {
    Write-Host "[ERROR] Failed to get subnet or security group" -ForegroundColor Red
    exit 1
}

# Step 3: Update Lambda environment variables
Write-Host "ステップ3: Lambda 環境変数を設定..." -ForegroundColor Yellow
$envVars = "AWS_REGION=$AWSRegion,SUBNET_ID=$subnetId,SECURITY_GROUP_ID=$sgId,ECS_CLUSTER=playwright-cloud-executer-cluster,TASK_DEFINITION=playwright-cloud-executer:1"
aws lambda update-function-configuration --function-name playwright-scheduler --region $AWSRegion --profile $AWSProfile --environment "Variables={$envVars}" | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "  Lambda 環境変数を設定しました" -ForegroundColor Green
}
else {
    Write-Host "[ERROR] Failed to update Lambda environment variables" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Step 4: Create EventBridge rule
Write-Host "ステップ4: EventBridge ルールを作成..." -ForegroundColor Yellow
aws events put-rule --name playwright-hourly-schedule --schedule-expression 'cron(0 * * * ? *)' --state ENABLED --region $AWSRegion --profile $AWSProfile | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "  EventBridge ルール『playwright-hourly-schedule』を作成しました" -ForegroundColor Green
}
else {
    Write-Host "[WARNING] EventBridge ルール作成に失敗した可能性があります" -ForegroundColor Yellow
}
Write-Host ""

# Step 5: Get Lambda ARN
Write-Host "ステップ5: Lambda ARN を取得..." -ForegroundColor Yellow
$lambdaArn = aws lambda get-function --function-name playwright-scheduler --region $AWSRegion --profile $AWSProfile --query "Configuration.FunctionArn" --output text

Write-Host "  Lambda ARN: $lambdaArn" -ForegroundColor Green
Write-Host ""

# Step 6: Add Lambda permission
Write-Host "ステップ6: Lambda に EventBridge の呼び出し権限を追加..." -ForegroundColor Yellow
$sourceArn = "arn:aws:events:$AWSRegion`:$awsAccountId`:rule/playwright-hourly-schedule"
aws lambda add-permission --function-name playwright-scheduler --statement-id AllowEventBridgeInvoke --action lambda:InvokeFunction --principal events.amazonaws.com --source-arn $sourceArn --region $AWSRegion --profile $AWSProfile 2>&1 | Out-Null
Write-Host "  Lambda 権限を追加しました" -ForegroundColor Green
Write-Host ""

# Step 7: Add EventBridge target
Write-Host "ステップ7: EventBridge ターゲットを設定..." -ForegroundColor Yellow
aws events put-targets --rule playwright-hourly-schedule --targets "Id=1,Arn=$lambdaArn,Input={""site_name"":""yahoo""}" --region $AWSRegion --profile $AWSProfile | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "  EventBridge ターゲットを設定しました" -ForegroundColor Green
}
else {
    Write-Host "[WARNING] EventBridge ターゲット設定に失敗した可能性があります" -ForegroundColor Yellow
}
Write-Host ""

# Summary
Write-Host "========================================" -ForegroundColor Green
Write-Host "✓ セットアップ完了！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "自動実行設定内容:" -ForegroundColor Cyan
Write-Host "  EventBridge Rule: playwright-hourly-schedule" -ForegroundColor White
Write-Host "  Schedule: 毎時0分 UTC" -ForegroundColor White
Write-Host "  Lambda: playwright-scheduler" -ForegroundColor White
Write-Host "  Fargate Task: playwright-cloud-executer" -ForegroundColor White
Write-Host ""
Write-Host "次のステップ:" -ForegroundColor Cyan
Write-Host "  1. AWS Console で EventBridge ルールのタイムゾーンを Asia/Tokyo に設定" -ForegroundColor Yellow
Write-Host "  2. Lambda を手動実行してテスト:" -ForegroundColor Yellow
Write-Host ""
Write-Host "     aws lambda invoke --function-name playwright-scheduler --region $AWSRegion --profile $AWSProfile response.json" -ForegroundColor Gray