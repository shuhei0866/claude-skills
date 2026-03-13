---
name: vercel-debug
description: Vercel CLIを使って本番環境のログ取得、デプロイ状況確認、エラーデバッグを行うスキル。ユーザーが「本番のログを見て」「デプロイ状況を確認して」「本番でエラーが出ている」「Vercelのログを取って」「ビルドが失敗した」「本番環境をデバッグして」「デプロイを調べて」「ランタイムエラー」「本番障害」と言った場合や、Vercel・デプロイ・本番ログ・ビルドエラーに関わる調査で自動的に使用すること。
context: fork
agent: debugger
---

# Vercel デバッグスキル

このスキルはプロジェクトの本番環境（Vercel）のログ取得・エラー調査・デプロイ状況確認を行います。

## 使用タイミング

- 本番環境でエラーが発生しているとき
- デプロイの状態やビルドログを確認したいとき
- ランタイムログをリアルタイムで確認したいとき
- デプロイの詳細情報（ドメイン、リージョン、ステータス等）を調べたいとき

## 前提条件

- Vercel CLI がインストール済み（`npm i -g vercel`）
- `vercel login` で認証済みであること
- プロジェクトがリンク済みであること（未リンクの場合は `vercel link` を実行）

## プロジェクト情報

- **プロジェクト名**: <your-vercel-project>（Vercel 上の名前を確認すること）
- **フレームワーク**: Next.js (App Router)
- **プロジェクトルート**: `apps/web/`

## コマンドリファレンス

### 1. デプロイ一覧の確認

```bash
# 最新のデプロイ一覧
vercel ls --cwd apps/web

# 本番環境のデプロイのみ
vercel ls --cwd apps/web --environment production

# エラー状態のデプロイを確認
vercel ls --cwd apps/web --status ERROR

# JSON 形式で取得（パースしやすい）
vercel ls --cwd apps/web --format json
```

### 2. デプロイの詳細確認

```bash
# デプロイの詳細情報
vercel inspect <DEPLOYMENT_URL_OR_ID> --cwd apps/web

# JSON 形式で詳細取得
vercel inspect <DEPLOYMENT_URL_OR_ID> --cwd apps/web --format json

# ビルドログの確認
vercel inspect <DEPLOYMENT_URL_OR_ID> --cwd apps/web --logs

# デプロイ完了まで待機（タイムアウト付き）
vercel inspect <DEPLOYMENT_URL_OR_ID> --cwd apps/web --wait --timeout 120s
```

### 3. ランタイムログの確認

```bash
# リアルタイムログ（最大5分間ストリーミング）
vercel logs <DEPLOYMENT_URL> --cwd apps/web

# JSON 形式で取得（フィルタリング可能）
vercel logs <DEPLOYMENT_URL> --cwd apps/web --format json

# エラーログのみフィルタ（jq 使用）
vercel logs <DEPLOYMENT_URL> --cwd apps/web --format json | jq 'select(.level == "error")'

# 警告以上をフィルタ
vercel logs <DEPLOYMENT_URL> --cwd apps/web --format json | jq 'select(.level == "error" or .level == "warning")'
```

### 4. 環境変数の確認

```bash
# 環境変数一覧
vercel env ls --cwd apps/web

# 特定環境の変数
vercel env ls production --cwd apps/web
```

### 5. デプロイの巻き戻し

```bash
# 前のデプロイにロールバック
vercel rollback <DEPLOYMENT_URL_OR_ID> --cwd apps/web
```

## デバッグワークフロー

### 本番エラーの調査手順

1. **デプロイ状況を確認**
   ```bash
   vercel ls --cwd apps/web --environment production --format json
   ```

2. **最新デプロイの詳細を確認**
   ```bash
   vercel inspect <DEPLOYMENT_URL> --cwd apps/web --format json
   ```

3. **ビルドエラーの場合 → ビルドログを確認**
   ```bash
   vercel inspect <DEPLOYMENT_URL> --cwd apps/web --logs
   ```

4. **ランタイムエラーの場合 → ランタイムログを確認**
   ```bash
   vercel logs <DEPLOYMENT_URL> --cwd apps/web --format json | jq 'select(.level == "error")'
   ```

5. **エラー内容を分析し、原因を特定**

### ビルド失敗の調査手順

1. **エラー状態のデプロイを特定**
   ```bash
   vercel ls --cwd apps/web --status ERROR
   ```

2. **ビルドログを確認**
   ```bash
   vercel inspect <DEPLOYMENT_URL> --cwd apps/web --logs
   ```

3. **ローカルでビルドを再現**
   ```bash
   pnpm build
   ```

## 注意事項

- `vercel logs` はリアルタイムストリーミングで最大5分間。長時間のログ収集には向かない
- `--cwd apps/web` を指定してプロジェクトのリンク情報を正しく参照すること
- 認証トークンが切れている場合は `vercel login` を再実行
- ログにはユーザーの個人情報が含まれる可能性があるため、共有時は注意すること
- ロールバックは慎重に。本番に影響するため、必ずユーザーの確認を取ること
