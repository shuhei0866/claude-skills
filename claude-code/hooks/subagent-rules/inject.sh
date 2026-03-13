#!/bin/bash
# subagent-rules/inject.sh: SubagentStart - 全サブエージェントに必須ルールを注入
#
# agent_type に応じて適切なルールセットを additionalContext として注入する。
# これにより CLAUDE.md を読み忘れても必須ルールがコンテキストに存在する。
#
# vdd.config はオプショナル: プロジェクトローカルにあれば読み込み、なければデフォルト値を使用。

set -uo pipefail

INPUT=$(cat)

# vdd.config の探索（オプショナル）
# 探索順: $CLAUDE_PROJECT_DIR/.claude/vdd.config → プロジェクトルート/.claude/vdd.config
VDD_CONFIG_LOADED=false
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/.claude/vdd.config" ]; then
  source "$CLAUDE_PROJECT_DIR/.claude/vdd.config" 2>/dev/null && VDD_CONFIG_LOADED=true
else
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  if [ -n "$PROJECT_ROOT" ] && [ -f "$PROJECT_ROOT/.claude/vdd.config" ]; then
    source "$PROJECT_ROOT/.claude/vdd.config" 2>/dev/null && VDD_CONFIG_LOADED=true
  fi
fi

# デフォルト値（vdd.config が見つからない場合は空文字列）
CHECK_CMD="${CHECK_COMMAND:-}"
TEST_CMD="${TEST_COMMAND:-}"
INTEGRATION="${INTEGRATION_BRANCH:-develop}"

# agent_type を取得
if command -v jq &>/dev/null; then
  AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty')
else
  exit 0
fi

# 現在のブランチを取得
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")

# ベースルール（全エージェント共通）
BASE_RULES="[必須ルール - SubagentStart フックにより自動注入]
- メインワークツリー（リポジトリルート）でのファイル編集は禁止。ワークツリー内で作業すること
- .claude/ 配下、CLAUDE.md への書き込みは例外的に許可
- git push は禁止。コミットまでは可能"

# agent_type に応じたルール出し分け
case "$AGENT_TYPE" in
  implementer|general-purpose)
    RULES="$BASE_RULES
- TDD 必須: 実装コードより先にテストを書くこと"
    # TEST_CMD / CHECK_CMD が設定されている場合のみ注入
    if [ -n "$TEST_CMD" ]; then
      RULES="$RULES
- テスト実行: ${TEST_CMD}"
    fi
    if [ -n "$CHECK_CMD" ]; then
      RULES="$RULES
- ${CHECK_CMD}（型チェック + lint + テスト）を実装完了後に必ず実行"
    fi
    # release/* ブランチの場合はゴール宣言 + ガードレールを注入
    case "$BRANCH" in
      release/*)
        RULES="$RULES

[release ブランチのゴール]
あなたのゴールは「${INTEGRATION} にマージするところまでやり切ること」です。
手段は自分で選んでください。Stop フック（出口ゲート）が完了条件を検証します:
- リリース仕様書がコミットされていること
- レビューが実行されていること
- PR が ${INTEGRATION} にマージされていること

ガードレール:
- リリース仕様書のスコープ外の変更をしないこと"
        ;;
    esac
    ;;
  code-reviewer)
    RULES="$BASE_RULES
- レビュー観点: セキュリティ、パフォーマンス、エラーハンドリング、型安全性
- リリース仕様書があればスコープ逸脱がないか確認"
    ;;
  Explore|Plan)
    RULES="$BASE_RULES
- このエージェントは読み取り専用。ファイルの編集・作成は行わない
- 調査結果を正確に報告すること"
    ;;
  *)
    RULES="$BASE_RULES"
    ;;
esac

# JSON 出力用にエスケープ
ESCAPED_RULES=$(echo "$RULES" | jq -Rs '.')

cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStart",
    "additionalContext": $ESCAPED_RULES
  }
}
EOF
