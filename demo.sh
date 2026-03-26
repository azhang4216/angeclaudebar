#!/usr/bin/env bash
# AngeClaudeBar demo — renders all layout tiers and account types.
# Run directly to preview, or use to generate preview.svg:
#   npx svg-term-cli --command "bash demo.sh" --out preview.svg --width 210 --height 42

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUSLINE="$SCRIPT_DIR/statusline.sh"

mkdir -p /tmp/claude

# ── Plan setup helpers ────────────────────────────────────────────────────────

setup_api_plan() {
  # Profile with no Pro/Max flags; empty usage file so subscription check is false
  printf '{"account":{"email":"you@example.com","has_claude_max":false,"has_claude_pro":false}}' \
    > /tmp/claude/statusline-profile-cache.json
  : > /tmp/claude/statusline-usage-cache.json   # empty = no usage data
}

setup_pro_plan() {
  printf '{"account":{"email":"you@example.com","has_claude_max":false,"has_claude_pro":true}}' \
    > /tmp/claude/statusline-profile-cache.json
  # utilization is 0-100 (percentage)
  printf '{"five_hour":{"utilization":42,"resets_at":"2026-03-26T16:00:00Z"},"seven_day":{"utilization":18,"resets_at":"2026-03-28T00:00:00Z"},"extra_usage":{"is_enabled":false,"monthly_limit":0}}' \
    > /tmp/claude/statusline-usage-cache.json
}

setup_max_plan() {
  printf '{"account":{"email":"you@example.com","has_claude_max":true,"has_claude_pro":false}}' \
    > /tmp/claude/statusline-profile-cache.json
  printf '{"five_hour":{"utilization":72,"resets_at":"2026-03-26T16:00:00Z"},"seven_day":{"utilization":55,"resets_at":"2026-03-28T00:00:00Z"},"extra_usage":{"is_enabled":true,"monthly_limit":10000,"utilization":31,"used_credits":3100}}' \
    > /tmp/claude/statusline-usage-cache.json
}

# ── Helpers ───────────────────────────────────────────────────────────────────
DIM='\033[38;2;110;115;141m'
BOLD='\033[1m'
R='\033[0m'

json() {
  local dir="${1}" cost="${2:-0}" model="${3:-Sonnet 4.6}" ctx="${4:-14}"
  printf '{"workspace":{"project_dir":"%s"},"model":{"display_name":"%s"},"context_window":{"used_percentage":%s,"context_window_size":200000,"current_usage":{"input_tokens":28000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cost":{"total_cost_usd":%s},"cwd":"%s"}' \
    "$dir" "$model" "$ctx" "$cost" "$dir"
}

show() {
  local label="$1" cols="$2" j="$3"
  printf "${DIM}%-42s width %-3d${R}  " "$label" "$cols"
  printf '%s' "$j" | STATUSLINE_COLS="$cols" bash "$STATUSLINE" 2>/dev/null || true
  printf '\n'
}

# ── Demo ──────────────────────────────────────────────────────────────────────
printf '\n'
printf "${BOLD}AngeClaudeBar — layout preview${R}\n"
printf '\n'

printf "${DIM}── API billing ──────────────────────────────────────────────────────${R}\n"
setup_api_plan
show "wide  (gauge visible)"          200 "$(json /Users/you/repos/my-project 0.34)"
show "medium  (no gauge, full cost)"  140 "$(json /Users/you/repos/my-project 0.34)"
show "compact  (project name)"         95 "$(json /Users/you/repos/my-project 0.34)"
show "narrow  (short name)"            70 "$(json /Users/you/repos/my-project 0.34)"
printf '\n'

printf "${DIM}── Pro plan ─────────────────────────────────────────────────────────${R}\n"
setup_pro_plan
show "wide  (5h/7d gauges + resets)"  200 "$(json /Users/you/repos/my-project 0)"
show "medium  (usage percentages)"    140 "$(json /Users/you/repos/my-project 0)"
show "compact"                          95 "$(json /Users/you/repos/my-project 0)"
printf '\n'

printf "${DIM}── Max plan  (extra budget enabled) ─────────────────────────────────${R}\n"
setup_max_plan
show "wide  (extra budget shown)"     200 "$(json /Users/you/repos/my-project 0 'Claude Opus 4.6' 67)"
show "medium"                          140 "$(json /Users/you/repos/my-project 0 'Claude Opus 4.6' 67)"
printf '\n'
