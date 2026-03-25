#!/usr/bin/env bash
# Claude Code Status Line - Catppuccin Macchiato theme
# Line 1: project, git branch + diff stats, model, context gauge
# Line 2: weekly gauge, current gauge, session cost

# --- Colors (Catppuccin Macchiato truecolor) ---
R='\033[0m'                           # reset
C_RED='\033[38;2;237;135;150m'        # #ed8796 - project name
C_GREEN='\033[38;2;166;218;149m'      # #a6da95 - git branch
C_AMBER='\033[38;2;238;212;159m'      # #eed49f - diff stats, cost
C_PURPLE='\033[38;2;198;160;246m'     # #c6a0f6 - model
C_TEAL='\033[38;2;139;213;202m'       # #8bd5ca - healthy gauge fill
C_PEACH='\033[38;2;245;169;127m'      # #f5a97f - bypass mode
C_MUTED='\033[38;2;110;115;141m'      # #6e738d - labels, hints
C_OVERLAY='\033[38;2;54;58;79m'       # #363a4f - empty gauge, separators

# --- Read JSON from stdin ---
input=$(cat)
if [ -z "$input" ]; then
  printf "Claude"
  exit 0
fi

# --- Parse fields ---
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // .workspace.current_dir // empty')
[ -z "$project_dir" ] || [ "$project_dir" = "null" ] && project_dir=$(echo "$input" | jq -r '.cwd // empty')
project_name=$(basename "${project_dir:-Claude}")
# Short version for narrow tiers
if [ ${#project_name} -gt 12 ]; then
  project_short="${project_name:0:10}.."
else
  project_short="$project_name"
fi

model_full=$(echo "$input" | jq -r '.model.display_name // "Claude"' | sed 's/ context//')
model_name=$(echo "$model_full" | sed 's/^\([A-Z][a-z]\)[a-z]*/\1/')
# Tiny: drop version number, e.g. "Op (1M)"
model_tiny=$(echo "$model_name" | sed 's/ [0-9][0-9.]*//')
# Readable model name: first word + version e.g. "Sonnet-4.6"
model_word=$(echo "$model_full" | awk '{print $1}')
model_ver=$(echo "$model_full" | grep -oE '[0-9]+\.[0-9]+' | head -1)
[ -n "$model_ver" ] && model_short="${model_word}-${model_ver}" || model_short="$model_word"
session_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

# --- Git info ---
git_branch=""
diff_str=""
if [ -n "$project_dir" ] && git -C "$project_dir" rev-parse --git-dir >/dev/null 2>&1; then
  git_branch=$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
  git_status=$(git -C "$project_dir" --no-optional-locks status --porcelain 2>/dev/null)
  if [ -n "$git_status" ]; then
    m=$(echo "$git_status" | grep -c '^ M\|^M' || true)
    a=$(echo "$git_status" | grep -c '^A\|^??' || true)
    d=$(echo "$git_status" | grep -c '^ D\|^D' || true)
    parts=()
    [ "$m" -gt 0 ] 2>/dev/null && parts+=("${m}M")
    [ "$a" -gt 0 ] 2>/dev/null && parts+=("${a}A")
    [ "$d" -gt 0 ] 2>/dev/null && parts+=("${d}D")
    if [ ${#parts[@]} -gt 0 ]; then
      diff_str=$(IFS=','; echo "${parts[*]}")
    fi
  fi
fi

# --- Helpers ---
format_tokens() {
  local t=$1
  if [ "$t" -ge 1000000 ] 2>/dev/null; then
    awk "BEGIN {printf \"%.0fM\", $t / 1000000}"
  elif [ "$t" -ge 10000 ] 2>/dev/null; then
    awk "BEGIN {printf \"%.0fK\", $t / 1000}"
  elif [ "$t" -ge 1000 ] 2>/dev/null; then
    awk "BEGIN {printf \"%.1fK\", $t / 1000}"
  else
    echo "$t"
  fi
}

# Gauge with color thresholds using background-colored spaces (avoids Unicode width glitches).
# Args: pct, mode (context|budget)
gauge() {
  local pct=$1 mode=${2:-context}
  [ "$pct" -lt 0 ] 2>/dev/null && pct=0
  [ "$pct" -gt 100 ] 2>/dev/null && pct=100
  local nf=$((pct * 10 / 100)) ne
  [ "$pct" -gt 0 ] && [ "$nf" -eq 0 ] && nf=1
  [ "$nf" -gt 10 ] && nf=10
  ne=$((10 - nf))

  local fill_bg
  if [ "$mode" = "budget" ]; then
    if [ "$pct" -lt 50 ]; then fill_bg='\033[48;2;166;218;149m'      # green bg
    elif [ "$pct" -lt 80 ]; then fill_bg='\033[48;2;238;212;159m'    # amber bg
    else fill_bg='\033[48;2;237;135;150m'                             # red bg
    fi
  else
    if [ "$pct" -lt 40 ]; then fill_bg='\033[48;2;139;213;202m'      # teal bg
    elif [ "$pct" -lt 70 ]; then fill_bg='\033[48;2;238;212;159m'    # amber bg
    else fill_bg='\033[48;2;237;135;150m'                             # red bg
    fi
  fi
  local empty_bg='\033[48;2;54;58;79m'  # overlay bg

  local filled="" empty=""
  for ((i=0; i<nf; i++)); do filled+=" "; done
  for ((i=0; i<ne; i++)); do empty+=" "; done
  printf "%b%s%b%s%b" "$fill_bg" "$filled" "$empty_bg" "$empty" "$R"
}

fmt_reset() {
  local iso="$1"
  [ -z "$iso" ] || [ "$iso" = "null" ] && return

  # Strip fractional seconds: "2026-03-13T19:00:00.511778+00:00" -> "2026-03-13T19:00:00+00:00"
  local clean
  if [[ "$iso" == *"."* ]]; then
    local before_dot="${iso%%.*}"
    local after_dot="${iso#*.}"
    # after_dot is like "511778+00:00" or "511778Z"
    local tz_part=""
    if [[ "$after_dot" == *"+"* ]]; then
      tz_part="+${after_dot#*+}"
    elif [[ "$after_dot" == *"-"* ]]; then
      tz_part="-${after_dot#*-}"
    elif [[ "$after_dot" == *"Z"* ]]; then
      tz_part="Z"
    fi
    clean="${before_dot}${tz_part}"
  else
    clean="$iso"
  fi

  # Convert ISO with any timezone offset to epoch
  # Extract the datetime and offset parts
  local dt_part tz_part=""
  if [[ "$clean" == *"Z" ]]; then
    dt_part="${clean%%Z*}"
    tz_part="+00:00"
  elif [[ "$clean" =~ (.+)([+-][0-9]{2}:[0-9]{2})$ ]]; then
    dt_part="${BASH_REMATCH[1]}"
    tz_part="${BASH_REMATCH[2]}"
  else
    dt_part="$clean"
  fi

  local epoch
  if [ -n "$tz_part" ]; then
    # Parse datetime as-is, then adjust for offset to get true UTC epoch
    local raw_epoch
    raw_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$dt_part" "+%s" 2>/dev/null)
    if [ -n "$raw_epoch" ]; then
      # raw_epoch interpreted the time as local; we need to undo that and apply the real offset
      # Get local UTC offset in seconds
      local local_off_str local_off_sec
      local_off_str=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$dt_part" "+%z" 2>/dev/null)
      local sign_l=${local_off_str:0:1} hh_l=${local_off_str:1:2} mm_l=${local_off_str:3:2}
      local_off_sec=$(( (10#$hh_l * 3600 + 10#$mm_l * 60) ))
      [ "$sign_l" = "-" ] && local_off_sec=$(( -local_off_sec ))
      # Parse the actual offset from the timestamp (strip colon: +00:00 -> +0000)
      local tz_flat="${tz_part/:/}"
      local sign_t=${tz_flat:0:1} hh_t=${tz_flat:1:2} mm_t=${tz_flat:3:2}
      local tz_off_sec=$(( (10#$hh_t * 3600 + 10#$mm_t * 60) ))
      [ "$sign_t" = "-" ] && tz_off_sec=$(( -tz_off_sec ))
      # Correct: raw_epoch assumed local offset, but real offset is tz_off_sec
      epoch=$(( raw_epoch + local_off_sec - tz_off_sec ))
    fi
  fi
  # Fallback: GNU date handles ISO offsets natively
  [ -z "$epoch" ] && epoch=$(date -d "$clean" "+%s" 2>/dev/null)
  [ -z "$epoch" ] && return

  # Format in local time
  local today_date reset_date time_str
  today_date=$(date "+%Y-%m-%d")
  reset_date=$(date -r "$epoch" "+%Y-%m-%d" 2>/dev/null)
  time_str=$(date -r "$epoch" "+%-I:%M%p" 2>/dev/null | tr 'A-Z' 'a-z' | sed 's/:00//')
  if [ "$reset_date" = "$today_date" ]; then
    printf "%s" "$time_str"
  else
    local mode="${2:-short}"
    local md
    if [ "$mode" = "full" ]; then
      md=$(date -r "$epoch" "+%B %-d" 2>/dev/null)
    else
      md=$(date -r "$epoch" "+%-m/%-d" 2>/dev/null)
    fi
    printf "%s, %s" "$time_str" "$md"
  fi
}

# --- Context window ---
ctx_pct=0
ctx_used=0
ctx_max=200000
ctx_used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$ctx_used_pct" ] && [ "$ctx_used_pct" != "null" ]; then
  ctx_pct=$(printf "%.0f" "$ctx_used_pct")
fi
ctx_max=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
ctx_usage=$(echo "$input" | jq '.context_window.current_usage // empty')
if [ -n "$ctx_usage" ] && [ "$ctx_usage" != "null" ] && [ "$ctx_usage" != "" ]; then
  ctx_used=$(echo "$ctx_usage" | jq '(.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)' 2>/dev/null)
  [ -z "$ctx_used" ] && ctx_used=0
  if [ "$ctx_pct" -eq 0 ] && [ "$ctx_max" -gt 0 ] 2>/dev/null; then
    ctx_pct=$((ctx_used * 100 / ctx_max))
  fi
fi
# If we still don't have used tokens, estimate from percentage
if [ "$ctx_used" -eq 0 ] && [ "$ctx_pct" -gt 0 ] 2>/dev/null; then
  ctx_used=$((ctx_pct * ctx_max / 100))
fi

ctx_used_fmt=$(format_tokens "$ctx_used")
ctx_max_fmt=$(format_tokens "$ctx_max")
ctx_gauge=$(gauge "$ctx_pct" context)

# --- OAuth usage API (cached) ---
USAGE_CACHE="/tmp/claude/statusline-usage-cache.json"
mkdir -p /tmp/claude 2>/dev/null

get_oauth_token() {
  if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
    echo "$CLAUDE_CODE_OAUTH_TOKEN"; return 0
  fi
  if command -v security >/dev/null 2>&1; then
    local blob
    blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
    if [ -n "$blob" ]; then
      local tok
      tok=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
      if [ -n "$tok" ] && [ "$tok" != "null" ]; then echo "$tok"; return 0; fi
    fi
  fi
  local cf="${HOME}/.claude/.credentials.json"
  if [ -f "$cf" ]; then
    local tok
    tok=$(jq -r '.claudeAiOauth.accessToken // empty' "$cf" 2>/dev/null)
    if [ -n "$tok" ] && [ "$tok" != "null" ]; then echo "$tok"; return 0; fi
  fi
  echo ""
}

USAGE_LOCK="/tmp/claude/statusline-usage.lock"
CACHE_TTL=300  # 5 minutes; shared across all sessions

usage_data=""
needs_refresh=true
if [ -f "$USAGE_CACHE" ]; then
  cache_age=$(( $(date +%s) - $(stat -f%m "$USAGE_CACHE" 2>/dev/null || echo 0) ))
  [ "$cache_age" -lt "$CACHE_TTL" ] && needs_refresh=false && usage_data=$(cat "$USAGE_CACHE" 2>/dev/null)
fi
if $needs_refresh; then
  # Clean up stale lock (older than 10 seconds means the holder crashed)
  if [ -f "$USAGE_LOCK" ]; then
    lock_age=$(( $(date +%s) - $(stat -f%m "$USAGE_LOCK" 2>/dev/null || echo 0) ))
    [ "$lock_age" -gt 10 ] && rm -f "$USAGE_LOCK"
  fi
  # Lock prevents multiple sessions from refreshing simultaneously
  if ( set -o noclobber; echo $$ > "$USAGE_LOCK" ) 2>/dev/null; then
    trap 'rm -f "$USAGE_LOCK"' EXIT
    tok=$(get_oauth_token)
    if [ -n "$tok" ] && [ "$tok" != "null" ]; then
      resp=$(curl -s --max-time 5 \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $tok" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -H "User-Agent: claude-code/2.1.74" \
        "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
      if [ -n "$resp" ] && echo "$resp" | jq -e '.five_hour' >/dev/null 2>&1; then
        usage_data="$resp"
        echo "$resp" > "$USAGE_CACHE"
      fi
    fi
    rm -f "$USAGE_LOCK"
    trap - EXIT
  fi
  # Fall back to stale cache (another session is refreshing, or refresh failed)
  [ -z "$usage_data" ] && [ -f "$USAGE_CACHE" ] && usage_data=$(cat "$USAGE_CACHE" 2>/dev/null)
fi

# --- Parse usage data ---
weekly_pct=0; weekly_reset=""
current_pct=0; current_reset=""
extra_pct=0; extra_used=""; extra_limit=""; extra_enabled=false
if [ -n "$usage_data" ]; then
  weekly_pct=$(echo "$usage_data" | jq -r '.seven_day.utilization // 0' | awk '{printf "%.0f", $1}')
  current_pct=$(echo "$usage_data" | jq -r '.five_hour.utilization // 0' | awk '{printf "%.0f", $1}')
  [ "$weekly_pct" -gt 100 ] 2>/dev/null && weekly_pct=100
  [ "$current_pct" -gt 100 ] 2>/dev/null && current_pct=100
  weekly_reset_iso=$(echo "$usage_data" | jq -r '.seven_day.resets_at // empty')
  weekly_reset=$(fmt_reset "$weekly_reset_iso" short)
  weekly_reset_full=$(fmt_reset "$weekly_reset_iso" full)
  current_reset=$(fmt_reset "$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty')" short)
  # Extra usage (only show if enabled and budget > 0)
  extra_enabled=$(echo "$usage_data" | jq -r '.extra_usage.is_enabled // false')
  if [ "$extra_enabled" = "true" ]; then
    extra_limit_raw=$(echo "$usage_data" | jq -r '.extra_usage.monthly_limit // 0')
    if [ "$extra_limit_raw" -gt 0 ] 2>/dev/null; then
      extra_pct=$(echo "$usage_data" | jq -r '.extra_usage.utilization // 0' | awk '{printf "%.0f", $1}')
      [ "$extra_pct" -gt 100 ] 2>/dev/null && extra_pct=100
      extra_used_raw=$(echo "$usage_data" | jq -r '.extra_usage.used_credits // 0')
      extra_remaining=$(echo "$extra_used_raw $extra_limit_raw" | awk '{printf "$%.0f", ($2-$1)/100}')
    else
      extra_enabled=false
    fi
  fi
fi

# --- Account info (email + plan) via /api/oauth/profile (cached) ---
account_email=""
account_plan=""

PROFILE_CACHE="/tmp/claude/statusline-profile-cache.json"
PROFILE_LOCK="/tmp/claude/statusline-profile.lock"
PROFILE_TTL=1800  # 30 minutes

profile_data=""
profile_needs_refresh=true
if [ -f "$PROFILE_CACHE" ]; then
  profile_cache_age=$(( $(date +%s) - $(stat -f%m "$PROFILE_CACHE" 2>/dev/null || echo 0) ))
  [ "$profile_cache_age" -lt "$PROFILE_TTL" ] && profile_needs_refresh=false && profile_data=$(cat "$PROFILE_CACHE" 2>/dev/null)
fi
if $profile_needs_refresh; then
  if [ -f "$PROFILE_LOCK" ]; then
    lock_age=$(( $(date +%s) - $(stat -f%m "$PROFILE_LOCK" 2>/dev/null || echo 0) ))
    [ "$lock_age" -gt 10 ] && rm -f "$PROFILE_LOCK"
  fi
  if ( set -o noclobber; echo $$ > "$PROFILE_LOCK" ) 2>/dev/null; then
    trap 'rm -f "$PROFILE_LOCK"' EXIT
    tok=$(get_oauth_token)
    if [ -n "$tok" ] && [ "$tok" != "null" ]; then
      resp=$(curl -s --max-time 5 \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $tok" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -H "User-Agent: claude-code/2.1.74" \
        "https://api.anthropic.com/api/oauth/profile" 2>/dev/null)
      if [ -n "$resp" ] && echo "$resp" | jq -e '.account.email' >/dev/null 2>&1; then
        profile_data="$resp"
        echo "$resp" > "$PROFILE_CACHE"
      fi
    fi
    rm -f "$PROFILE_LOCK"
    trap - EXIT
  fi
  [ -z "$profile_data" ] && [ -f "$PROFILE_CACHE" ] && profile_data=$(cat "$PROFILE_CACHE" 2>/dev/null)
fi

if [ -n "$profile_data" ]; then
  account_email=$(echo "$profile_data" | jq -r '.account.email // empty' 2>/dev/null)
  [ "$account_email" = "null" ] && account_email=""
  _has_max=$(echo "$profile_data" | jq -r '.account.has_claude_max // false' 2>/dev/null)
  _has_pro=$(echo "$profile_data" | jq -r '.account.has_claude_pro // false' 2>/dev/null)
  if [ "$_has_max" = "true" ]; then
    account_plan="Max"
  elif [ "$_has_pro" = "true" ]; then
    account_plan="Pro"
  fi
fi

# Fallback plan from credentials file
if [ -z "$account_plan" ] && [ -f "${HOME}/.claude/.credentials.json" ]; then
  _sub=$(jq -r '.claudeAiOauth.subscriptionType // empty' "${HOME}/.claude/.credentials.json" 2>/dev/null)
  case "$_sub" in
    *max*) account_plan="Max" ;;
    *pro*) account_plan="Pro" ;;
  esac
fi

# Short email: username before @
_email_short="${account_email%%@*}"

# --- Billing model detection ---
# Subscription plans (Pro/Max) have rolling 5h/7d rate-limit windows.
# API key plans are pay-per-token — no windows, show cost instead.
is_subscription_plan=false
if [ "$account_plan" = "Pro" ] || [ "$account_plan" = "Max" ]; then
  is_subscription_plan=true
elif [ -z "$account_plan" ] && [ -n "$usage_data" ]; then
  # No profile yet but rate-limit data returned — must be subscription
  is_subscription_plan=true
fi

# Formatted session cost for API plans
session_cost_fmt=$(awk "BEGIN {printf \"\$%.2f\", ${session_cost:-0}}")

# --- Separator ---
sep=" ${C_OVERLAY}|${R} "

# =====================================================================
# Width-adaptive layout: detect terminal width, pick best tier
# =====================================================================

# stdin is JSON, so tput/stty need /dev/tty to reach the real terminal
term_cols=$(tput cols < /dev/tty 2>/dev/null || stty size < /dev/tty 2>/dev/null | awk '{print $2}' || echo 80)
# Right-side Claude Code chrome (effort, tokens, version) shares the first line.
avail=$((term_cols - 35))

# Color-coded percentage (no gauge bar). Args: pct, mode
cpct() {
  local pct=$1 mode=${2:-context}
  local color
  if [ "$mode" = "budget" ]; then
    if [ "$pct" -lt 50 ]; then color="$C_GREEN"
    elif [ "$pct" -lt 80 ]; then color="$C_AMBER"
    else color="$C_RED"
    fi
  else
    if [ "$pct" -lt 40 ]; then color="$C_TEAL"
    elif [ "$pct" -lt 70 ]; then color="$C_AMBER"
    else color="$C_RED"
    fi
  fi
  printf "%b%d%%%b" "$color" "$pct" "$R"
}

# Background-color gauge. Args: pct, width, mode
bgauge() {
  local pct=$1 w=${2:-8} mode=${3:-context}
  [ "$pct" -lt 0 ] 2>/dev/null && pct=0
  [ "$pct" -gt 100 ] 2>/dev/null && pct=100
  local nf=$((pct * w / 100))
  [ "$pct" -gt 0 ] && [ "$nf" -eq 0 ] && nf=1
  [ "$nf" -gt "$w" ] && nf=$w
  local ne=$((w - nf))
  local fill_bg
  if [ "$mode" = "budget" ]; then
    if [ "$pct" -lt 50 ]; then fill_bg='\033[48;2;166;218;149m'
    elif [ "$pct" -lt 80 ]; then fill_bg='\033[48;2;238;212;159m'
    else fill_bg='\033[48;2;237;135;150m'
    fi
  else
    if [ "$pct" -lt 40 ]; then fill_bg='\033[48;2;139;213;202m'
    elif [ "$pct" -lt 70 ]; then fill_bg='\033[48;2;238;212;159m'
    else fill_bg='\033[48;2;237;135;150m'
    fi
  fi
  local empty_bg='\033[48;2;54;58;79m'
  local filled="" empty=""
  for ((i=0; i<nf; i++)); do filled+=" "; done
  for ((i=0; i<ne; i++)); do empty+=" "; done
  printf "%b%s%b%s%b" "$fill_bg" "$filled" "$empty_bg" "$empty" "$R"
}

# Account/plan suffix appended to the end of each tier
acct_sfx=""
if [ -n "$_email_short" ] || [ -n "$account_plan" ]; then
  acct_sfx="${sep}"
  [ -n "$_email_short" ] && acct_sfx+="${C_MUTED}${_email_short}${R}"
  if [ -n "$account_plan" ]; then
    [ -n "$_email_short" ] && acct_sfx+=" "
    acct_sfx+="${C_AMBER}${account_plan}${R}"
  fi
fi

# --- Build single-line output based on available width ---
# All tiers are single-line (multi-line is unreliable in Claude Code).
# Content widths measured from actual visible characters:
#   FULL:    project  branch [diffs] | model | gauge ctx% | c% | w%  (~87 chars)
#   WIDE:    project  branch | model | ctx% | c% | w%                (~64 chars)
#   COMPACT: project  branch [diffs] | ctx% | c% | w%               (~52 chars)
#   NARROW:  project  branch | ctx% | c% | w%                       (~40 chars)
#   ULTRA:   branch ctx% c% w%                                      (~16 chars)

# Precompute widths for tier selection
# WIDE uses short model name (Op 4.6 (1M))
model_line_vis=$((${#project_name} + 2 + ${#git_branch} + 3 + ${#model_name} + 3 + 3 + 3 + 5 + 3 + 4))
# FULL uses full model name (Opus 4.6 (1M)) + gauge
full_model_vis=$((${#project_name} + 2 + ${#git_branch} + 3 + ${#model_full} + 3 + 10 + 1 + 4))
full_line_vis=$full_model_vis

if [ "$avail" -ge 88 ] && [ "$avail" -ge "$full_line_vis" ]; then
  # FULL: line 1 = project + branch + diffs + model + ctx gauge
  #       line 2 = c gauge + reset | w gauge + reset | ext
  line1="${C_RED}${project_name}${R}"
  [ -n "$git_branch" ] && line1+="  ${C_GREEN}${git_branch}${R}"
  [ -n "$diff_str" ] && line1+=" ${C_AMBER}[${diff_str}]${R}"
  line1+="${sep}${C_PURPLE}${model_full}${R}"
  line1+="${sep}${C_MUTED}ctx:${R} $(bgauge "$ctx_pct" 8 context) $(cpct $ctx_pct context)"
  if $is_subscription_plan; then
    line2="${C_MUTED}5h:${R} $(bgauge "$current_pct" 6 budget) $(cpct $current_pct budget)"
    [ -n "$current_reset" ] && line2+=" ${C_MUTED}${current_reset}${R}"
    line2+="${sep}${C_MUTED}7d:${R} $(bgauge "$weekly_pct" 6 budget) $(cpct $weekly_pct budget)"
    [ -n "$weekly_reset_full" ] && line2+=" ${C_MUTED}${weekly_reset_full}${R}"
    if [ "$extra_enabled" = "true" ]; then
      line2+="${sep}${C_MUTED}extra${R} $(bgauge "$extra_pct" 6 budget) ${C_MUTED}${extra_remaining} left${R}"
    fi
  else
    line2="${C_MUTED}cost:${R} ${C_AMBER}${session_cost_fmt}${R}"
  fi
  line2+="$acct_sfx"
  printf '%b\n%b' "$line1" "$line2"

elif [ "$avail" -ge 88 ] && [ "$avail" -ge "$model_line_vis" ]; then
  # WIDE: line 1 = project + branch + model + ctx%
  #       line 2 = usage gauges + resets
  line1="${C_RED}${project_name}${R}"
  [ -n "$git_branch" ] && line1+="  ${C_GREEN}${git_branch}${R}"
  [ -n "$diff_str" ] && line1+=" ${C_AMBER}[${diff_str}]${R}"
  line1+="${sep}${C_PURPLE}${model_short}${R}"
  line1+="${sep}${C_MUTED}ctx:${R} $(cpct $ctx_pct context)"
  if $is_subscription_plan; then
    line2="${C_MUTED}5h:${R} $(bgauge "$current_pct" 6 budget) $(cpct $current_pct budget)"
    [ -n "$current_reset" ] && line2+=" ${C_MUTED}${current_reset}${R}"
    line2+="${sep}${C_MUTED}7d:${R} $(bgauge "$weekly_pct" 6 budget) $(cpct $weekly_pct budget)"
    [ -n "$weekly_reset" ] && line2+=" ${C_MUTED}${weekly_reset}${R}"
    if [ "$extra_enabled" = "true" ]; then
      line2+="${sep}${C_MUTED}ext:${R} $(bgauge "$extra_pct" 6 budget) ${C_MUTED}${extra_remaining} left${R}"
    fi
  else
    line2="${C_MUTED}cost:${R} ${C_AMBER}${session_cost_fmt}${R}"
  fi
  line2+="$acct_sfx"
  printf '%b\n%b' "$line1" "$line2"

elif [ "$avail" -ge 56 ]; then
  # COMPACT: line 1 = short project + branch + model_tiny + ctx gauge
  #          line 2 = c% + w% with gauges
  line1="${C_RED}${project_short}${R}"
  [ -n "$git_branch" ] && line1+="  ${C_GREEN}${git_branch}${R}"
  line1+="${sep}${C_PURPLE}${model_short}${R}"
  line1+="${sep}${C_MUTED}ctx:${R} $(bgauge "$ctx_pct" 8 context) $(cpct $ctx_pct context)"
  if $is_subscription_plan; then
    line2="${C_MUTED}5h:${R} $(bgauge "$current_pct" 6 budget) $(cpct $current_pct budget)"
    [ -n "$current_reset" ] && line2+=" ${C_MUTED}${current_reset}${R}"
    line2+="${sep}${C_MUTED}7d:${R} $(bgauge "$weekly_pct" 6 budget) $(cpct $weekly_pct budget)"
    if [ "$extra_enabled" = "true" ]; then
      line2+="${sep}${C_MUTED}ext:${R} $(bgauge "$extra_pct" 6 budget) ${C_MUTED}${extra_remaining} left${R}"
    fi
  else
    line2="${C_MUTED}cost:${R} ${C_AMBER}${session_cost_fmt}${R}"
  fi
  line2+="$acct_sfx"
  printf '%b\n%b' "$line1" "$line2"

elif [ "$avail" -ge 36 ]; then
  # NARROW: 1 line, short project + model_tiny + percentages
  line="${C_RED}${project_short}${R}"
  [ -n "$git_branch" ] && line+="  ${C_GREEN}${git_branch}${R}"
  line+="${sep}${C_PURPLE}${model_short}${R}"
  line+="${sep}${C_MUTED}ctx:${R} $(cpct $ctx_pct context)"
  if $is_subscription_plan; then
    line+="${sep}${C_MUTED}5h:${R} $(cpct $current_pct budget)"
    line+="${sep}${C_MUTED}7d:${R} $(cpct $weekly_pct budget)"
  else
    line+="${sep}${C_AMBER}${session_cost_fmt}${R}"
  fi
  line+="$acct_sfx"
  printf '%b' "$line"

else
  # ULTRACOMPACT: branch + model_tiny + percentages, no dividers
  line=""
  [ -n "$git_branch" ] && line+="${C_GREEN}${git_branch}${R}" || line+="${C_RED}${project_short}${R}"
  line+=" ${C_PURPLE}${model_word}${R}"
  line+=" ${C_MUTED}ctx:${R}$(cpct $ctx_pct context)"
  if $is_subscription_plan; then
    line+=" ${C_MUTED}5h:${R}$(cpct $current_pct budget)"
    line+=" ${C_MUTED}7d:${R}$(cpct $weekly_pct budget)"
  else
    line+=" ${C_AMBER}${session_cost_fmt}${R}"
  fi
  printf '%b' "$line"
fi

exit 0
