# AWS Step1 セットアップガイド（Console操作手順）

このガイドは、AWS Console 上で Step1 に必要なリソースを手動で作成するための具体的な手順です。

---

## 前提条件

- AWS アカウントへのアクセス権限があること
- IAM ユーザーまたはルートユーザーであること（IAM 権限作成のため）
- S3 バケット `playwright-output-bucket` が既に存在すること

---

## 全体的なリソース一覧

Step1 で作成・設定が必要なリソース：

| # | リソース | サービス | 作成順序 | 状態 |
|---|---------|---------|--------|------|
| 1 | `Playwright-ExecutionRole` | IAM | **第1優先** | 新規作成 |
| 2 | `playwrightExecuterUser` | IAM | - | ✅ 既に存在 |
| 3 | `/ecs/playwright-cloud-executer` | CloudWatch Logs | **第2優先** | 新規作成 |
| 4 | `playwright-sg` | VPC (Security Group) | **第3優先** | 新規作成 |
| 5 | `playwright-cloud-executer` | ECR | **第4優先** | 新規作成 |
| 6 | `playwright-cloud-executer-cluster` | ECS | **第5優先** | 新規作成 |
| S3 既存 | `playwright-output-bucket` | S3 | - | ✅ 既に存在 |

---

## Step 1: IAM ロール作成

### 1.1 Playwright-ExecutionRole（統合ロール）

**ロールの役割**: 
- ECS が Fargate タスクを実行・管理するための権限
- Fargate タスク内のアプリケーション（Node.js）が S3・Secrets Manager・CloudWatch にアクセスするための権限
- **両方の役割を 1 つのロールに集約**

**AWS Console での操作**:

1. **IAM コンソールを開く**
   - URL: https://console.aws.amazon.com/iam/
   - 左メニュー → `ロール` をクリック

2. **「ロールを作成」をクリック**

3. **信頼されるエンティティを選択**
   - 「信頼されるエンティティの種類」: **AWS サービス**
   - 「ユースケース」: **Elastic Container Service** を選択
   - 「シナリオを選択」: **Elastic Container Service Task** を選択
   - 「次へ」をクリック

4. **権限を追加（既存ポリシー）**
   - 検索バーで以下のポリシーを 1 つずつ検索・追加：
     1. `AmazonECSTaskExecutionRolePolicy` ✅ チェック
     2. `CloudWatchLogsFullAccess` ✅ チェック
     3. `SecretsManagerReadAccess` ✅ チェック
   - 「次へ」をクリック

5. **ロール名を設定**
   - ロール名: **`Playwright-ExecutionRole`**
   - 説明: `Execution and task role for Playwright Cloud Executer (ECS execution + S3 + Secrets Manager + CloudWatch access)`
   - タグ（オプション）:
     - キー: `Project` / 値: `PlaywrightCloudExecuter`
   - 「ロールを作成」をクリック

6. **作成後、カスタムインラインポリシーを追加**
   - 作成されたロール `Playwright-ExecutionRole` をクリック
   - 「インラインポリシーを追加」セクション → **「ここをクリック」** または「ポリシーを追加」
   - 「JSON」タブ → 以下のコードをペースト:
   
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "s3:GetObject",
           "s3:PutObject",
           "s3:ListBucket"
         ],
         "Resource": [
           "arn:aws:s3:::playwright-output-bucket",
           "arn:aws:s3:::playwright-output-bucket/*"
         ]
       },
       {
         "Effect": "Allow",
         "Action": [
           "logs:CreateLogStream",
           "logs:PutLogEvents"
         ],
         "Resource": "arn:aws:logs:ap-northeast-1:*:log-group:/ecs/playwright-cloud-executer*"
       }
     ]
   }
   ```
   
   - ポリシー名: **`Playwright-S3-SecretsManager-Policy`**
   - 「ポリシーを作成」をクリック

✅ **完了**: `Playwright-ExecutionRole` が作成されました（ECS実行 + アプリケーション実行権限を統合）

---

### 1.2 既存 IAM ユーザー「playwrightExecuterUser」の確認

**ユーザーの役割**: 開発者が ECR へイメージをプッシュ、ECS タスクを起動するために必要な権限

**AWS Console での確認**:

1. **IAM コンソール → 左メニュー「ユーザー」**

2. **「playwrightExecuterUser」を検索・クリック**

3. **必要な権限があるか確認**
   
   以下のポリシーがアタッチされているか確認してください：
   
   ✅ **必須ポリシー（既にあるか確認）:**
   - `AmazonEC2ContainerRegistryPowerUser` - ECR へのプッシュに必要
   - `CloudWatchLogsReadOnlyAccess` - ログ確認に必要
   
   ✅ **必須な追加権限（なければ追加）:**
   
   以下のカスタムインラインポリシーがアタッチされているか確認。なければ追加してください：
   
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "ecs:RunTask",
           "ecs:UpdateService",
           "ecs:DescribeTaskDefinition",
           "ecs:DescribeTasks",
           "ecs:DescribeServices",
           "ecs:ListTasks"
         ],
         "Resource": "*"
       },
       {
         "Effect": "Allow",
         "Action": [
           "iam:PassRole"
         ],
         "Resource": "arn:aws:iam::*:role/Playwright-ExecutionRole"
       },
       {
         "Effect": "Allow",
         "Action": [
           "ec2:DescribeNetworkInterfaces",
           "ec2:DescribeSubnets",
           "ec2:DescribeSecurityGroups",
           "ec2:DescribeVpcs"
         ],
         "Resource": "*"
       }
     ]
   }
   ```
   
   **ポリシー追加手順**:
   - ユーザー `playwrightExecuterUser` のページ
   - 「インラインポリシーを追加」または「ポリシーをアタッチ」
   - 「JSON」タブ → 上記コードをペースト
   - ポリシー名: **`Playwright-ECS-Deployment-Policy`**
   - 「ポリシーを作成」をクリック

✅ **完了**: `playwrightExecuterUser` に必要な権限が確認/追加されました

---

## Step 2: CloudWatch ロググループ作成

**ロググループの役割**: Fargate タスクが出力するログを集約・保管する

**AWS Console での操作**:

1. **CloudWatch コンソールを開く**
   - URL: https://console.aws.amazon.com/cloudwatch/
   - 左メニュー → 「ログ」 → 「ロググループ」

2. **「ロググループを作成」をクリック**

3. **ロググループの詳細を指定**
   - ロググループ名: **`/ecs/playwright-cloud-executer`**
   - ⚠️ **先頭の `/ecs/` は必須** です。ECS タスク定義と一致させる必要があります
   - 「作成」をクリック

4. **保有期間を設定（オプション）**
   - 作成されたロググループをクリック
   - 右上「アクション」 → 「ログ保持期間を編集」
   - 保有期間: **30 日**（推奨）
   - 「保存」をクリック

✅ **完了**: CloudWatch ロググループが作成されました

---

## Step 3: セキュリティグループの作成/確認

**セキュリティグループの役割**: Fargate タスクのネットワーク通信を制限

**AWS Console での操作**:

1. **EC2 コンソールを開く**
   - URL: https://console.aws.amazon.com/ec2/
   - 左メニュー → 「セキュリティグループ」

2. **セキュリティグループが存在するか確認**
   - `playwright-sg` という名前のセキュリティグループがあるか検索
   - **ある場合**: 以下を確認して OK
   - **ない場合**: 「セキュリティグループを作成」をクリック

3. **セキュリティグループの詳細（新規作成時）**
   - セキュリティグループ名: **`playwright-sg`**
   - 説明: `Security group for Playwright Cloud Executer`
   - VPC: **デフォルト VPC** を選択

4. **インバウンドルール**
   - **設定不要** （Fargate はインターネット受信を必要としません）

5. **アウトバウンドルール**
   - デフォルト設定: 「すべてのトラフィックを許可」 ✅ そのままで OK
   - または詳細設定:
     ```
     プロトコル: TCP
     ポート範囲: 443
     宛先: 0.0.0.0/0
     説明: HTTPS outbound for browser
     ```

6. **「セキュリティグループを作成」をクリック**

✅ **完了**: セキュリティグループが作成されました

---

## Step 4: ECR リポジトリ作成

**ECR の役割**: Docker イメージを格納・管理するレジストリ

**AWS Console での操作**:

1. **ECR コンソールを開く**
   - URL: https://console.aws.amazon.com/ecr/
   - 左メニュー → 「リポジトリ」

2. **「リポジトリを作成」をクリック**

3. **リポジトリ詳細を指定**
   - リポジトリ名: **`playwright-cloud-executer`**
   - スキャン時のイメージ: **チェック** ✅ （セキュリティスキャン有効）
   - イメージタグの不変性: **無効** で OK
   - 「作成」をクリック

4. **リポジトリ URI を記録**
   - 作成されたリポジトリをクリック
   - **URI** をメモ帳にコピー
   - 例: `123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/playwright-cloud-executer`
   - このURI は後で Docker イメージをプッシュする際に必要です

✅ **完了**: ECR リポジトリが作成されました

---

## Step 5: ECS クラスター作成

**クラスターの役割**: Fargate タスクを実行する基盤

**AWS Console での操作**:

1. **ECS コンソールを開く**
   - URL: https://console.aws.amazon.com/ecs/
   - 左メニュー → 「クラスター」

2. **「クラスターを作成」をクリック**

3. **クラスター設定**
   - クラスター名: **`playwright-cloud-executer-cluster`**
   - VPC: **デフォルト VPC** を選択
   - サブネット: **デフォルトのすべてのサブネット** を選択
   - セキュリティグループ: **`playwright-sg`** を選択
   - CloudWatch Container Insights: **有効** ✅ （推奨）
   - 「作成」をクリック

✅ **完了**: ECS クラスターが作成されました

---

## まとめ：各リソースの ARN / ID

以下の情報をメモ帳に記録してください。後のステップで必要になります。

| リソース名 | ARN / ID / URI | メモ |
|-----------|--------------|------|
| ExecutionRole | `arn:aws:iam::123456789012:role/Playwright-ExecutionRole` | IAM コンソール → ロール から確認 |
| DeployUser | `playwrightExecuterUser` | ✅ 既に存在（権限確認済み） |
| S3 Bucket | `playwright-output-bucket` | ✅ 既に存在 |
| CloudWatch Log Group | `/ecs/playwright-cloud-executer` | CloudWatch → ロググループ から確認 |
| Security Group ID | `sg-xxxxxxxx` | EC2 コンソール → セキュリティグループ → playwright-sg |
| ECR Repository URI | `123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/playwright-cloud-executer` | ECR コンソール → リポジトリ から確認 |
| ECS Cluster | `playwright-cloud-executer-cluster` | ECS コンソール → クラスター から確認 |

---

## トラブルシューティング

### IAM ロール作成後、ポリシーが見つからない

**原因**: ポリシー名を正確に入力していない

**解決策**:
1. IAM コンソール → 「ポリシー」で以下を検索:
   - `AmazonECSTaskExecutionRolePolicy`
   - `CloudWatchLogsFullAccess`
   - `SecretsManagerReadAccess`
   - `AmazonEC2ContainerRegistryPowerUser`

### CloudWatch ロググループ名に `/ecs/` がない

**原因**: ロググループ名が ECS タスク定義と一致していない

**解決策**:
1. CloudWatch コンソール → ロググループ
2. ロググループを削除
3. 正確に `/ecs/playwright-cloud-executer` で再作成

### セキュリティグループが見つからない

**原因**: VPC またはリージョンが異なる

**解決策**:
1. EC2 コンソール → セキュリティグループ
2. フィルター: VPC を「デフォルト VPC」、リージョンを「ap-northeast-1」に設定
3. 見つからない場合は新規作成

---

## 次のステップ

AWS Console 上でこれらのリソースが作成できたら、以下の情報を教えてください：

1. ✅ ExecutionRole の ARN - `arn:aws:iam::123456789012:role/Playwright-ExecutionRole`
2. ✅ SecurityGroup の ID - `sg-xxxxxxxx`
3. ✅ ECR Repository の URI - `123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/playwright-cloud-executer`
4. ✅ ECS Cluster 名 - `playwright-cloud-executer-cluster`
5. ✅ playwrightExecuterUser の権限確認 - 上記の必須ポリシーがアタッチされているか

その後、**フェーズ2（Docker イメージのビルド・プッシュ）** に進みます。
