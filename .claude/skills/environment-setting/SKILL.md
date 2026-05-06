---
name: environment-setting
description: Claudeに実装してもらうときに私が使っている環境を毎回指定している。例えば、Windows11端末を使っている。shellは使えないのでps1（PowerShell）を使うことなど。これを毎回指示するのではなくskillから読み取るためのプロトコル。
---

## 💻 Local Development Environment (Implicit Defaults)
Claudeは、ユーザーから明示的な指定がない限り、常に以下の環境を前提としてコード生成およびコマンド実行を行うこと。

### 1. OS & Shell
- **OS:** Windows 11 Home/Pro
- **Primary Shell:** PowerShell (pwsh)
- **Forbidden Commands:** `export`, `ls` (as alias for bash), `rm -rf` (Standard bash syntax)
- **Required Syntax:** 
  - 環境変数は `$Env:VAR_NAME = "value"`
  - ファイル操作は `Remove-Item`, `Copy-Item` 等のコマンドレット、またはPowerShell標準構文を使用

### 2. Path & Storage Context
- **Critical Note:** OneDrive同期下にあるため、ファイルロック（index.lock等）や同期遅延が発生しやすいことを考慮に入れ、操作に失敗した際は即座に `Force` オプションを検討せよ。

### 3. Node.js & Tooling
- **Manager:** npm (not yarn/pnpm)
- **Directory Structure:** `playwright-app/` がメインのソースディレクトリである。
