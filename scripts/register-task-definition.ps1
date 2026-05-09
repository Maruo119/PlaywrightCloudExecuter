# ============================================================================
# register-task-definition.ps1
# ============================================================================
# Phase 3: Register ECS task definition
#
# Usage:
#   .\scripts\register-task-definition.ps1
#
# Prerequisites:
#   - AWS CLI installed
#   - AWS CLI profile (default) configured
#   - ecs-task-definition.json exists in project root
# ============================================================================

param(
    [string]$Profile = "default",
    [string]$Region = "ap-northeast-1",
    [string]$TaskDefinitionFile = ".\ecs-task-definition.json",
    [switch]$DryRun = $false
)

# ============================================================================
# Configuration
# ============================================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Phase 3: ECS Task Definition Registration" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Region: $Region" -ForegroundColor Yellow
Write-Host "Task Definition File: $TaskDefinitionFile" -ForegroundColor Yellow
Write-Host ""

# ============================================================================
# Step 1: Verify Task Definition File
# ============================================================================

Write-Host "Step 1: Verifying task definition file..." -ForegroundColor Cyan

if (-not (Test-Path $TaskDefinitionFile)) {
    Write-Host "✗ Error: Task definition file not found: $TaskDefinitionFile" -ForegroundColor Red
    exit 1
}

try {
    $TaskDefinition = Get-Content $TaskDefinitionFile | ConvertFrom-Json
    Write-Host "✓ Task definition file loaded successfully" -ForegroundColor Green
    Write-Host "  - Family: $($TaskDefinition.family)" -ForegroundColor Gray
    Write-Host "  - CPU: $($TaskDefinition.cpu)" -ForegroundColor Gray
    Write-Host "  - Memory: $($TaskDefinition.memory)" -ForegroundColor Gray
} catch {
    Write-Host "✗ Failed to parse task definition file: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""

# ============================================================================
# Step 2: Register Task Definition
# ============================================================================

Write-Host "Step 2: Registering task definition with AWS..." -ForegroundColor Cyan

$RegisterCmd = "aws ecs register-task-definition --cli-input-json file://$TaskDefinitionFile --region $Region --profile $Profile"

if ($DryRun) {
    Write-Host "[DRY RUN] Task definition registration command:" -ForegroundColor Yellow
    Write-Host $RegisterCmd -ForegroundColor Yellow
} else {
    try {
        Write-Host "Executing: aws ecs register-task-definition..." -ForegroundColor Gray
        $Result = Invoke-Expression $RegisterCmd | ConvertFrom-Json

        if ($Result.taskDefinition) {
            $TaskDefArn = $Result.taskDefinition.taskDefinitionArn
            $TaskDefRev = $Result.taskDefinition.revision

            Write-Host "✓ Task definition registered successfully" -ForegroundColor Green
            Write-Host "  - ARN: $TaskDefArn" -ForegroundColor Green
            Write-Host "  - Revision: $TaskDefRev" -ForegroundColor Green
        } else {
            throw "Failed to register task definition"
        }
    } catch {
        Write-Host "✗ Task definition registration failed: $_" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# ============================================================================
# Step 3: Verify Task Definition Registration
# ============================================================================

Write-Host "Step 3: Verifying task definition registration..." -ForegroundColor Cyan

$DescribeCmd = "aws ecs describe-task-definition --task-definition playwright-cloud-executer --region $Region --profile $Profile"

if ($DryRun) {
    Write-Host "[DRY RUN] Task definition verification command:" -ForegroundColor Yellow
    Write-Host $DescribeCmd -ForegroundColor Yellow
} else {
    try {
        Write-Host "Executing: aws ecs describe-task-definition..." -ForegroundColor Gray
        $DescribeResult = Invoke-Expression $DescribeCmd | ConvertFrom-Json

        if ($DescribeResult.taskDefinition) {
            $Family = $DescribeResult.taskDefinition.family
            $Revision = $DescribeResult.taskDefinition.revision
            $Status = $DescribeResult.taskDefinition.status
            $Image = $DescribeResult.taskDefinition.containerDefinitions[0].image

            Write-Host "✓ Task definition verified successfully" -ForegroundColor Green
            Write-Host "  - Family: $Family" -ForegroundColor Green
            Write-Host "  - Revision: $Revision" -ForegroundColor Green
            Write-Host "  - Status: $Status" -ForegroundColor Green
            Write-Host "  - Image: $Image" -ForegroundColor Green
        } else {
            throw "Failed to verify task definition"
        }
    } catch {
        Write-Host "✗ Task definition verification failed: $_" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# ============================================================================
# Complete
# ============================================================================

Write-Host "========================================" -ForegroundColor Green
Write-Host "✓ Phase 3 Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Task definition registered successfully:"
Write-Host "  - Family: playwright-cloud-executer" -ForegroundColor Green
Write-Host ""
Write-Host "Next step: Execute Fargate task manually in Phase 4" -Fo