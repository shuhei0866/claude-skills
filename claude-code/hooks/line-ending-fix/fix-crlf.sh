#!/bin/bash
# line-ending-fix/fix-crlf.sh: PostToolUse (Write|Edit) - CRLF 改行を自動修正
#
# Write/Edit 後にファイルの改行コードをチェックし、CRLF が検出された場合は
# LF に自動変換する。バイナリファイルはスキップ。

set -uo pipefail

INPUT=$(cat)

# file_path を取得
if command -v jq &>/dev/null; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
else
  exit 0
fi

if [ -z "${FILE_PATH:-}" ]; then
  exit 0
fi

# ファイルが存在しない場合はスキップ
if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# バイナリファイルはスキップ (file コマンドで判定)
if file "$FILE_PATH" | grep -qE 'binary|executable|image|archive|compressed'; then
  exit 0
fi

# CRLF チェック & 修正 — grep -cP で直接 \r を検出（file コマンドより確実）
if grep -qP '\r$' "$FILE_PATH" 2>/dev/null; then
  sed -i 's/\r$//' "$FILE_PATH"
  echo "[CRLF 修正] ${FILE_PATH} の改行を LF に変換しました" >&2
fi

exit 0
