# agents-harnesses

AI コーディングエージェント（Claude Code / Codex）の生産性を高めるスキル・ループ・Hooks のコレクション。

## ディレクトリ構成

```
agents-harnesses/
├── claude-code/
│   ├── skills/          # slash commands (/review-loop 等)
│   ├── hooks/           # PreToolUse / PostToolUse hooks
│   └── scripts/         # 通知・MCP 等のユーティリティ
├── codex/
│   ├── skills/          # Codex 用スキル
│   └── hooks/           # Codex 用 hooks
└── loops/               # 決定論的ループランナー（エージェント非依存）
```

## Claude Code

### Skills (`claude-code/skills/`)

| スキル | 説明 | 呼び出し |
|--------|------|----------|
| **review-loop** | 4-5 並列レビュアーによる収束型コードレビューループ。ラウンドごとに指摘→修正→再レビューを繰り返し、新規指摘 0 件で収束 | `/review-loop` |
| **review-now** | 独立コンテキストでの単発コードレビュー。PR 前のクイックチェックに | `/review-now` |
| **claude-loop** | 決定論的 bash ループで Claude Code を繰り返し実行。converge（レビュー収束）と backlog（技術的負債バッチ処理）の 2 モード | `/claude-loop` |
| **task-decompose** | 大規模タスクを独立サブタスクに分解し、git worktree + サブエージェントで並列実行 | `/task-decompose` |
| **tdd** | テスト駆動開発をサブエージェントで実行。テスト設計→実装→Red-Green-Refactor サイクル | `/tdd` |
| **dig** | 曖昧な要件を構造化された質問で掘り下げ、意思決定を記録する | `/dig` |

### Hooks (`claude-code/hooks/`)

#### Guardrails（PreToolUse）

安全なエージェント運用のためのガードレール群。`GUARD_LEVEL` (L1〜L5) で厳しさを段階制御。

| Hook | 説明 |
|------|------|
| **gh-guard** | PR の自己 approve・保護ブランチへの直接マージをブロック |
| **commit-guard** | main/develop への直接コミット、`--no-verify`、force push を防止 |
| **secret-guard** | シークレットの平文出力（echo, printenv 等）をブロック |
| **heredoc-guard** | heredoc 構文をブロックし、コピペ事故を防止 |
| **pr-merge-ready-guard** | 未解決レビュースレッド・マージコンフリクトがある PR のマージを防止 |
| **toolchain-guard** | sudo npm/node をブロック、gh 認証チェック |
| **worktree-guard** | メインワークツリーでの直接編集を制限（worktree 分離を強制） |

#### Automation（PostToolUse）

| Hook | 説明 |
|------|------|
| **fix-crlf** | Write/Edit 後に CRLF → LF を自動変換 |
| **resolve-reminder** | git push 後に未解決レビュースレッドをリマインド |
| **subagent-rules/inject** | サブエージェント起動時にエージェント種別に応じたルールを注入 |

### Scripts (`claude-code/scripts/`)

| スクリプト | 説明 |
|-----------|------|
| **notify-discord.sh** | Discord 通知（Webhook / Bot Token 対応） |
| **hook-stop-notify.sh** | セッション終了時の自動 Discord 通知（Stop hook 用） |
| **launch-discord-mcp.sh** | Discord MCP サーバー起動 |

## Codex

（準備中 — hooks / skills を順次追加予定）

## Loop Runner (`loops/`)

`claude-loop.sh` はエージェントをラップする bash スクリプトで、ループ制御を AI ではなくシェルが担う。

```bash
# レビュー収束ループ（指摘 0 件まで繰り返す）
./loops/claude-loop.sh --mode converge --max-rounds 5

# 技術的負債バッチ処理（TODO/lint/tsc/GitHub Issues を順次処理）
./loops/claude-loop.sh --mode backlog --source auto+issues --label tech-debt
```

### 設計原則

- **決定論的制御**: ループ判定は bash が行い、AI の暴走を防止
- **コンテキスト分離**: 各ラウンドで新しいプロセスを起動し、前ラウンドのバイアスを排除
- **構造化出力**: JSON Lines で指摘事項を出力、`<loop-result>` タグでラウンド完了を通知
- **安全停止**: 収束条件達成 or 最大ラウンド数で停止、Ctrl+C で即座に中断可能

## セットアップ

```bash
git clone git@github.com:shuhei0866/agents-harnesses.git ~/agents-harnesses

# Claude Code スキルをシンボリックリンク
ln -s ~/agents-harnesses/claude-code/skills/*.md ~/.claude/commands/

# Hooks をシンボリックリンク
ln -s ~/agents-harnesses/claude-code/hooks/* ~/.claude/hooks/

# Scripts をシンボリックリンク
ln -s ~/agents-harnesses/claude-code/scripts/*.sh ~/.claude/scripts/
```

## ライセンス

MIT
