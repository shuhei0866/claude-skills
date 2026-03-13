#!/usr/bin/env bash
# Tests for claude-loop.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOOP_SH="$SCRIPT_DIR/../claude-loop.sh"

PASS=0
FAIL=0
TMPDIR_TEST="$(mktemp -d)"

cleanup() {
  rm -rf "$TMPDIR_TEST"
}
trap cleanup EXIT

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected: '$expected'"
    echo "    actual:   '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected to contain: '$needle'"
    echo "    actual: '$haystack'"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected NOT to contain: '$needle'"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit_code() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected exit $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

# --- Test: --help shows usage ---
test_help() {
  echo "test_help:"
  local output
  output="$("$LOOP_SH" --help 2>&1)" || true
  assert_contains "shows usage" "Usage:" "$output"
  assert_contains "shows modes" "converge" "$output"
  assert_contains "shows backlog mode" "backlog" "$output"
}

# --- Test: missing mode shows error ---
test_missing_mode() {
  echo "test_missing_mode:"
  local output exit_code=0
  output="$("$LOOP_SH" 2>&1)" || exit_code=$?
  assert_eq "exits with error" "1" "$exit_code"
  assert_contains "shows error message" "mode" "$output"
}

# --- Test: invalid mode shows error ---
test_invalid_mode() {
  echo "test_invalid_mode:"
  local output exit_code=0
  output="$("$LOOP_SH" --mode=invalid 2>&1)" || exit_code=$?
  assert_eq "exits with error" "1" "$exit_code"
  assert_contains "shows error" "invalid" "$output"
}

# --- Test: --dry-run converge mode ---
test_dry_run_converge() {
  echo "test_dry_run_converge:"
  local proj="$TMPDIR_TEST/dry-converge"
  mkdir -p "$proj"

  local output
  output="$("$LOOP_SH" --mode=converge --project="$proj" --max-rounds=3 --dry-run 2>&1)"

  assert_contains "shows mode" "Mode: converge" "$output"
  assert_contains "shows max rounds" "Max rounds: 3" "$output"
  assert_contains "shows project" "$proj" "$output"
  assert_not_contains "does not call claude" "claude -p" "$output"
  assert_contains "shows dry-run indicator" "DRY RUN" "$output"
}

# --- Test: --dry-run backlog mode ---
test_dry_run_backlog() {
  echo "test_dry_run_backlog:"
  local proj="$TMPDIR_TEST/dry-backlog"
  mkdir -p "$proj/src"
  echo "// TODO: fix this" > "$proj/src/test.ts"

  local output
  output="$("$LOOP_SH" --mode=backlog --project="$proj" --source=auto --max-rounds=2 --dry-run 2>&1)"

  assert_contains "shows mode" "Mode: backlog" "$output"
  assert_contains "shows backlog items" "Backlog items:" "$output"
  assert_contains "shows dry-run indicator" "DRY RUN" "$output"
}

# --- Test: custom prompt file ---
test_custom_prompt() {
  echo "test_custom_prompt:"
  local proj="$TMPDIR_TEST/custom-prompt"
  mkdir -p "$proj"
  local prompt_file="$TMPDIR_TEST/custom.md"
  echo "Custom prompt: {{PROJECT_DIR}} round {{ROUND}}" > "$prompt_file"

  local output
  output="$("$LOOP_SH" --mode=converge --project="$proj" --prompt="$prompt_file" --dry-run 2>&1)"

  assert_contains "uses custom prompt" "Prompt: $prompt_file" "$output"
}

# --- Test: log-dir option ---
test_log_dir() {
  echo "test_log_dir:"
  local proj="$TMPDIR_TEST/log-dir-test"
  local logdir="$TMPDIR_TEST/my-logs"
  mkdir -p "$proj"

  local output
  output="$("$LOOP_SH" --mode=converge --project="$proj" --log-dir="$logdir" --dry-run 2>&1)"

  assert_contains "shows log dir" "$logdir" "$output"
}

# --- Test: default max-rounds is 5 ---
test_default_max_rounds() {
  echo "test_default_max_rounds:"
  local proj="$TMPDIR_TEST/default-rounds"
  mkdir -p "$proj"

  local output
  output="$("$LOOP_SH" --mode=converge --project="$proj" --dry-run 2>&1)"

  assert_contains "default max rounds is 5" "Max rounds: 5" "$output"
}

# --- Test: converge mode with mock claude (issues converge to 0) ---
test_converge_mock() {
  echo "test_converge_mock:"
  local proj="$TMPDIR_TEST/converge-mock"
  local logdir="$TMPDIR_TEST/converge-mock-logs"
  mkdir -p "$proj" "$logdir"

  # Create a mock claude that returns decreasing issues
  local mock_claude="$TMPDIR_TEST/mock-claude"
  local call_count_file="$TMPDIR_TEST/claude-call-count"
  echo "0" > "$call_count_file"

  cat > "$mock_claude" <<'MOCK'
#!/usr/bin/env bash
COUNT_FILE="$(dirname "$0")/claude-call-count"
count=$(cat "$COUNT_FILE")
count=$((count + 1))
echo "$count" > "$COUNT_FILE"

if [[ $count -eq 1 ]]; then
  echo "Found some issues"
  echo '<loop-result>{"issues": 3}</loop-result>'
elif [[ $count -eq 2 ]]; then
  echo "Fixed most issues"
  echo '<loop-result>{"issues": 1}</loop-result>'
else
  echo "All clear"
  echo '<loop-result>{"issues": 0}</loop-result>'
fi
MOCK
  chmod +x "$mock_claude"

  # Run with CLAUDE_CMD override
  local output
  output="$(CLAUDE_CMD="$mock_claude" "$LOOP_SH" --mode=converge --project="$proj" --max-rounds=5 --log-dir="$logdir" 2>&1)"

  assert_contains "completes successfully" "CONVERGED" "$output"
  assert_contains "ran 3 rounds" "Round 3" "$output"

  # Check progress file exists
  local progress_file="$logdir/progress.txt"
  if [[ -f "$progress_file" ]]; then
    echo "  PASS: progress file created"
    PASS=$((PASS + 1))

    local pcontent
    pcontent="$(cat "$progress_file")"
    assert_contains "progress shows convergence" "CONVERGED" "$pcontent"
  else
    echo "  FAIL: progress file not created"
    FAIL=$((FAIL + 1))
  fi
}

# --- Test: converge mode stops on worsening ---
test_converge_worsening() {
  echo "test_converge_worsening:"
  local proj="$TMPDIR_TEST/worsen-mock"
  local logdir="$TMPDIR_TEST/worsen-mock-logs"
  mkdir -p "$proj" "$logdir"

  local mock_claude="$TMPDIR_TEST/mock-claude-worsen"
  local call_count_file="$TMPDIR_TEST/worsen-call-count"
  echo "0" > "$call_count_file"

  cat > "$mock_claude" <<'MOCK'
#!/usr/bin/env bash
COUNT_FILE="$(dirname "$0")/worsen-call-count"
count=$(cat "$COUNT_FILE")
count=$((count + 1))
echo "$count" > "$COUNT_FILE"

if [[ $count -eq 1 ]]; then
  echo '<loop-result>{"issues": 3}</loop-result>'
else
  echo '<loop-result>{"issues": 5}</loop-result>'
fi
MOCK
  chmod +x "$mock_claude"

  local output
  output="$(CLAUDE_CMD="$mock_claude" "$LOOP_SH" --mode=converge --project="$proj" --max-rounds=5 --log-dir="$logdir" 2>&1)" || true

  assert_contains "detects worsening" "WORSENING" "$output"
}

# --- Test: backlog mode with mock claude ---
test_backlog_mock() {
  echo "test_backlog_mock:"
  local proj="$TMPDIR_TEST/backlog-mock"
  local logdir="$TMPDIR_TEST/backlog-mock-logs"
  mkdir -p "$proj/src" "$logdir"

  echo "// TODO: item one" > "$proj/src/a.ts"
  echo "// FIXME: item two" > "$proj/src/b.ts"

  local mock_claude="$TMPDIR_TEST/mock-claude-backlog"
  cat > "$mock_claude" <<'MOCK'
#!/usr/bin/env bash
echo "Fixed the item"
echo '<loop-result>{"status": "done", "summary": "Fixed it"}</loop-result>'
MOCK
  chmod +x "$mock_claude"

  local output
  output="$(CLAUDE_CMD="$mock_claude" "$LOOP_SH" --mode=backlog --project="$proj" --source=auto --max-rounds=5 --log-dir="$logdir" 2>&1)"

  assert_contains "processes items" "Round 1" "$output"
  assert_contains "processes second item" "Round 2" "$output"
  assert_contains "shows done status" "done" "$output"
}

# --- Test: converge mode passes previous round's JSON Lines issues to next round ---
test_converge_previous_issues() {
  echo "test_converge_previous_issues:"
  local proj="$TMPDIR_TEST/prev-issues"
  local logdir="$TMPDIR_TEST/prev-issues-logs"
  mkdir -p "$proj" "$logdir"

  # Create mock claude that:
  # Round 1: outputs JSON Lines issues + 2 issues
  # Round 2: checks that the prompt contains previous issues, outputs 0
  local mock_claude="$TMPDIR_TEST/mock-claude-prev"
  local call_count_file="$TMPDIR_TEST/prev-issues-call-count"
  local prompt_capture_file="$TMPDIR_TEST/prev-issues-prompt-r2"
  echo "0" > "$call_count_file"

  cat > "$mock_claude" <<MOCK
#!/usr/bin/env bash
COUNT_FILE="$call_count_file"
PROMPT_CAPTURE="$prompt_capture_file"
count=\$(cat "\$COUNT_FILE")
count=\$((count + 1))
echo "\$count" > "\$COUNT_FILE"

if [[ \$count -eq 1 ]]; then
  echo '{"severity":"high","file":"src/app.ts","line":10,"title":"Missing null check","description":"Variable x can be null","evidence":"line 10","fix_code":"if (x) { ... }"}'
  echo '{"severity":"medium","file":"src/utils.ts","line":25,"title":"Unused import","description":"Import foo is unused","evidence":"line 1","fix_code":"remove line 1"}'
  echo '<loop-result>{"issues": 2}</loop-result>'
elif [[ \$count -eq 2 ]]; then
  # Capture the prompt (passed via -p flag) for assertion
  # The prompt is the argument after -p
  for arg in "\$@"; do
    if [[ "\$prev_was_p" == "true" ]]; then
      echo "\$arg" > "\$PROMPT_CAPTURE"
      break
    fi
    if [[ "\$arg" == "-p" ]]; then
      prev_was_p=true
    fi
  done
  echo '<loop-result>{"issues": 0}</loop-result>'
fi
MOCK
  chmod +x "$mock_claude"

  local output
  output="$(CLAUDE_CMD="$mock_claude" "$LOOP_SH" --mode=converge --project="$proj" --max-rounds=5 --log-dir="$logdir" 2>&1)"

  assert_contains "converges in 2 rounds" "CONVERGED" "$output"

  # Verify round 1 log contains JSON Lines
  local r1_log="$logdir/round-1.log"
  if [[ -f "$r1_log" ]]; then
    local r1_content
    r1_content="$(cat "$r1_log")"
    assert_contains "round 1 log has issue JSON" "Missing null check" "$r1_content"
    echo "  PASS: round 1 log exists"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: round 1 log not found"
    FAIL=$((FAIL + 1))
  fi

  # Verify the prompt for round 2 contains previous issues JSON
  if [[ -f "$prompt_capture_file" ]]; then
    local r2_prompt
    r2_prompt="$(cat "$prompt_capture_file")"
    assert_contains "round 2 prompt has previous JSON issues" "Missing null check" "$r2_prompt"
    assert_contains "round 2 prompt has severity info" "high" "$r2_prompt"
  else
    echo "  FAIL: round 2 prompt not captured"
    FAIL=$((FAIL + 1))
  fi
}

# --- Run all tests ---
echo "=== claude-loop.sh tests ==="
test_help
test_missing_mode
test_invalid_mode
test_dry_run_converge
test_dry_run_backlog
test_custom_prompt
test_log_dir
test_default_max_rounds
test_converge_mock
test_converge_worsening
test_converge_previous_issues
test_backlog_mock

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
