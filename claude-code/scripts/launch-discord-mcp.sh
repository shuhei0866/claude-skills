#!/bin/bash
# Discord MCP サーバー起動スクリプト
# ~/.claude/.env に未設定なら macOS Keychain から補完する

if [ -f ~/.claude/.env ]; then
  source ~/.claude/.env
fi

if [ -z "${DISCORD_TOKEN:-}" ]; then
  if command -v security >/dev/null 2>&1; then
    DISCORD_TOKEN="$(security find-generic-password -a "claude-agent" -s "claude-agent/DISCORD_TOKEN" -w 2>/dev/null || true)"
  fi
fi

if [ -z "${DISCORD_TOKEN:-}" ]; then
  echo "Error: DISCORD_TOKEN is not set in ~/.claude/.env and not found in macOS Keychain" >&2
  exit 1
fi

export DISCORD_TOKEN
exec npx -y mcp-discord
