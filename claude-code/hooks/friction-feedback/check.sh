#!/bin/bash
# friction-feedback/check.sh: Stop - セッション中の摩擦を検出し Issue 作成を促す [L3→L4]
#
# transcript から実際のフック拒否（deny/block）イベントを検出し、
# 構造的な改善が必要かどうかを AI に問いかける。
# AI は一時的な問題か構造的な問題かを判断し、
# 構造的な問題には GitHub Issue を作成する。
#
# 検出方法:
#   jq で JSONL をパースし、tool_result の content が [ガードラベル] で始まるものを抽出。
#   ソースコード読み取り（Read ツール）の内容は行番号やシェバンで始まるため除外される。(#693)
#
# 検出対象:
#   - PreToolUse の deny（[XXXガード] パターン）
#   - Stop の block（[XXX強制], [XXXゲート], [XXX確認] パターン）
#     ※ Stop block は同一フック由来の重複を除去してカウント
#
# エスケープ条件:
#   - stop_hook_active が true（無限ループ防止）
#   - transcript が存在しない場合
#   - 拒否イベントが検出されなかった場合

set -uo pipefail

INPUT=$(cat)

if command -v jq &>/dev/null; then
  STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
  TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
else
  exit 0
fi

if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# transcript が存在しない場合はスキップ
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  exit 0
fi

# --- PreToolUse の deny を検出（全件カウント） ---
PRETOOL_LABELS='\[(コミット衛生ガード|ワークツリーガード|ブランチ戦略ガード|マイグレーション番号ガード|マイグレーションガード|Discord メンションガード)\]'

PRETOOL_DENIALS=$(jq -r '
  [
    (try .message.content[] catch empty),
    (try .data.message.message.content[] catch empty)
  ][] |
  select(type == "object" and .type == "tool_result") |
  .content // empty |
  select(startswith("["))
' "$TRANSCRIPT_PATH" 2>/dev/null | grep -oE "^${PRETOOL_LABELS}.*" | sort -u || true)

# --- Stop の block を検出（同一フック由来は重複除去） ---
STOP_LABELS='\[(レビュー強制|リリース完了ゲート|レビュー確認|リリース確認)\]'

STOP_BLOCKS=$(jq -r '
  [
    (try .message.content[] catch empty),
    (try .data.message.message.content[] catch empty)
  ][] |
  select(type == "object" and .type == "tool_result") |
  .content // empty |
  select(startswith("["))
' "$TRANSCRIPT_PATH" 2>/dev/null | grep -oE "^${STOP_LABELS}" | sort -u || true)
# ↑ sort -u でラベル単位の重複除去（同じフックの複数回 block → 1件に集約）

# 合算
ALL_DENIALS=""
if [ -n "$PRETOOL_DENIALS" ]; then
  ALL_DENIALS="$PRETOOL_DENIALS"
fi
if [ -n "$STOP_BLOCKS" ]; then
  if [ -n "$ALL_DENIALS" ]; then
    ALL_DENIALS="${ALL_DENIALS}
${STOP_BLOCKS}"
  else
    ALL_DENIALS="$STOP_BLOCKS"
  fi
fi

if [ -z "$ALL_DENIALS" ]; then
  exit 0
fi

# 拒否件数をカウント
DENIAL_COUNT=$(echo "$ALL_DENIALS" | wc -l | tr -d ' ')

# 表示用にフォーマット
DENIAL_LIST=""
while IFS= read -r line; do
  DENIAL_LIST="${DENIAL_LIST}\n  - ${line}"
done <<< "$ALL_DENIALS"

cat << EOF
{
  "decision": "block",
  "reason": "[摩擦フィードバック] このセッションで ${DENIAL_COUNT} 件のフック拒否が発生しました:${DENIAL_LIST}\n\n構造的な改善が必要な項目があれば \`gh issue create\` で Issue を作成してください。\n一時的な問題（正当なブロック、操作ミス等）であればそのまま停止して構いません。"
}
EOF
