---
name: git-lock-issue-resolution
description: Windows 11 + OneDrive環境特有の `index.lock` 問題が発生した際、推論トークンを節約し最短で解決するためのプロトコル。また、lock以外にもgithubで何らかの問題が発生した場合にトークンを節約するため無駄な処理は行わずにユーザーに操作を依頼するためのプロトコル。
---

# Project Skill: Fast-Track Git & Environment Resolution

## 🚨 Git Lockfile Conflict (High Priority)
Windows 11 + OneDrive環境特有の `index.lock` 問題が発生した際、推論トークンを節約し最短で解決するためのプロトコル。

### 1. Error Detection
以下のアクション中に "index.lock" または "Permission denied" エラーを検知した場合：
- `git checkout` / `git switch`
- `git commit`
- `git merge` / `git pull`

上記以外で問題を検知した場合、tokenの消費を節約するためユーザーに直接操作を指示して、切り上げてください。

### 2. Mandatory Immediate Action
原因分析や「数秒待つ」という提案をスキップし、直ちに以下のコマンドを強制実行せよ。
```powershell
Remove-Item -Path .git/index.lock -Force -ErrorAction SilentlyContinue
```

### 3. Mandatory Immediate Action
それでも解決しない場合、tokenの消費を節約するためユーザーに直接操作を指示して、切り上げてください。