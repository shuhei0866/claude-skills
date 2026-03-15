#!/bin/bash
# session-sync/daily-briefing.sh: SessionStart - 毎日最初のセッションでブリーフィングを促す
#
# ~/.cache/skynet-hub/last_briefing に最終実行日を記録。
# 今日まだ実行していなければ additionalContext でブリーフィング実行を促す。

set -uo pipefail

STAMP_FILE="$HOME/.cache/skynet-hub/last_briefing"
TODAY=$(date -u +%Y-%m-%d)

# 今日既にブリーフィング済みならスキップ
if [ -f "$STAMP_FILE" ]; then
  LAST=$(cat "$STAMP_FILE" 2>/dev/null || echo "")
  if [ "$LAST" = "$TODAY" ]; then
    exit 0
  fi
fi

# skynet-hub の briefing.py が存在するか確認
BRIEFING_SCRIPT="$HOME/Documents/my-skynet-hub/scripts/briefing.py"
if [ ! -f "$BRIEFING_SCRIPT" ]; then
  exit 0
fi

cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "[デイリーブリーフィング] 今日のブリーフィングがまだ実行されていません。\`python3 ~/Documents/my-skynet-hub/scripts/briefing.py --active-only\` を実行して、全リポジトリの Issues/PRs 状況を確認してください。"
  }
}
EOF
