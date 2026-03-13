#!/bin/bash
# review-enforcement/check.sh: Stop - release/* ブランチでのレビューステップ実行を検証
#
# release/* ブランチで作業が行われた場合、/release-ready と /review-now が
# 実行されたかを検証する。
#
# 判定ロジック:
#   1. ステートファイルで過去セッションのレビュー完了を確認
#   2. ステートファイルの SHA と現在 HEAD を比較（差分検出）
#   3. 今のセッションで Write/Edit が使われたか（読み取り専用判定）
#   4. transcript で今セッションのレビュー実行を確認
#
# 結果:
#   - レビュー済み + 差分なし → pass
#   - レビュー済み + 差分あり → warn（block ではない）
#   - 読み取り専用セッション → pass
#   - レビュー未実行 + 変更あり → block

set -uo pipefail

INPUT=$(cat)

# stop_hook_active チェック（無限ループ防止）
if command -v jq &>/dev/null; then
  STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
  TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
else
  exit 0
fi

if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# 現在のブランチを確認
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")

# release/* ブランチでない場合はスキップ
case "$BRANCH" in
  release/*)
    ;;
  *)
    exit 0
    ;;
esac

# 設計対話フェーズの判定: コードの変更がない場合はレビュー不要
CODE_CHANGES=$(git diff main --name-only 2>/dev/null | grep -v -E '^\.claude/' | head -1)
if [ -z "$CODE_CHANGES" ]; then
  exit 0
fi

# --- ステートファイルの読み取り ---
RELEASE_NAME="${BRANCH#release/}"
STATE_DIR=".claude/.hook-state/review/${RELEASE_NAME}"
STATE_RELEASE_READY="${STATE_DIR}/release-ready.done"
STATE_REVIEW_NOW="${STATE_DIR}/review-now.done"
STATE_SHA="${STATE_DIR}/last-reviewed-sha"

PREV_RELEASE_READY=false
PREV_REVIEW_NOW=false
PREV_SHA=""

if [ -f "$STATE_RELEASE_READY" ]; then
  PREV_RELEASE_READY=true
fi
if [ -f "$STATE_REVIEW_NOW" ]; then
  PREV_REVIEW_NOW=true
fi
if [ -f "$STATE_SHA" ]; then
  PREV_SHA=$(cat "$STATE_SHA" 2>/dev/null || echo "")
fi

CURRENT_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")

# --- transcript から今セッションのレビュー実行を確認 ---
HAS_RELEASE_READY=false
HAS_REVIEW_NOW=false

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  if grep -q "release-ready" "$TRANSCRIPT_PATH" 2>/dev/null; then
    HAS_RELEASE_READY=true
  fi
  if grep -q "review-now" "$TRANSCRIPT_PATH" 2>/dev/null; then
    HAS_REVIEW_NOW=true
  fi
fi

# --- ステートファイルの書き込み（今セッションでレビュー実行した場合） ---
if [ "$HAS_RELEASE_READY" = "true" ] || [ "$HAS_REVIEW_NOW" = "true" ]; then
  mkdir -p "$STATE_DIR"
  if [ "$HAS_RELEASE_READY" = "true" ]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE_RELEASE_READY"
  fi
  if [ "$HAS_REVIEW_NOW" = "true" ]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE_REVIEW_NOW"
  fi
  echo "$CURRENT_SHA" > "$STATE_SHA"
fi

# --- 判定: 過去 + 今セッションの合算 ---
REVIEWED_RELEASE_READY=false
REVIEWED_REVIEW_NOW=false

if [ "$HAS_RELEASE_READY" = "true" ] || [ "$PREV_RELEASE_READY" = "true" ]; then
  REVIEWED_RELEASE_READY=true
fi
if [ "$HAS_REVIEW_NOW" = "true" ] || [ "$PREV_REVIEW_NOW" = "true" ]; then
  REVIEWED_REVIEW_NOW=true
fi

# ケース 1: 両方レビュー済み
if [ "$REVIEWED_RELEASE_READY" = "true" ] && [ "$REVIEWED_REVIEW_NOW" = "true" ]; then
  # SHA が一致 → 完全 pass
  if [ "$PREV_SHA" = "$CURRENT_SHA" ] && [ -n "$PREV_SHA" ]; then
    exit 0
  fi
  # 今セッションでレビューした → pass（SHA は上で更新済み）
  if [ "$HAS_RELEASE_READY" = "true" ] || [ "$HAS_REVIEW_NOW" = "true" ]; then
    exit 0
  fi
  # 過去にレビュー済みだが HEAD が進んでいる → warn
  cat << EOF
{
  "decision": "block",
  "reason": "[レビュー確認] レビュー済みですが、レビュー後に新しいコミットがあります。差分が軽微であればこのまま停止して構いません。大きな変更がある場合は /review-now の再実行を検討してください。"
}
EOF
  exit 0
fi

# ケース 2: 読み取り専用セッション判定
# transcript で Write/Edit ツールが使われていなければ、読み取り専用と見なす
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  HAS_WRITE_EDIT=$(jq -r '
    [
      (try .message.content[] catch empty),
      (try .data.message.message.content[] catch empty)
    ][] |
    select(type == "object") |
    select(.type == "tool_use") |
    .name // empty
  ' "$TRANSCRIPT_PATH" 2>/dev/null | grep -cE '^(Write|Edit)$' || echo "0")

  if [ "$HAS_WRITE_EDIT" = "0" ]; then
    # Write/Edit なし → 読み取り専用セッション → pass
    exit 0
  fi
fi

# ケース 3: レビュー未実行 + 変更あり → block
MISSING=""
if [ "$REVIEWED_RELEASE_READY" = "false" ]; then
  MISSING="/release-ready"
fi
if [ "$REVIEWED_REVIEW_NOW" = "false" ]; then
  if [ -n "$MISSING" ]; then
    MISSING="$MISSING, /review-now"
  else
    MISSING="/review-now"
  fi
fi

if [ -n "$MISSING" ]; then
  cat << EOF
{
  "decision": "block",
  "reason": "[レビュー強制] release/* ブランチでコード変更がありますが、以下のレビューステップが未実行です: ${MISSING}。PR 作成前に実行してください。"
}
EOF
else
  exit 0
fi
