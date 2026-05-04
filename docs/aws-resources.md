# AWS リソース一覧と作成手順

## 📋 実装状況

### フェーズ1: ローカル開発 ✅ 完了
- ✓ Node.js / TypeScript 環境
- ✓ Playwright 実装
- ✓ Yahoo スクレイパー実装（title 取得）
- ✓ S3 保存コード実装
- ✓ ログ・エラーハンドリング実装

### フェーズ2-3: ローカルテスト ✅ 完了
- ✓ npm run dev で動作確認済み
- ✓ Yahoo から「Yahoo! JAPAN」タイトル取得確認
- ✓ Docker コンテナ化対応

### フェーズ4: AWS デプロイ ⏳ 次ステップ
- ⏳ IAM ロール・ユーザー作成
- ⏳ ECR リポジトリ作成
- ⏳ S3 バケット作成
- ⏳ ECS Fargate セットアップ
- ⏳ Lambda・EventBridge 設定

---

## リソース一覧

| リソース種別 | 名称 | リージョン | タグ | 備考 |
|-------------|-----|---------|------|------|
| IAM ロール | Playwright-Role | - | PlaywrightCloudExecuter=true | ECS実行用 |
| IAM ユーザー | Playwright_User | - | PlaywrightCloudExecuter=true | 開発者用 |
| ECR リポジトリ | playwright-cloud-executer | ap-northeast-1 | PlaywrightCloudExecuter=true | Docker イメージ格納 |
| CloudWatch ロググループ | /ecs/playwright-cloud-executer | ap-northeast-1 | PlaywrightCloudExecuter=true | Fargate ログ記録 |
| ECS クラスター | playwright-cloud-executer-cluster | ap-northeast-1 | PlaywrightCloudExecuter=true | Fargate クラスター |
| ECS タスク定義 | playwright-cloud-executer | ap-northeast-1 | PlaywrightCloudExecuter=true | コンテナ実行定義 |
| Lambda 関数 | playwright-scheduler | ap-northeast-1 | PlaywrightCloudExecuter=true | スケジューラー |
| EventBridge 規則 | playwright-hourly-schedule | ap-northeast-1 | PlaywrightCloudExecuter=true | 定期実行ルール |
| S3 バケット | PlaywrightOutput | ap-northeast-1 | PlaywrightCloudExecuter=true | 結果保存先 |
| セキュリティグループ | playwright-sg | ap-northeast-1 | PlaywrightCloudExecuter=true | ネットワーク制御 |

## 作成手順（AWS Console使用）

### 1. IAM ロール「Playwright-Role」の作成

1. AWS Management Console > IAM > ロール > ロールを作成
2. **信頼されるエンティティの種類**: AWS サービス
3. **ユースケース**: Elastic Container Service > Elastic Container Service タスク
4. **ポリシーをアタッチ**:
   - `AmazonEC2ContainerRegistryReadOnly`
   - `CloudWatchLogsFullAccess`
5. **ロール名**: `Playwright-Role`
6. **タグ**: `PlaywrightCloudExecuter=true`
7. 作成

### 2. IAM ユーザー「Playwright_User」の作成

1. AWS Management Console > IAM > ユーザー > ユーザーを作成
2. **ユーザー名**: `Playwright_User`
3. **認証情報タイプ**: プログラマティックアクセス
4. **ポリシーをアタッチ**:
   - `AmazonECS_FullAccess`
   - `AmazonEC2ContainerRegistryFullAccess`
   - `CloudWatchLogsFullAccess`
5. **タグ**: `PlaywrightCloudExecuter=true`
6. 作成
7. **重要**: Access Key ID と Secret Access Key を控える（後で使用）

### 3. ECR リポジトリ「playwright-cloud-executer」の作成

1. AWS Management Console > ECR > リポジトリ > リポジトリを作成
2. **リポジトリ名**: `playwright-cloud-executer`
3. **タグの不変性**: 無効
4. **イメージスキャン**: 有効
5. **タグ**: `PlaywrightCloudExecuter=true`
6. 作成
7. **リポジトリ URI を控える** (例: `123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/playwright-cloud-executer`)

### 4. CloudWatch Logs グループの作成

1. AWS Management Console > CloudWatch > ロググループ > ロググループを作成
2. **ロググループ名**: `/ecs/playwright-cloud-executer`
3. **保有期間**: 30 日
4. **タグ**: `PlaywrightCloudExecuter=true`
5. 作成

### 5. ECS クラスターの作成

1. AWS Management Console > ECS > クラスター > クラスターを作成
2. **クラスター名**: `playwright-cloud-executer-cluster`
3. **インフラストラクチャ**: AWS Fargate
4. **CloudWatch Container Insights**: 有効
5. **タグ**: `PlaywrightCloudExecuter=true`
6. 作成

### 6. ECS タスク定義の作成

1. AWS Management Console > ECS > タスク定義 > 新しいタスク定義を作成
2. **タスク定義ファミリー**: `playwright-cloud-executer`
3. **起動タイプ**: Fargate
4. **リージョン**: ap-northeast-1
5. **ネットワークモード**: awsvpc
6. **CPU**: 0.5 vCPU
7. **メモリ**: 1024 MB
8. **タスク実行ロール**: `Playwright-Role`
9. **コンテナ定義**:
   - **名前**: `playwright-container`
   - **イメージ**: `{ECR_REPOSITORY_URI}:latest`
   - **メモリ割り当て**: 1024 MB
   - **ログ設定**:
     - **ログドライバー**: awslogs
     - **ロググループ**: `/ecs/playwright-cloud-executer`
     - **ログストリームプレフィックス**: `ecs`
     - **リージョン**: `ap-northeast-1`
   - **環境変数**:
     ```
     NODE_ENV=production
     LOG_LEVEL=info
     AWS_REGION=ap-northeast-1
     BROWSER_HEADLESS=true
     ```
10. **タグ**: `PlaywrightCloudExecuter=true`
11. 作成

### 7. S3 バケット「PlaywrightOutput」の作成

1. AWS Management Console > S3 > バケット > バケットを作成
2. **バケット名**: `PlaywrightOutput` (リージョン別に `PlaywrightOutput-{account-id}` 等に変更可)
3. **リージョン**: ap-northeast-1
4. **バージョニング**: 無効
5. **タグ**: `PlaywrightCloudExecuter=true`
6. **アクセス許可**: ブロックパブリックアクセス（デフォルト推奨）
7. 作成

### 8. Lambda 関数「playwright-scheduler」の作成

1. AWS Management Console > Lambda > 関数を作成
2. **関数名**: `playwright-scheduler`
3. **ランタイム**: Python 3.11
4. **実行ロール**: 新しいロールを作成（または既存ロール使用）
5. **関数コード**: Lambda コンソールエディタで以下を入力

```python
import boto3
import json
import os
from datetime import datetime

ecs_client = boto3.client('ecs', region_name='ap-northeast-1')

def lambda_handler(event, context):
    """
    EventBridgeから定期的に呼び出され、Fargateタスクを起動する
    """
    try:
        cluster = 'playwright-cloud-executer-cluster'
        task_definition = 'playwright-cloud-executer:1'
        subnet = os.environ['SUBNET_ID']
        security_group = os.environ['SECURITY_GROUP_ID']
        site_name = event.get('site_name', 'yahoo')

        response = ecs_client.run_task(
            cluster=cluster,
            taskDefinition=task_definition,
            launchType='FARGATE',
            networkConfiguration={
                'awsvpcConfiguration': {
                    'subnets': [subnet],
                    'securityGroups': [security_group],
                    'assignPublicIp': 'ENABLED'
                }
            },
            overrides={
                'containerOverrides': [
                    {
                        'name': 'playwright-container',
                        'environment': [
                            {'name': 'SITE_NAME', 'value': site_name},
                            {'name': 'AWS_S3_BUCKET', 'value': 'PlaywrightOutput'}
                        ]
                    }
                ]
            }
        )

        task_arn = response['tasks'][0]['taskArn']
        print(f"Task started: {task_arn}")

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Fargate task started successfully',
                'taskArn': task_arn,
                'timestamp': datetime.utcnow().isoformat()
            })
        }

    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
```

6. **環境変数**: Lambda コンソールで以下を設定
   - `SUBNET_ID`: VPC のサブネット ID （例: subnet-12345678）
   - `SECURITY_GROUP_ID`: セキュリティグループ ID （例: sg-12345678）
7. **タイムアウト**: 60 秒
8. **メモリ**: 128 MB
9. **タグ**: `PlaywrightCloudExecuter=true`
10. デプロイ

### 9. EventBridge 規則「playwright-hourly-schedule」の作成

1. AWS Management Console > EventBridge > ルール > ルールを作成
2. **ルール名**: `playwright-hourly-schedule`
3. **説明**: Playwright Fargateタスクを1時間ごとに実行
4. **ルールタイプ**: スケジュール
5. **スケジュール式（Cron）**: `0 * * * ? *` (毎時0分 UTC)
6. **タイムゾーン**: Asia/Tokyo （ローカルタイムに変換：9時間進める）
7. **ターゲット**:
   - **ターゲットタイプ**: AWS Lambda 関数
   - **関数**: `playwright-scheduler`
   - **トランスフォーメーション** (オプション):
     ```json
     {
       "site_name": "yahoo"
     }
     ```
8. **タグ**: `PlaywrightCloudExecuter=true`
9. 作成

### 10. セキュリティグループの作成

1. AWS Management Console > VPC > セキュリティグループ > セキュリティグループを作成
2. **セキュリティグループ名**: `playwright-sg`
3. **VPC**: 既存VPC を選択
4. **インバウンドルール**: 
   - 不要（Fargate タスク内部用）
5. **アウトバウンドルール**:
   - **タイプ**: HTTPS
   - **プロトコル**: TCP
   - **ポート**: 443
   - **宛先**: 0.0.0.0/0 (すべてのIP)
6. **タグ**: `PlaywrightCloudExecuter=true`
7. 作成

## リソース間の関連付け

### Lambda 関数への IAM ロール付与

Lambda 関数が Fargate タスクを起動するための権限を付与：

1. Lambda 関数の実行ロールに以下のインラインポリシーを追加

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:RunTask"
      ],
      "Resource": "arn:aws:ecs:ap-northeast-1:*:task-definition/playwright-cloud-executer:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:PassRole"
      ],
      "Resource": "arn:aws:iam::*:role/Playwright-Role"
    }
  ]
}
```

## アカウントID と リージョンの確認

### アカウント ID の取得
```bash
aws sts get-caller-identity --query Account --output text
```

### リージョンの確認
```bash
aws configure get region
```

## AWS CLI での確認コマンド

### リソース一覧確認
```bash
# IAM ロール確認
aws iam get-role --role-name Playwright-Role

# ECR リポジトリ確認
aws ecr describe-repositories --repository-names playwright-cloud-executer --region ap-northeast-1

# ECS クラスター確認
aws ecs describe-clusters --clusters playwright-cloud-executer-cluster --region ap-northeast-1

# Lambda 関数確認
aws lambda get-function --function-name playwright-scheduler --region ap-northeast-1

# EventBridge 規則確認
aws events describe-rule --name playwright-hourly-schedule --region ap-northeast-1
```

## タグ付与の確認

すべてのリソースに `PlaywrightCloudExecuter=true` タグが付与されているか確認：

```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filter 'Key=PlaywrightCloudExecuter,Values=true' \
  --region ap-northeast-1
```
