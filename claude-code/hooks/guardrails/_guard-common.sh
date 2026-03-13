#!/bin/bash
# _guard-common.sh: 全ガードスクリプト共通ライブラリ
#
# GUARD_LEVEL に基づいて deny / warn を制御する。
# - critical: GUARD_LEVEL に関係なく常に deny
# - advisory: GUARD_LEVEL=deny → deny, GUARD_LEVEL=warn → allow + additionalContext
#
# 使い方:
#   source "$GUARD_COMMON"
#   guard_respond "advisory" "heredoc" "heredoc は使わないでください"

# --- GUARD_LEVEL のロード ---
# 優先順位: 環境変数 GUARD_LEVEL > vdd.config > デフォルト (warn)
_load_guard_level() {
  # 既に環境変数で設定済みならそれを使う
  if [ -n "${GUARD_LEVEL:-}" ]; then
    return
  fi

  # vdd.config から読み込み（inject.sh と同じ探索順序）
  local config_file=""
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/.claude/vdd.config" ]; then
    config_file="$CLAUDE_PROJECT_DIR/.claude/vdd.config"
  else
    local project_root
    project_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
    if [ -n "$project_root" ] && [ -f "$project_root/.claude/vdd.config" ]; then
      config_file="$project_root/.claude/vdd.config"
    fi
  fi

  if [ -n "$config_file" ]; then
    # GUARD_LEVEL のみ抽出（source すると副作用が出る可能性があるため grep で取得）
    local level
    level=$(grep -E '^GUARD_LEVEL=' "$config_file" 2>/dev/null | tail -1 | cut -d= -f2 | tr -d '"'"'" | tr -d '[:space:]')
    if [ -n "$level" ]; then
      GUARD_LEVEL="$level"
      return
    fi
  fi

  # デフォルト
  GUARD_LEVEL="warn"
}

# --- レスポンス出力 ---
# guard_respond severity tag message
#   severity: "critical" | "advisory"
#   tag: ガード名（ログ用）
#   message: deny 理由メッセージ
guard_respond() {
  local severity="$1"
  local tag="$2"
  local message="$3"

  if [ "$severity" = "critical" ]; then
    # critical は常に deny
    cat << DENY
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "[${tag}] ${message}"
  }
}
DENY
    exit 0
  fi

  # advisory: GUARD_LEVEL に従う
  if [ "${GUARD_LEVEL:-warn}" = "deny" ]; then
    cat << DENY
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "[${tag}] ${message}"
  }
}
DENY
    exit 0
  fi

  # warn: 警告のみ（実行は許可）
  cat << WARN
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "additionalContext": "[${tag}] WARNING: ${message}"
  }
}
WARN
  exit 0
}

# 初期化: source された時点で GUARD_LEVEL をロード
_load_guard_level
