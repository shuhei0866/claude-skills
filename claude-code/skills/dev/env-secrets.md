---
name: env-secrets
description: 環境変数の参照、.env ファイルの操作、シークレットキーの調査、API キーの確認が必要な時に使用する。安全な取り扱い方法を提供し、漏洩を防止する。
---

# 環境変数・シークレット管理スキル

このスキルはプロジェクトで環境変数やシークレットを安全に扱う方法を提供します。

## 最重要ルール: AI によるシークレット漏洩の防止

### .env.local の直接読み取り禁止

**AI（Claude Code）は `.env.local` ファイルの内容を絶対に読んではならない。**

- `Read` ツールで `.env.local` を開かない
- `cat`, `head`, `tail` で `.env.local` を表示しない
- `grep` で `.env.local` の内容を出力しない
- `.env.local` の内容がセッションログに記録され、平文シークレットが永続化するため

`settings.local.json` の `permissions.deny` で技術的にブロックされているが、ルールとしても明示する。

### シークレットを含むコマンド出力の禁止

- API キーや service role key を含む行を出力するコマンドを実行しない
- `git grep` や `grep` の出力にシークレットが含まれる場合、その出力はセッションログに記録される
- `allow` エントリに平文シークレットを含むコマンドを許可しない

## シークレット漏洩調査の安全な方法

シークレットが漏洩していないか調査する際は、**マッチした行の内容を出力しない**ことが絶対条件。

### OK パターン（安全）

```bash
# ファイル名のみ出力（-l）
grep -rl 'sb_secret_' /path/to/search/

# カウントのみ出力（-c）
grep -rc 'sk-ant-api03-' /path/to/search/ | grep -v ':0$'

# git 内のファイル名のみ（--name-only）
git log --all -S 'sb_secret_' --name-only --oneline

# git grep でファイル名のみ
git grep -l 'sb_secret_' --all
```

### NG パターン（危険）

```bash
# NG: マッチ行が出力され、シークレット全体がセッションログに記録される
grep -r 'sb_secret_' /path/to/search/
git grep 'sb_secret_' --all

# NG: .env.local の内容を表示
grep 'SUPABASE' apps/web/.env.local
cat apps/web/.env.local
```

### サービス別シークレットプレフィックス

調査時はこれらのプレフィックスで検索する（値の全体を検索に使わない）：

| サービス | プレフィックス | 例 |
|---------|--------------|---|
| Supabase service role | `sb_secret_` | `sb_secret_xxx...` |
| Supabase publishable | `sb_publishable_` | `sb_publishable_xxx...` |
| Supabase JWT | `eyJ` | `eyJhbGc...` |
| Anthropic API | `sk-ant-api03-` | `sk-ant-api03-xxx...` |
| OpenAI API | `sk-proj-` | `sk-proj-xxx...` |
| Resend API | `re_` | `re_xxx...` |
| Vercel OIDC | `eyJhbG` (JWT) | `eyJhbGciOi...` |

## 使用タイミング

- リモート DB に接続するとき
- パスワードや API キーを使うコマンドを実行するとき
- 環境変数を読み込んでスクリプトを実行するとき
- **シークレットの漏洩調査を行うとき**
- **`.env.local` に関わる操作全般**

## 環境変数ファイルの場所

```text
<your-project>/
├── .env.local                   # DB パスワード等（共通設定）
└── apps/web/.env.local          # Web アプリ用（API キー等）
```

### .env.local（ルート）の内容

```bash
# Supabase DB パスワード（リモートDB接続用）
SUPABASE_DB_PASSWORD=xxxxxx
```

## 安全な環境変数の読み込み方法

### パターン1: source で読み込んで使用（推奨）

```bash
# .env.local を読み込んで環境変数として使用
source /path/to/project/.env.local
PGPASSWORD="$SUPABASE_DB_PASSWORD" psql "postgresql://postgres@db.xxx.supabase.co:5432/postgres" -c "SELECT 1;"
```

**メリット**: コマンド履歴にパスワードが残らない

### パターン2: サブシェルで読み込み

```bash
# 1行で完結させる場合
(source /path/to/project/.env.local && PGPASSWORD="$SUPABASE_DB_PASSWORD" psql "...")
```

### パターン3: grep + cut で抽出

```bash
# 特定の変数だけ取り出す場合
PGPASSWORD="$(grep SUPABASE_DB_PASSWORD /path/to/.env.local | cut -d= -f2)" psql "..."
```

## リモート DB 接続パターン

### プロジェクト固有の接続情報

- **Project Ref**: `<your-project-ref>`
- **Region**: `<your-region>`
- **接続先**: `db.<your-project-ref>.supabase.co:5432`

### 安全な接続コマンド

```bash
# 環境変数を読み込んでから接続
source .env.local
PGPASSWORD="$SUPABASE_DB_PASSWORD" psql "postgresql://postgres@db.<your-project-ref>.supabase.co:5432/postgres"
```

### クエリ実行例

```bash
source .env.local
PGPASSWORD="$SUPABASE_DB_PASSWORD" psql "postgresql://postgres@db.<your-project-ref>.supabase.co:5432/postgres" -c "
    SELECT email, is_admin FROM users WHERE is_admin = true;
"
```

## NG パターン（やってはいけない）

```bash
# NG: パスワードがコマンド履歴に残る
psql "postgresql://postgres:PASSWORD@db.xxx.supabase.co:5432/postgres"

# NG: パスワードを直接指定
PGPASSWORD='actualpassword' psql ...

# NG: 接続文字列にパスワードを含める
psql "postgresql://postgres:actualpassword@..."

# NG: .env.local を Read ツールで読む
# Read(apps/web/.env.local) ← 禁止

# NG: grep で .env.local の内容を表示
grep 'SECRET' apps/web/.env.local
```

## 多層防御の構成

シークレット保護は以下の3層で実現する：

1. **permissions.deny（決定論的・最も確実）**: `settings.local.json` で `.env.local` の Read をブロック
2. **スキルのルール（AI の行動指針）**: このスキルで定義された禁止事項・安全パターン
3. **コマンドパターン（運用ルール）**: `source` + 変数参照による間接アクセス

### permissions.deny の設定例

`settings.local.json` に以下を追加する。**Read ツールは絶対パスを受け取るため、`//` プレフィックスの絶対パスパターンが最も確実に動作する。**

```json
{
  "permissions": {
    "deny": [
      "Read(//Users/**/.env.local)",
      "Read(//Users/**/.env)",
      "Read(//Users/**/.env.*)",
      "Bash(cat *.env.local*)",
      "Bash(cat */.env.local*)",
      "Bash(grep *.env.local*)",
      "Bash(grep */.env.local*)",
      "Bash(head *.env.local*)",
      "Bash(tail *.env.local*)",
      "Bash(source *.env.local*)",
      "Bash(source */.env.local*)"
    ]
  }
}
```

### パターン構文の注意点

| 構文 | 意味 | 備考 |
|------|------|------|
| `//path` | ファイルシステムの絶対パス | **Read で最も確実** |
| `~/path` | ホームディレクトリからの相対パス | |
| `./path` | 設定ファイルからの相対パス | |
| `**` | 任意の深さのディレクトリ | |
| `*` | 単一ディレクトリ内のワイルドカード | |

## GitHub シークレット漏洩調査の安全な方法

**シークレットが git リポジトリに誤ってコミットされた場合の調査方法です。**

### ❌ 危険なパターン

```bash
# 危険: 出力にシークレット値全体が含まれる
git grep "sb_secret_"
git grep "sk-ant-api"

# 危険: サブエージェント出力がセッションログに記録される
# → 修復不可能な漏洩になる
```

### ✅ 安全な調査方法

#### 方法1: ファイル名のみを取得

```bash
# ファイル名のみ出力（値は含まれない）
git grep -l "sb_secret_"
git grep -l "sk-ant-api03-"
```

**用途**: どのファイルにシークレットが含まれているかを特定

#### 方法2: マッチ数のみを取得

```bash
# マッチ数を数える（値は含まれない）
git grep -c "sb_secret_"
git grep -c "sk-ant-api03-"
```

**用途**: シークレットが何行含まれているかを確認

#### 方法3: ローカルで確認してから削除

```bash
# ローカルでファイルを確認（git には残さない）
git log --oneline --all -- "*" | head -20  # 最近のコミットを確認

# git filter-branch や git-filter-repo で削除（要リポジトリ再構築）
git filter-repo --invert-paths --path <file-with-secret>
```

### 調査時の重要な注意事項

1. **絶対に検索結果の内容を出力しない**
   - `-l` (ファイル名のみ) または `-c` (カウントのみ) を使用

2. **サブエージェントに調査させない**
   - サブエージェント出力はセッションログに記録される
   - ローカルで調査を完了させてから、結果の概要だけを報告

3. **検索パターンは部分文字列に留める**
   - `sb_secret_` の完全な値を検索パターンに含めない

4. **漏洩が確認された場合**
   - ステップ1: Supabase Dashboard でシークレットをローテーション（最優先）
   - ステップ2: 問題のあるコミットを git から削除
   - ステップ3: 安全な状態を確認してから、修正内容を PR に含める

## シェルヘルパー関数（オプション）

`.bashrc` や `.zshrc` に追加すると便利：

```bash
# プロジェクト用のリモート DB 接続
project-db() {
  local project_root="${PROJECT_ROOT:-$HOME/<your-project>}"
  source "$project_root/.env.local"
  PGPASSWORD="$SUPABASE_DB_PASSWORD" psql \
    "postgresql://postgres@db.<your-project-ref>.supabase.co:5432/postgres" \
    "$@"
}

# 使用例: project-db -c "SELECT * FROM users LIMIT 5;"
```

## Claude Code での使用

Claude Code でリモート DB にクエリを実行する際は、必ずこのパターンを使用：

```bash
# Step 1: 環境変数を読み込み
source $HOME/<your-project>/.env.local

# Step 2: 環境変数を使って接続
PGPASSWORD="$SUPABASE_DB_PASSWORD" psql "postgresql://postgres@db.<your-project-ref>.supabase.co:5432/postgres" -c "..."
```

## チェックリスト

環境変数を使うコマンドを実行する前に確認：

- [ ] `.env.local` を Read ツールで直接読もうとしていないか
- [ ] パスワードや API キーを直接コマンドに書いていないか
- [ ] `source` で .env.local を読み込んでいるか
- [ ] 変数参照（`$VARIABLE`）を使っているか
- [ ] 接続文字列にパスワードを含めていないか
- [ ] シークレット調査で `-l`（ファイル名のみ）や `-c`（カウントのみ）を使っているか

シークレット調査時に確認：

- [ ] `git grep -l` または `git grep -c` を使い、出力は値を含まないか
- [ ] サブエージェントに調査させていないか
- [ ] 検索パターンが部分文字列に留まっているか
- [ ] 漏洩が確認されたら、ローテーション優先で実施しているか
