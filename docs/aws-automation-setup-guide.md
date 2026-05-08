# AWS 自動化セットアップガイド（EventBridge + Lambda）

このガイドでは、Playwright Cloud Executer を **1時間ごとに自動実行** するための EventBridge + Lambda の設定方法を説明します。

---

## 前提条件

以下がすべて完了していることを確認してください：

✅ **フェーズ1-3 の完了**
- Playwright アプリケーション実装済み
- Docker イメージが ECR にプッシュ済み
- ECS タスク定義が登録済み

✅ **AWS リソースの作成**
- IAM ロール: `Playwright-Role` （Fargate タスク実行用）
- ECS クラスター: `playwright-cloud-executer-cluster`
- ECS タスク定義: `playwright-cloud-executer`
- S3 バケット: `PlaywrightOutput`
- CloudWatch ロググループ: `/ecs/playwright-cloud-executer`

✅ **ローカル環境**
- AWS CLI v2 以上がインストール済み
- PowerShell 5.0 以上
- AWS CLI 認証設定済み（`aws configure`）

---

## 実装内容

このフェーズで設定される内容：

| リソース | 説明 | 役割 |
|---------|------|------|
| **Lambda 関数** | `playwright-scheduler` | EventBridge のトリガーを受けて Fargate タスクを起動 |
| **EventBridge ルール** | `playwright-hourly-schedule` | 毎時0分に Lambda を呼び出す |
| **IAM インラインポリシー** | `playwright-ecs-execution` | Lambda が ECS RunTask を実行する権限 |
| **Lambda 環境変数** | 複数 | SUBNET_ID, SECURITY_GROUP_ID など |

### データフロー

```
EventBridge ルール (毎時0分 UTC/JST)
         ↓
Lambda 関数 (playwright-scheduler)
         ↓
ECS RunTask API
         ↓
Fargate タスク (playwright-cloud-executer)
         ↓
Playwright スクレイピング実行
         ↓
S3 に結果保存
```

---

## セットアップ手順

### ステップ1: Lambda 関数を AWS Console で作成

現在、AWS Console から Lambda 関数を手動で作成する必要があります。以下の手順に従ってください：

1. **AWS Management Console にアクセス**
   - [Lambda コンソール](https://ap-northeast-1.console.aws.amazon.com/lambda/)

2. **関数を作成**
   - ボタン: 「関数を作成」
   - 関数名: `playwright-scheduler`
   - ランタイム: `Python 3.11`
   - アーキテクチャ: `x86_64`

3. **実行ロール**
   - 「AWS Lambda にロールを実行することを許可するための新しいロールを作成」を選択
   - ロール名: `service-role/playwright-scheduler-role` （自動生成）

4. **コード設定**
   - Lambda コンソールのエディタで、プロジェクトの `lambda-function/index.py` の内容をコピーして貼り付け
   - または ZIP ファイルでアップロード（後述）

5. **基本設定**
   - タイムアウト: `60` 秒
   - メモリ: `128` MB

6. **デプロイ**
   - 「Deploy」ボタンをクリック

### ステップ2: Lambda 関数コードをデプロイ

#### 方法A: ZIP ファイルでアップロード（推奨）

```powershell
# プロジェクトルートで PowerShell を開く
cd C:\Users\umesk\OneDrive\ドキュメント\Claude\Projects\PlaywrightCloudExecuter

# Lambda 関数ファイルを ZIP に圧縮
Compress-Archive -Path lambda-function\index.py -DestinationPath lambda-function.zip -Force

# Lambda にアップロード
aws lambda update-function-code `
  --function-name playwright-scheduler `
  --zip-file fileb://lambda-function.zip `
  --region ap-northeast-1 `
  --profile default
```

#### 方法B: AWS Console で直接編集

1. Lambda コンソール > `playwright-scheduler` 関数
2. コード タブ
3. `index.py` をコピー
4. コンソールエディタに貼り付け
5. Deploy をクリック

### ステップ3: 自動化セットアップスクリプトを実行

PowerShell を管理者権限で開き、プロジェクトルートで以下を実行：

```powershell
# プロジェクトルートに移動
cd C:\Users\umesk\OneDrive\ドキュメント\Claude\Projects\PlaywrightCloudExecuter

# スクリプトを実行
.\scripts\setup-automation.ps1 -AWSProfile default -AWSRegion ap-northeast-1
```

**スクリプトの実行内容:**
- ✅ Lambda 関数の存在確認
- ✅ VPC・Subnet・Security Group 情報の取得
- ✅ Lambda 実行ロールに ECS 権限を追加
- ✅ Lambda 環境変数を設定
- ✅ EventBridge ルール「playwright-hourly-schedule」を作成
- ✅ Lambda に EventBridge の呼び出し権限を付与
- ✅ EventBridge ターゲットに Lambda を指定

**期待される出力例:**

```
========================================
フェーズ4: EventBridge + Lambda 自動化設定
========================================

ステップ1: AWS アカウント情報の取得...
  AWS Account ID: 123456789012
  Region: ap-northeast-1

ステップ2: Lambda 関数の確認...
  Lambda ARN: arn:aws:lambda:ap-northeast-1:123456789012:function:playwright-scheduler

...

ステップ10: セットアップ結果の確認...
  Rule Name: playwright-hourly-schedule
  Rule State: ENABLED
  Schedule: cron(0 * * * ? *)

========================================
✓ フェーズ4 完了！
========================================
```

### ステップ4: EventBridge ルールのタイムゾーンを設定

スクリプト実行後、AWS Console で EventBridge ルールのタイムゾーンを **Asia/Tokyo** に変更します：

1. **EventBridge コンソール** > ルール > `playwright-hourly-schedule`
2. **ルールを編集**
3. **スケジュール**
   - タイムゾーン: `Asia/Tokyo` を選択
4. **保存**

この設定により、毎時0分が **日本時間** で実行されます：
- 09:00, 10:00, 11:00, ..., 23:00, 00:00, 01:00, ...

---

## 動作確認

### 方法1: Lambda を手動で実行

```powershell
# Lambda を手動実行（テスト）
aws lambda invoke `
  --function-name playwright-scheduler `
  --region ap-northeast-1 `
  --payload '{"site_name":"yahoo"}' `
  --profile default `
  response.json

# 結果を確認
Get-Content response.json | ConvertFrom-Json
```

**期待される出力:**

```json
{
  "statusCode": 200,
  "body": {
    "message": "Fargate task started successfully",
    "taskArn": "arn:aws:ecs:ap-northeast-1:123456789012:task/playwright-cloud-executer-cluster/...",
    "timestamp": "2026-05-08T12:34:56.789000",
    "site": "yahoo"
  }
}
```

### 方法2: CloudWatch Logs で実行ログを確認

1. **CloudWatch Logs コンソール**
   - ロググループ: `/aws/lambda/playwright-scheduler`
   - または `/ecs/playwright-cloud-executer`

2. **ログストリームを確認**
   - Lambda 実行ログ：Lambda の出力メッセージ
   - Fargate ログ：Playwright アプリケーション内の出力

### 方法3: ECS タスク実行状況を確認

```powershell
# 最近実行されたタスク一覧
aws ecs list-tasks `
  --cluster playwright-cloud-executer-cluster `
  --region ap-northeast-1 `
  --profile default `
  --output json | ConvertFrom-Json

# 特定タスクの詳細確認
aws ecs describe-tasks `
  --cluster playwright-cloud-executer-cluster `
  --tasks <TASK_ARN> `
  --region ap-northeast-1 `
  --profile default `
  --output json
```

### 方法4: S3 の結果を確認

```powershell
# S3 バケットの内容を確認
aws s3 ls s3://PlaywrightOutput/ --recursive --profile default
```

---

## トラブルシューティング

### Lambda 実行エラー: `Missing environment variables`

**原因**: SUBNET_ID または SECURITY_GROUP_ID が設定されていない

**対処**:
```powershell
# 環境変数を確認
aws lambda get-function-configuration `
  --function-name playwright-scheduler `
  --region ap-northeast-1 `
  --profile default

# 環境変数を手動で設定
aws lambda update-function-configuration `
  --function-name playwright-scheduler `
  --region ap-northeast-1 `
  --environment Variables={SUBNET_ID=subnet-xxxxx,SECURITY_GROUP_ID=sg-xxxxx} `
  --profile default
```

### EventBridge ルールが実行されない

**原因1**: ルール状態が「DISABLED」になっている

**対処**:
```powershell
# ルールを有効化
aws events put-rule `
  --name playwright-hourly-schedule `
  --state ENABLED `
  --region ap-northeast-1 `
  --profile default
```

**原因2**: Lambda 権限がない

**対処**:
```powershell
# Lambda 権限を確認
aws lambda get-policy `
  --function-name playwright-scheduler `
  --region ap-northeast-1 `
  --profile default

# 権限を手動で追加
aws lambda add-permission `
  --function-name playwright-scheduler `
  --statement-id AllowEventBridgeInvoke `
  --action lambda:InvokeFunction `
  --principal events.amazonaws.com `
  --source-arn arn:aws:events:ap-northeast-1:123456789012:rule/playwright-hourly-schedule `
  --region ap-northeast-1 `
  --profile default
```

### Fargate タスク起動失敗：`InvalidParameterException`

**原因**: SUBNET_ID または SECURITY_GROUP_ID が無効

**対処**:
```powershell
# VPC・Subnet・Security Group を再確認
$VPC_ID = (aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text --region ap-northeast-1 --profile default)
$SUBNET_ID = (aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[0].SubnetId" --output text --region ap-northeast-1 --profile default)
$SG_ID = (aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[0].GroupId" --output text --region ap-northeast-1 --profile default)

Write-Host "Subnet: $SUBNET_ID"
Write-Host "Security Group: $SG_ID"
```

### CloudWatch Logs にログが出力されない

**原因**: 実行ロールに CloudWatch Logs 権限がない

**対処**:
1. Lambda 実行ロール（`service-role/playwright-scheduler-role`）を確認
2. 以下のポリシーをアタッチ：
   - `AWSLambdaBasicExecutionRole`
   - または `CloudWatchLogsFullAccess`

---

## Lambda 関数コードの仕様

### 入力イベント (Event)

```json
{
  "site_name": "yahoo"
}
```

| フィールド | 型 | 説明 | デフォルト |
|-----------|------|------|----------|
| `site_name` | string | スクレイピング対象のサイト名 | `yahoo` |

### 環境変数

| 変数名 | 説明 | 例 |
|--------|------|-----|
| `AWS_REGION` | AWS リージョン | `ap-northeast-1` |
| `SUBNET_ID` | VPC サブネット ID | `subnet-12345678` |
| `SECURITY_GROUP_ID` | セキュリティグループ ID | `sg-12345678` |
| `ECS_CLUSTER` | ECS クラスター名 | `playwright-cloud-executer-cluster` |
| `TASK_DEFINITION` | ECS タスク定義（リビジョン付き） | `playwright-cloud-executer:1` |

### 出力レスポンス

**成功時 (statusCode: 200)**

```json
{
  "statusCode": 200,
  "body": {
    "message": "Fargate task started successfully",
    "taskArn": "arn:aws:ecs:...",
    "timestamp": "2026-05-08T12:34:56.789000",
    "site": "yahoo"
  }
}
```

**エラー時 (statusCode: 500)**

```json
{
  "statusCode": 500,
  "body": {
    "error": "Error launching Fargate task: ..."
  }
}
```

---

## EventBridge ルール仕様

| 設定項目 | 値 | 説明 |
|---------|-----|------|
| **ルール名** | `playwright-hourly-schedule` | - |
| **スケジュール式** | `cron(0 * * * ? *)` | 毎時0分 (UTC) |
| **タイムゾーン** | `Asia/Tokyo` | 日本時間に変換 |
| **ターゲット** | Lambda 関数 `playwright-scheduler` | - |
| **入力変換** | `{"site_name":"yahoo"}` | Lambda に渡すペイロード |

### タイムゾーン設定時の実行時刻

EventBridge のタイムゾーン設定が `Asia/Tokyo` の場合：

```
毎時0分 JST で実行：
  09:00, 10:00, 11:00, 12:00, ..., 22:00, 23:00, 00:00, ...
```

UTC との対応：

```
09:00 JST = 00:00 UTC
10:00 JST = 01:00 UTC
...
23:00 JST = 14:00 UTC
00:00 JST = 15:00 UTC (前日)
```

---

## 次のステップ

✅ **本セットアップ完了後:**
1. 手動テスト（上記「動作確認」参照）でシステムが正常に動作することを確認
2. CloudWatch Logs でログを監視
3. 1時間後に自動実行されることを確認
4. S3 に結果が保存されていることを確認

✅ **今後の改善:**
- CloudWatch アラーム設定（エラー時の通知）
- 複数サイトの並列実行
- 実行頻度の調整（毎30分など）
- Slack・メール通知の追加

---

## 参考リソース

- [AWS EventBridge ドキュメント](https://docs.aws.amazon.com/eventbridge/)
- [AWS Lambda ドキュメント](https://docs.aws.amazon.com/lambda/)
- [Amazon ECS ドキュメント](https://docs.aws.amazon.com/ecs/)
- [CloudWatch Logs ドキュメント](https://docs.aws.amazon.com/AmazonCloudWatch/)

---
