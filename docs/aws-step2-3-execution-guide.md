# AWS Step2・3 実行ガイド（スクリプト自動化版）

このガイドは、フェーズ2・3 をスクリプトで自動化して実行するための手順です。

---

## 前提条件

✅ **AWS Console 上の Phase 1 が完了していること:**
- IAM ロール `Playwright-ExecutionRole` が作成済み
- ECR リポジトリ `playwright-cloud-executer` が作成済み
- ECS クラスター `playwright-cloud-executer-cluster` が作成済み
- CloudWatch ロググループ `/ecs/playwright-cloud-executer` が作成済み
- S3 バケット `playwright-output-bucket` が存在すること

✅ **ローカル環境に以下がインストール済み:**
- Docker Desktop（Windows 11 で起動状態）
- AWS CLI v2 以上
- PowerShell 5.0 以上

✅ **AWS CLI 認証設定:**
```powershell
# 設定済みか確認
aws configure list --profile default

# リージョンが ap-northeast-1 で、認証情報が設定されていることを確認
```

---

## 記録すべき情報

以下の情報は、スクリプト実行前に確認してください：

| 項目 | 値 | 例 |
|------|-----|-----|
| AWS Account ID | `${AWS_ACCOUNT_ID}` | `123456789012` |
| Region | `${AWS_REGION}` | `ap-northeast-1` |
| ExecutionRole ARN | `arn:aws:iam::${AWS_ACCOUNT_ID}:role/Playwright-ExecutionRole` | `arn:aws:iam::123456789012:role/Playwright-ExecutionRole` |
| ECR Repository URI | `${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/playwright-cloud-executer` | `123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/playwright-cloud-executer` |
| ECS Cluster Name | `playwright-cloud-executer-cluster` | `playwright-cloud-executer-cluster` |
| S3 Bucket | `playwright-output-bucket` | `playwright-output-bucket` |

**⚠️ シークレット情報の注意:**
- AWS Account ID や ARN は機密情報です
- リポジトリに commit する前に、必ずマスキング版を使用してください
- ローカルでの実行時は、自分の AWS Account ID に置き換えて実行してください

---

## 実行手順

### **フェーズ2: Docker イメージのビルド・ECR へプッシュ**

#### ステップ1: プロジェクトルートで PowerShell を開く

```powershell
# プロジェクトディレクトリに移動
cd C:\Users\umesk\OneDrive\ドキュメント\Claude\Projects\PlaywrightCloudExecuter
```

#### ステップ2: スクリプトを実行

```powershell
# フェーズ2 スクリプトを実行
.\scripts\deploy-docker-to-ecr.ps1
```

**実行内容:**
1. ✅ AWS アカウント ID を取得
2. ✅ ECR へのログイン
3. ✅ Docker イメージをビルド（所要時間: 10-15分）
4. ✅ イメージにタグを付与
5. ✅ ECR へプッシュ

**期待される出力:**
```
========================================
フェーズ2: Docker イメージのビルド・プッシュ
========================================
AWS Account ID: ${AWS_ACCOUNT_ID}
Region: ap-northeast-1
ECR Registry: ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com
Image URI: ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/playwright-cloud-executer:latest

ステップ1: ECR へのログイン...
✓ ECR ログイン成功

ステップ2: Docker イメージをビルド...
✓ Docker イメージビルド成功: playwright-cloud-executer:latest

ステップ3: イメージにタグを付与...
✓ イメージタグ付け成功

ステップ4: イメージを ECR へプッシュ...
✓ ECR へのプッシュ成功

========================================
✓ フェーズ2 完了！
========================================

ECR にアップロード完了:
  - Image URI: 442426886752.dkr.ecr.ap-northeast-1.amazonaws.com/playwright-cloud-executer:latest
  - Latest Tag: 442426886752.dkr.ecr.ap-northeast-1.amazonaws.com/playwright-cloud-executer:latest

次のステップ: フェーズ3 でタスク定義を登録してください
  .\scripts\register-task-definition.ps1
```

✅ **完了後の確認:**

AWS Console で ECR リポジトリを確認：
- ECR コンソール → リポジトリ → `playwright-cloud-executer`
- イメージが `latest` タグで存在することを確認

---

### **フェーズ3: ECS タスク定義の登録**

#### ステップ0: タスク定義ファイルを準備

**注意: `ecs-task-definition.json` はシークレット情報を含むため .gitignore に登録されています。**

以下の手順で自分の環境用ファイルを準備してください：

```powershell
# サンプル版から自分用ファイルを作成
Copy-Item .\ecs-task-definition.template.json .\ecs-task-definition.json

# ecs-task-definition.json をテキストエディタで開いて、以下を置換
# ${AWS_ACCOUNT_ID} をあなたの AWS Account ID に置換
# 例: 442426886752
```

**ファイルの場所:**
```
プロジェクトルート/
├── ecs-task-definition.json        ← ローカル用（git 対象外）
└── ecs-task-definition.template.json ← サンプル版（git 登録済み）
```

#### ステップ1: タスク定義ファイルの確認

以下のファイルが存在することを確認してください：

```
プロジェクトルート/
├── ecs-task-definition.json           ← ローカル用（${AWS_ACCOUNT_ID} を置換済み）
├── ecs-task-definition.template.json  ← サンプル版（git 登録済み）
└── scripts/
    └── register-task-definition.ps1
```

✅ **ecs-task-definition.json の確認:**
- `${AWS_ACCOUNT_ID}` が自分の AWS Account ID に置換されているか
- `.gitignore` に登録されているため git の対象外です

**ファイル内容の確認** - `ecs-task-definition.json` の重要な部分：

```json
{
  "family": "playwright-cloud-executer",
  "cpu": "512",
  "memory": "1024",
  "taskRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/Playwright-ExecutionRole",
  "executionRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/Playwright-ExecutionRole",
  "containerDefinitions": [
    {
      "image": "${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/playwright-cloud-executer:latest",
      "logConfiguration": {
        "awslogs-group": "/ecs/playwright-cloud-executer",
        "awslogs-region": "ap-northeast-1"
      }
    }
  ]
}
```

**⚠️ 重要: 実行前の確認**
- `${AWS_ACCOUNT_ID}` をあなたの AWS Account ID に置き換えてください
- ExecutionRole ARN がユーザーの設定と一致しているか確認してください

#### ステップ2: スクリプトを実行

```powershell
# フェーズ3 スクリプトを実行
.\scripts\register-task-definition.ps1
```

**実行内容:**
1. ✅ タスク定義ファイルを読み込み
2. ✅ AWS にタスク定義を登録
3. ✅ 登録結果を確認

**期待される出力:**
```
========================================
フェーズ3: ECS タスク定義の登録
========================================
Region: ap-northeast-1
Task Definition File: .\ecs-task-definition.json

ステップ1: タスク定義ファイルを確認...
✓ タスク定義ファイル読み込み成功
  - Family: playwright-cloud-executer
  - CPU: 512
  - Memory: 1024

ステップ2: タスク定義を AWS に登録...
✓ タスク定義登録成功
  - ARN: arn:aws:ecs:ap-northeast-1:${AWS_ACCOUNT_ID}:task-definition/playwright-cloud-executer:1
  - Revision: 1

ステップ3: 登録されたタスク定義を確認...
✓ タスク定義確認成功
  - Family: playwright-cloud-executer
  - Revision: 1
  - Status: ACTIVE
  - Image: ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/playwright-cloud-executer:latest

========================================
✓ フェーズ3 完了！
========================================

タスク定義が登録されました:
  - Family: playwright-cloud-executer

次のステップ: フェーズ4 で Fargate タスクを手動実行してください
  aws ecs run-task --cluster playwright-cloud-executer-cluster ...
```

✅ **完了後の確認:**

AWS Console で ECS タスク定義を確認：
- ECS コンソール → タスク定義 → `playwright-cloud-executer`
- リビジョン `1` が ACTIVE 状態で存在することを確認

---

## トラブルシューティング

### フェーズ2: Docker ビルドエラー

**エラー**: `docker: command not found`

**原因**: Docker Desktop が起動していない

**対処**:
```powershell
# Docker Desktop が起動しているか確認
docker --version

# 起動していない場合はスタートメニューから起動
```

---

### フェーズ2: ECR ログインエラー

**エラー**: `Error response from daemon: login attempt to ... failed`

**原因**: AWS CLI 認証情報が正しくない

**対処**:
```powershell
# AWS CLI プロファイル確認
aws configure list --profile default

# 認証情報を修正
aws configure --profile default
```

---

### フェーズ2: Docker ビルド時間が長い

**状況**: ビルドに 20 分以上かかっている

**原因**: Playwright ブラウザのダウンロード・インストール中

**対処**: そのまま待機してください。初回ビルドは時間がかかります。

---

### フェーズ3: タスク定義登録エラー

**エラー**: `Invalid request provided: CreateCluster Invalid Request`

**原因**: タスク定義ファイルの JSON が不正な可能性

**対処**:
```powershell
# ファイルの JSON 形式を確認
Get-Content .\ecs-task-definition.json | ConvertFrom-Json

# エラーが出る場合は、JSON ファイルを手動で修正
```

---

### フェーズ3: iam:PassRole エラー

**エラー**: `User: arn:aws:iam::... is not authorized to perform: iam:PassRole`

**原因**: IAM ユーザーに `iam:PassRole` 権限がない

**対処**: AWS コンソールで `playwrightExecuterUser` に以下の権限をアタッチ：
```json
{
  "Effect": "Allow",
  "Action": ["iam:PassRole"],
  "Resource": "arn:aws:iam::*:role/Playwright-ExecutionRole"
}
```

---

## 次のステップ（フェーズ4）

フェーズ2・3 が完了したら、以下のコマンドで Fargate タスクを手動実行してください：

```powershell
# VPC・サブネット・セキュリティグループを取得
$VPC_ID = (aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text --region ap-northeast-1)
$SUBNET_ID = (aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[0].SubnetId" --output text --region ap-northeast-1)
$SG_ID = (aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[0].GroupId" --output text --region ap-northeast-1)

# Fargate タスクを実行
aws ecs run-task `
  --cluster playwright-cloud-executer-cluster `
  --task-definition playwright-cloud-executer:1 `
  --launch-type FARGATE `
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" `
  --region ap-northeast-1 `
  --profile default
```

**⚠️ 注意:** `--profile default` をご自分の AWS CLI プロファイルに置き換えてください

詳細はガイドドキュメント（`docs/aws-step4-manual-execution.md`）を参照してください。

---

## サマリー

| フェーズ | 実行内容 | 所要時間 | コマンド |
|---------|--------|--------|---------|
| 2 | Docker ビルド → ECR プッシュ | 15分 | `.\scripts\deploy-docker-to-ecr.ps1` |
| 3 | タスク定義登録 | 1分 | `.\scripts\register-task-definition.ps1` |
| **合計** | | **16分** | |

---
