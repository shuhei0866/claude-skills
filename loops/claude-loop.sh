#!/usr/bin/env bash
# claude-loop.sh - Universal loop runner for Claude Code
#
# Two modes:
#   converge: Review -> fix -> re-review until 0 issues
#   backlog:  Process backlog items one by one
#
# Usage:
#   claude-loop.sh --mode=converge [options]
#   claude-loop.sh --mode=backlog  [options]
#
# Options:
#   --mode=converge|backlog   Mode selection (required)
#   --max-rounds=N            Maximum iterations (default: 5)
#   --project=<path>          Target project path (default: .)
#   --prompt=<path>           Prompt template file (default: built-in)
#   --log-dir=<path>          Log output directory (default: .claude/loop-logs/)
#   --source=<source>         Backlog source: auto|issues|auto+issues|<file> (backlog mode)
#   --label=<label>           GitHub Issues label (default: tech-debt)
#   --dry-run                 Show what would be executed without calling claude
#   --help                    Show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Allow overriding claude command for testing
CLAUDE_CMD="${CLAUDE_CMD:-claude}"

# --- Color output ---
_is_tty() {
  [[ -t 1 ]]
}

_color() {
  if _is_tty; then
    printf '\033[%sm' "$1"
  fi
}

_reset() {
  if _is_tty; then
    printf '\033[0m'
  fi
}

log_info() {
  _color "36"  # cyan
  printf "[loop] "
  _reset
  printf '%s\n' "$*"
}

log_warn() {
  _color "33"  # yellow
  printf "[loop] WARNING: "
  _reset
  printf '%s\n' "$*"
}

log_error() {
  _color "31"  # red
  printf "[loop] ERROR: "
  _reset
  printf '%s\n' "$*" >&2
}

log_success() {
  _color "32"  # green
  printf "[loop] "
  _reset
  printf '%s\n' "$*"
}

# --- Usage ---
usage() {
  cat <<'EOF'
Usage: claude-loop.sh --mode=<converge|backlog> [options]

Modes:
  converge    Review -> fix -> re-review until 0 issues found
  backlog     Process backlog items (TODOs, lint errors, issues) one by one

Options:
  --mode=converge|backlog   Mode selection (required)
  --max-rounds=N            Maximum iterations (default: 5)
  --project=<path>          Target project path (default: current directory)
  --prompt=<path>           Prompt template file (default: built-in per mode)
  --log-dir=<path>          Log output directory (default: .claude/loop-logs/)
  --source=<source>         Backlog source: auto|issues|auto+issues|<file.json>
  --label=<label>           GitHub Issues label for --source=issues (default: tech-debt)
  --dry-run                 Show what would be executed without calling claude
  --help                    Show this help

Environment:
  CLAUDE_CMD                Override claude command (for testing)

Examples:
  claude-loop.sh --mode=converge --project=~/my-project --max-rounds=5
  claude-loop.sh --mode=backlog --project=~/my-project --source=auto --max-rounds=10
  claude-loop.sh --mode=backlog --source=issues --label=tech-debt
  claude-loop.sh --mode=converge --dry-run
EOF
}

# --- Parse arguments ---
MODE=""
MAX_ROUNDS=5
PROJECT_DIR="."
PROMPT_FILE=""
LOG_DIR=""
SOURCE="auto"
LABEL="tech-debt"
DRY_RUN=false

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode=*)
        MODE="${1#--mode=}"
        ;;
      --max-rounds=*)
        MAX_ROUNDS="${1#--max-rounds=}"
        ;;
      --project=*)
        PROJECT_DIR="${1#--project=}"
        ;;
      --prompt=*)
        PROMPT_FILE="${1#--prompt=}"
        ;;
      --log-dir=*)
        LOG_DIR="${1#--log-dir=}"
        ;;
      --source=*)
        SOURCE="${1#--source=}"
        ;;
      --label=*)
        LABEL="${1#--label=}"
        ;;
      --dry-run)
        DRY_RUN=true
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      converge|backlog)
        MODE="$1"
        ;;
      *)
        log_error "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
    shift
  done

  # Validate mode
  if [[ -z "$MODE" ]]; then
    log_error "mode is required. Use --mode=converge or --mode=backlog"
    usage
    exit 1
  fi

  if [[ "$MODE" != "converge" && "$MODE" != "backlog" ]]; then
    log_error "invalid mode: $MODE. Must be 'converge' or 'backlog'"
    exit 1
  fi

  # Resolve project dir to absolute path
  if [[ -d "$PROJECT_DIR" ]]; then
    PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
  else
    log_error "Project directory not found: $PROJECT_DIR"
    exit 1
  fi

  # Set defaults
  if [[ -z "$LOG_DIR" ]]; then
    LOG_DIR="$PROJECT_DIR/.claude/loop-logs"
  fi

  if [[ -z "$PROMPT_FILE" ]]; then
    if [[ "$MODE" == "converge" ]]; then
      PROMPT_FILE="$SCRIPT_DIR/prompts/review-converge.md"
    else
      PROMPT_FILE="$SCRIPT_DIR/prompts/debt-sweep.md"
    fi
  fi
}

# --- Template rendering ---
render_template() {
  local template="$1"
  shift
  # Replace {{VAR}} patterns with provided key=value pairs
  local content
  content="$(cat "$template")"

  while [[ $# -gt 0 ]]; do
    local key="${1%%=*}"
    local value="${1#*=}"
    content="${content//\{\{$key\}\}/$value}"
    shift
  done

  printf '%s' "$content"
}

# --- Extract loop result from claude output ---
extract_loop_result() {
  local output="$1"
  # Extract JSON from <loop-result>...</loop-result> tag
  local result
  result="$(echo "$output" | sed -n 's/.*<loop-result>\(.*\)<\/loop-result>.*/\1/p' | tail -1)" || true
  echo "${result:-}"
}

# --- Extract JSON Lines issues from a round log ---
# Looks for lines that are valid JSON with a "severity" field (issue entries)
extract_issues_from_log() {
  local log_file="$1"
  if [[ ! -f "$log_file" ]]; then
    return
  fi
  # Match lines that look like JSON objects with "severity" key
  grep -E '^\{.*"severity"' "$log_file" 2>/dev/null || true
}

# --- Run claude ---
run_claude() {
  local prompt="$1"
  local log_file="$2"

  if $DRY_RUN; then
    log_info "[DRY RUN] Would execute: $CLAUDE_CMD -p <prompt> --dangerously-skip-permissions"
    log_info "[DRY RUN] Prompt length: $(echo "$prompt" | wc -c | tr -d ' ') chars"
    echo '<loop-result>{"issues": 0}</loop-result>'
    return
  fi

  local output
  output="$("$CLAUDE_CMD" -p "$prompt" --dangerously-skip-permissions 2>&1 | tee "$log_file")" || true
  echo "$output"
}

# --- Converge mode ---
run_converge() {
  log_info "Starting converge mode"
  log_info "Project: $PROJECT_DIR"
  log_info "Max rounds: $MAX_ROUNDS"
  log_info "Prompt: $PROMPT_FILE"
  log_info "Log dir: $LOG_DIR"

  mkdir -p "$LOG_DIR"

  source "$SCRIPT_DIR/lib/progress.sh"
  progress_init "converge" "$PROJECT_DIR" "$LOG_DIR/progress.txt"

  local prev_issues=999999
  local round=1

  # Trap for clean interruption
  trap '_on_interrupt' INT

  while [[ $round -le $MAX_ROUNDS ]]; do
    log_info "--- Round $round / $MAX_ROUNDS ---"
    progress_round_start "$round"

    # Build prompt with previous round's issues
    local prev_result=""
    if [[ $round -gt 1 ]]; then
      local prev_log="$LOG_DIR/round-$((round - 1)).log"
      local prev_json_issues
      prev_json_issues="$(extract_issues_from_log "$prev_log")"
      if [[ -n "$prev_json_issues" ]]; then
        prev_result="### Previous Round Issues (Round $((round - 1)))

The previous round found $prev_issues issues. First fix these, then perform a fresh review.

\`\`\`jsonl
$prev_json_issues
\`\`\`"
      else
        prev_result="Previous round found $prev_issues issues. Fix them and perform a fresh review."
      fi
    fi

    local prompt
    if [[ -f "$PROMPT_FILE" ]]; then
      prompt="$(render_template "$PROMPT_FILE" \
        "PROJECT_DIR=$PROJECT_DIR" \
        "PREVIOUS_ISSUES=$prev_result" \
        "ROUND=$round")"
    else
      prompt="Review the project at $PROJECT_DIR. $prev_result Report issues in JSON Lines format. End with <loop-result>{\"issues\": N}</loop-result>"
    fi

    # Run claude
    local log_file="$LOG_DIR/round-${round}.log"
    local output
    output="$(run_claude "$prompt" "$log_file")"

    # Extract result
    local result_json
    result_json="$(extract_loop_result "$output")"

    if [[ -z "$result_json" ]]; then
      log_warn "No <loop-result> tag found in output. Assuming 0 issues."
      result_json='{"issues": 0}'
    fi

    # Parse issue count
    local issues
    issues="$(echo "$result_json" | sed -n 's/.*"issues"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)" || true
    issues="${issues:-0}"

    log_info "Issues found: $issues (previous: $prev_issues)"

    # Calculate fixed (estimate)
    local fixed=0
    if [[ $prev_issues -ne 999999 ]]; then
      fixed=$((prev_issues - issues))
      [[ $fixed -lt 0 ]] && fixed=0
    fi

    progress_round_end "$round" "{\"issues\": $issues, \"fixed\": $fixed, \"skipped\": 0}"

    # Convergence check
    if [[ $issues -eq 0 ]]; then
      log_success "CONVERGED! No issues found in round $round."
      progress_summary
      return 0
    fi

    # Worsening check (skip first round)
    if [[ $prev_issues -ne 999999 && $issues -ge $prev_issues ]]; then
      log_warn "WORSENING: Issues increased or stayed the same ($prev_issues -> $issues). Stopping."
      echo "" >> "$LOG_DIR/progress.txt"
      echo "## WORSENING" >> "$LOG_DIR/progress.txt"
      echo "- Status: WORSENING" >> "$LOG_DIR/progress.txt"
      progress_summary
      return 1
    fi

    prev_issues=$issues
    round=$((round + 1))
  done

  log_warn "Max rounds ($MAX_ROUNDS) reached without convergence."
  echo "" >> "$LOG_DIR/progress.txt"
  echo "## MAX_ROUNDS_REACHED" >> "$LOG_DIR/progress.txt"
  echo "- Status: MAX_ROUNDS_REACHED" >> "$LOG_DIR/progress.txt"
  progress_summary
  return 1
}

# --- Backlog mode ---
run_backlog() {
  log_info "Starting backlog mode"
  log_info "Project: $PROJECT_DIR"
  log_info "Source: $SOURCE"
  log_info "Max rounds: $MAX_ROUNDS"
  log_info "Prompt: $PROMPT_FILE"
  log_info "Log dir: $LOG_DIR"

  mkdir -p "$LOG_DIR"

  source "$SCRIPT_DIR/lib/progress.sh"
  progress_init "backlog" "$PROJECT_DIR" "$LOG_DIR/progress.txt"

  # Collect backlog items
  local backlog_file="$LOG_DIR/backlog.jsonl"
  local backlog_output

  if [[ "$SOURCE" == "auto" || "$SOURCE" == "issues" || "$SOURCE" == "auto+issues" ]]; then
    backlog_output="$("$SCRIPT_DIR/lib/backlog-collect.sh" "$PROJECT_DIR" --source="$SOURCE" --label="$LABEL" 2>/dev/null)" || true
  else
    backlog_output="$("$SCRIPT_DIR/lib/backlog-collect.sh" "$PROJECT_DIR" --source="$SOURCE" 2>/dev/null)" || true
  fi

  if [[ -z "$backlog_output" ]]; then
    log_success "No backlog items found. Nothing to do."
    return 0
  fi

  echo "$backlog_output" > "$backlog_file"
  local total_items
  total_items="$(echo "$backlog_output" | wc -l | tr -d ' ')"
  log_info "Backlog items: $total_items"

  if $DRY_RUN; then
    log_info "[DRY RUN] Configuration:"
    log_info "  Mode: backlog"
    log_info "  Max rounds: $MAX_ROUNDS"
    log_info "  Backlog items: $total_items"
    echo "$backlog_output" | head -5
    [[ $total_items -gt 5 ]] && log_info "  ... and $((total_items - 5)) more"
    return 0
  fi

  # Trap for clean interruption
  trap '_on_interrupt' INT

  local round=1
  local done_count=0
  local skip_count=0
  local fail_count=0

  while IFS= read -r item && [[ $round -le $MAX_ROUNDS ]]; do
    log_info "--- Round $round / $MAX_ROUNDS (item $round/$total_items) ---"
    progress_round_start "$round"

    # Build prompt
    local prompt
    if [[ -f "$PROMPT_FILE" ]]; then
      prompt="$(render_template "$PROMPT_FILE" \
        "PROJECT_DIR=$PROJECT_DIR" \
        "ITEM=$item" \
        "ITEM_INDEX=$round" \
        "TOTAL_ITEMS=$total_items")"
    else
      prompt="Fix the following item in $PROJECT_DIR: $item. Report result with <loop-result>{\"status\": \"done|skip|fail\", \"summary\": \"...\"}</loop-result>"
    fi

    # Run claude
    local log_file="$LOG_DIR/round-${round}.log"
    local output
    output="$(run_claude "$prompt" "$log_file")"

    # Extract result
    local result_json
    result_json="$(extract_loop_result "$output")"

    if [[ -z "$result_json" ]]; then
      log_warn "No <loop-result> found. Marking as skip."
      result_json='{"status": "skip", "summary": "No result tag in output"}'
    fi

    local status
    status="$(echo "$result_json" | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)" || true
    status="${status:-skip}"

    local summary
    summary="$(echo "$result_json" | sed -n 's/.*"summary"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)" || true
    summary="${summary:-No summary}"

    log_info "Result: $status - $summary"
    progress_round_end "$round" "$result_json"

    case "$status" in
      done)  done_count=$((done_count + 1)) ;;
      skip)  skip_count=$((skip_count + 1)) ;;
      fail)  fail_count=$((fail_count + 1)) ;;
    esac

    round=$((round + 1))
  done <<< "$backlog_output"

  log_info "=== Backlog Summary ==="
  log_info "Done: $done_count, Skipped: $skip_count, Failed: $fail_count"
  progress_summary
}

# --- Interrupt handler ---
_on_interrupt() {
  log_warn "Interrupted by user (Ctrl+C)"
  progress_mark_interrupted
  exit 130
}

# --- Dry run display ---
show_dry_run() {
  log_info "[DRY RUN] Configuration:"
  log_info "  Mode: $MODE"
  log_info "  Project: $PROJECT_DIR"
  log_info "  Max rounds: $MAX_ROUNDS"
  log_info "  Prompt: $PROMPT_FILE"
  log_info "  Log dir: $LOG_DIR"

  if [[ "$MODE" == "backlog" ]]; then
    local backlog_output
    backlog_output="$("$SCRIPT_DIR/lib/backlog-collect.sh" "$PROJECT_DIR" --source="$SOURCE" --label="$LABEL" 2>/dev/null)" || true
    local count=0
    if [[ -n "$backlog_output" ]]; then
      count="$(echo "$backlog_output" | wc -l | tr -d ' ')"
    fi
    log_info "  Backlog items: $count"
  fi
}

# --- Main ---
main() {
  parse_args "$@"

  if $DRY_RUN && [[ "$MODE" == "converge" ]]; then
    show_dry_run
    return 0
  fi

  case "$MODE" in
    converge)
      run_converge
      ;;
    backlog)
      run_backlog
      ;;
  esac
}

main "$@"
