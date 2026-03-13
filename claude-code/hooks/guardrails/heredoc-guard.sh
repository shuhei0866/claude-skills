#!/bin/bash
# heredoc-guard: PreToolUse (Bash) - heredoc 構文をブロック
#
# ユーザーがコピペする際に heredoc が正しく動作しないケースがあるため、
# echo '...' | sudo tee や printf を使うよう強制する。

set -uo pipefail

GUARD_COMMON="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/_guard-common.sh"
source "$GUARD_COMMON"

INPUT=$(cat)

if command -v jq &>/dev/null; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
else
  exit 0
fi

if [ -z "${COMMAND:-}" ]; then
  exit 0
fi

# heredoc パターン検出: <<EOF, <<'EOF', <<"EOF", << 'CONF', <<-EOF など
if echo "$COMMAND" | grep -qE '<<-?\s*'\''?\"?[A-Za-z_]+'\''?\"?\s*$'; then
  guard_respond "advisory" "heredoc ガード" "heredoc (<<EOF) 構文はコピペ時に問題が発生するためブロックされています。代わりに echo '...' | sudo tee /path/to/file または printf を使用してください。"
fi

exit 0
