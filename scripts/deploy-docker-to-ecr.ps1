# ============================================================================
# deploy-docker-to-ecr.ps1
# ============================================================================
# Phase 2: Build Docker image and push to ECR
#
# Usage:
#   .\scripts\deploy-docker-to-ecr.ps1
#
# Prerequisites:
#   - Docker Desktop installed and running
#   - AWS CLI installed
#   - AWS CLI profile (default) configured
# ============================================================================

param(
    [string]$Profile = "default",
    [string]$Region = "ap-northeast-1",
    [string]$ImageName = "playwright-cloud-executer",
    [string]$ImageTag = "latest",
    [switch]$DryRun = $false
)

# ============================================================================
# Configuration
# ============================================================================

# Get AWS Account ID
Write-Host "Fetching AWS account information..." -ForegroundColor Cyan
try {
    $AwsAccountId = aws sts get-caller-identity --query Account --output text --profile $Profile
    if (-not $AwsAccountId) {
        throw "Failed to retrieve AWS Account ID"
    }
    Write-Host "✓ AWS Account ID: $AwsAccountId" -ForegroundColor Green
} catch {
    Write-Host "✗ Error: $_" -ForegroundColor Red
    exit 1
}

# Build ECR repository URI
$EcrRegistry = "$AwsAccountId.dkr.ecr.$Region.amazonaws.com"
$EcrRepository = "$EcrRegistry/$ImageName"
$ImageUri = "$EcrRepository`:$ImageTag"
$ImageUriLatest = "$EcrRepository`:latest"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Phase 2: Docker Image Build & Push" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "AWS Account ID: $AwsAccountId" -ForegroundColor Yellow
Write-Host "Region: $Region" -ForegroundColor Yellow
Write-Host "ECR Registry: $EcrRegistry" -ForegroundColor Yellow
Write-Host "Image URI: $ImageUri" -ForegroundColor Yellow
Write-Host ""

# ============================================================================
# Step 1: ECR Login
# ============================================================================

Write-Host "Step 1: ECR Login..." -ForegroundColor Cyan

$EcrLoginCmd = "aws ecr get-login-password --region $Region --profile $Profile | docker login --username AWS --password-stdin $EcrRegistry"

if ($DryRun) {
    Write-Host "[DRY RUN] $EcrLoginCmd" -ForegroundColor Yellow
} else {
    try {
        Write-Host "Executing: aws ecr get-login-password | docker login..." -ForegroundColor Gray
        Invoke-Expression $EcrLoginCmd
        Write-Host "✓ ECR login successful" -ForegroundColor Green
    } catch {
        Write-Host "✗ ECR login failed: $_" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# ============================================================================
# Step 2: Build Docker Image
# ============================================================================

Write-Host "Step 2: Building Docker image..." -ForegroundColor Cyan

$BuildCmd = "docker build -t $ImageName`:$ImageTag ."

if ($DryRun) {
    Write-Host "[DRY RUN] $BuildCmd" -ForegroundColor Yellow
} else {
    try {
        # Navigate to playwright-app directory
        $PlaywrightAppPath = ".\playwright-app"
        if (-not (Test-Path $PlaywrightAppPath)) {
            throw "playwright-app directory not found: $PlaywrightAppPath"
        }

        Write-Host "Executing: $BuildCmd" -ForegroundColor Gray
        Push-Location $PlaywrightAppPath
        Invoke-Expression $BuildCmd
        Pop-Location

        Write-Host "✓ Docker image build successful: $ImageName`:$ImageTag" -ForegroundColor Green
    } catch {
        Write-Host "✗ Docker image build failed: $_" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# ============================================================================
# Step 3: Tag Docker Image
# ============================================================================

Write-Host "Step 3: Tagging image..." -ForegroundColor Cyan

$TagCmd1 = "docker tag $ImageName`:$ImageTag $ImageUri"
$TagCmd2 = "docker tag $ImageName`:$ImageTag $ImageUriLatest"

if ($DryRun) {
    Write-Host "[DRY RUN] $TagCmd1" -ForegroundColor Yellow
    Write-Host "[DRY RUN] $TagCmd2" -ForegroundColor Yellow
} else {
    try {
        Write-Host "Executing: docker tag ... $ImageUri" -ForegroundColor Gray
        Invoke-Expression $TagCmd1

        Write-Host "Executing: docker tag ... $ImageUriLatest" -ForegroundColor Gray
        Invoke-Expression $TagCmd2

        Write-Host "✓ Image tagging successful" -ForegroundColor Green
    } catch {
        Write-Host "✗ Image tagging failed: $_" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# ============================================================================
# Step 4: Push to ECR
# ============================================================================

Write-Host "Step 4: Pushing image to ECR..." -ForegroundColor Cyan

$PushCmd1 = "docker push $ImageUri"
$PushCmd2 = "docker push $ImageUriLatest"

if ($DryRun) {
    Write-Host "[DRY RUN] $PushCmd1" -ForegroundColor Yellow
    Write-Host "[DRY RUN] $PushCmd2" -ForegroundColor Yellow
} else {
    try {
        Write-Host "Executing: docker push $ImageUri" -ForegroundColor Gray
        Invoke-Expression $PushCmd1

        Write-Host "Executing: docker push $ImageUriLatest" -ForegroundColor Gray
        Invoke-Expression $PushCmd2

        Write-Host "✓ ECR push successful" -ForegroundColor Green
    } catch {
        Write-Host "✗ ECR push failed: $_" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# ============================================================================
# Complete
# ============================================================================

Write-Host "========================================" -ForegroundColor Green
Write-Host "✓ Phase 2 Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Successfully uploaded to ECR:"
Write-Host "  - Image URI: $ImageUri" -ForegroundColor Green
Write-Host "  - Latest Tag: $ImageUriLatest" -ForegroundColor Green
Write-Host ""
Write-Host "Next step: Register task definition in Phase 3" -ForegroundColor Yellow
Write-Host "  .\scripts\register-task-definition.ps1" -ForegroundColor Yellow
Write-Host ""
