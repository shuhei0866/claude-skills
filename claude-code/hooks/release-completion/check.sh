#!/bin/bash
# release-completion/check.sh: Stop - develop 向け PR のマージ完了を検証 [L4]
#
# ブランチ別の検証:
#   release/* → 3ゲート（仕様書 warn / メモリ block / PRマージ block）
#   develop   → open PR の存在チェック（Draft PR は除外。WT から戻った場合をキャッチ）
#   fix/*/feat/* 等 → PR が develop にマージ済みか
#   main      → スキップ
#
# エスケープ条件:
#   - stop_hook_active が true（無限ループ防止、2回目は通過）
#   - コード変更がない場合（設計対話フェーズ）

set -uo pipefail

INPUT=$(cat)

# stop_hook_active チェック（無限ループ防止）
if command -v jq &>/dev/null; then
  STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
else
  exit 0
fi

if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# gh CLI の存在フラグ（PR 検証に必要だが、release/* の仕様書/メモリチェックは gh 不要）
HAS_GH=false
if command -v gh &>/dev/null; then
  HAS_GH=true
fi

# 現在のブランチを確認
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")

# main/master/unknown はスキップ
case "$BRANCH" in
  main|master|unknown)
    exit 0
    ;;
esac

# --- develop ブランチの場合: open PR をチェック ---
# エージェントが WT から戻った後、未マージ PR が残っているケースをキャッチ
if [ "$BRANCH" = "develop" ]; then
  if [ "$HAS_GH" = "true" ]; then
    OPEN_PRS=$(gh pr list --base develop --state open --author "@me" --json number,headRefName,title,isDraft -q '[.[] | select(.isDraft | not) | select(.title | startswith("design:") | not)] | .[] | "#\(.number) \(.headRefName): \(.title)"' 2>/dev/null || echo "")
    if [ -n "$OPEN_PRS" ]; then
      # JSON 安全のため改行を \\n に、引用符をエスケープ
      SAFE_PRS=$(echo "$OPEN_PRS" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' '|' | sed 's/|/\\n/g')
      cat << EOF
{
  "decision": "block",
  "reason": "[マージ完了ゲート] develop 向けの未マージ PR があります:\\n${SAFE_PRS}\\n\\nマージまで完了してから停止してください。"
}
EOF
    fi
  fi
  exit 0
fi

# --- PR マージ状態を判定する共通関数 ---
check_pr_merge_status() {
  local branch="$1"
  MERGED_PR_DATA=$(gh pr list --head "$branch" --base develop --state merged --json number,mergedAt -q '.[0]' 2>/dev/null || echo "")
  if [ -n "$MERGED_PR_DATA" ] && [ "$MERGED_PR_DATA" != "null" ]; then
    # マージ済み PR がある → マージ後の追加コミットをチェック
    MERGED_AT=$(echo "$MERGED_PR_DATA" | jq -r '.mergedAt // empty')
    if [ -n "$MERGED_AT" ]; then
      COMMITS_AFTER_MERGE=$(git log --after="$MERGED_AT" --oneline HEAD 2>/dev/null | head -1)
      if [ -n "$COMMITS_AFTER_MERGE" ]; then
        echo "pr_not_merged"  # マージ後に追加コミットあり
      else
        echo "merged"
      fi
    else
      echo "merged"
    fi
  else
    # マージ済み PR なし → open PR があるか確認
    OPEN_PR=$(gh pr list --head "$branch" --base develop --state open --json number -q '.[0].number' 2>/dev/null || echo "")
    if [ -n "$OPEN_PR" ] && [ "$OPEN_PR" != "null" ]; then
      echo "pr_not_merged"  # PR はあるが未マージ
    else
      echo "no_pr"  # PR 自体がない
    fi
  fi
}

# --- release/* ブランチの場合: フル検証（3ゲート） ---
if [[ "$BRANCH" == release/* ]]; then
  # コード変更がない場合はスキップ（設計対話フェーズ）
  CODE_CHANGES=$(git diff main --name-only 2>/dev/null | grep -v -E '^\.claude/' | head -1)
  if [ -z "$CODE_CHANGES" ]; then
    exit 0
  fi

  BLOCK_ISSUES=""
  WARN_ISSUES=""

  # ゲート 1: リリース仕様書の存在 → warn
  RELEASE_NAME="${BRANCH#release/}"
  SPEC_FILE=".claude/release-specs/${RELEASE_NAME}.md"
  if [ ! -f "$SPEC_FILE" ]; then
    WARN_ISSUES="${WARN_ISSUES}\n- リリース仕様書 (${SPEC_FILE}) が存在しません"
  fi

  # ゲート 2: エージェントメモリの未コミット変更 → block
  MEMORY_CHANGES=$(git diff --name-only 2>/dev/null | grep '^\.claude/agent-memory/' || true)
  MEMORY_STAGED=$(git diff --cached --name-only 2>/dev/null | grep '^\.claude/agent-memory/' || true)
  MEMORY_UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | grep '^\.claude/agent-memory/' || true)
  if [ -n "$MEMORY_CHANGES" ] || [ -n "$MEMORY_STAGED" ] || [ -n "$MEMORY_UNTRACKED" ]; then
    BLOCK_ISSUES="${BLOCK_ISSUES}\n- .claude/agent-memory/ に未コミットの変更があります。コミットに含めてください"
  fi

  # ゲート 3: PR マージ状態 → 条件付き（gh 必須）
  if [ "$HAS_GH" = "true" ]; then
    PR_STATUS=$(check_pr_merge_status "$BRANCH")
    case "$PR_STATUS" in
      "pr_not_merged")
        BLOCK_ISSUES="${BLOCK_ISSUES}\n- PR が develop にマージされていません。/ship-to-develop でマージまで完了してください"
        ;;
      "no_pr")
        WARN_ISSUES="${WARN_ISSUES}\n- PR がまだ作成されていません（作業途中であれば問題ありません）"
        ;;
    esac
  else
    WARN_ISSUES="${WARN_ISSUES}\n- gh CLI が利用できないため PR のマージ状態を確認できませんでした"
  fi

  # 結果出力
  if [ -n "$BLOCK_ISSUES" ]; then
    ALL_ISSUES="$BLOCK_ISSUES"
    if [ -n "$WARN_ISSUES" ]; then
      ALL_ISSUES="${ALL_ISSUES}\n\n[参考]${WARN_ISSUES}"
    fi
    cat << EOF
{
  "decision": "block",
  "reason": "[リリース完了ゲート] release/* ブランチでコード変更がありますが、以下が未完了です:${ALL_ISSUES}\n\nゴール: develop にマージするところまでやり切ること。"
}
EOF
  elif [ -n "$WARN_ISSUES" ]; then
    cat << EOF
{
  "decision": "block",
  "reason": "[リリース確認] 以下の点を確認してください（作業途中であればこのまま停止して構いません）:${WARN_ISSUES}"
}
EOF
  fi
  exit 0
fi

# --- その他のブランチ (fix/*, feat/* 等): PR マージ検証 ---
# コード変更がない場合はスキップ
CODE_CHANGES=$(git diff develop --name-only 2>/dev/null | grep -v -E '^\.claude/' | head -1)
if [ -z "$CODE_CHANGES" ]; then
  exit 0
fi

if [ "$HAS_GH" = "true" ]; then
  PR_STATUS=$(check_pr_merge_status "$BRANCH")
  case "$PR_STATUS" in
    "pr_not_merged")
      OPEN_PR_URL=$(gh pr list --head "$BRANCH" --base develop --state open --json url -q '.[0].url' 2>/dev/null || echo "")
      if [ -n "$OPEN_PR_URL" ]; then
        MSG="PR ($OPEN_PR_URL) が develop にマージされていません。マージまで完了してください"
      else
        MSG="PR が develop にマージされていません。マージまで完了してください"
      fi
      cat << EOF
{
  "decision": "block",
  "reason": "[マージ完了ゲート] ${BRANCH} ブランチでコード変更がありますが:\\n- ${MSG}\\n\\nゴール: develop にマージするところまでやり切ること。"
}
EOF
      ;;
    "no_pr")
      cat << EOF
{
  "decision": "block",
  "reason": "[マージ完了ゲート] ${BRANCH} ブランチでコード変更がありますが:\\n- PR がまだ作成されていません。PR を作成してマージまで完了してください\\n\\n作業途中であればこのまま停止して構いません。"
}
EOF
      ;;
  esac
fi
