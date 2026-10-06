#!/bin/bash
# Claude Code Status Line
# 3-line display: model/context/git, 5h rate limit, 7d rate limit

input=$(cat)

# ── JSON fields ──────────────────────────────────────────────────────────────
model=$(echo "$input" | jq -r '.model.display_name // ""')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')

# ── ANSI colors ───────────────────────────────────────────────────────────────
# #97C9C3 green  (0-49%)
# #E5C07B yellow (50-79%)
# #E06C75 red    (80-100%)
# #4A585C gray   (separators / dim labels)
COL_RESET='\033[0m'
COL_GREEN='\033[38;2;151;201;195m'
COL_YELLOW='\033[38;2;229;192;123m'
COL_RED='\033[38;2;224;108;117m'
COL_GRAY='\033[38;2;74;88;92m'
COL_SEP='\033[38;2;74;88;92m'   # separator │

# Return color escape for a given percentage (0-100)
pct_color() {
  local pct=$1
  if [ -z "$pct" ] || [ "$pct" = "null" ]; then
    printf '%s' "$COL_GRAY"
    return
  fi
  local ipct
  ipct=$(printf '%.0f' "$pct")
  if   [ "$ipct" -ge 80 ]; then printf '%s' "$COL_RED"
  elif [ "$ipct" -ge 50 ]; then printf '%s' "$COL_YELLOW"
  else                           printf '%s' "$COL_GREEN"
  fi
}

# Build a 10-segment progress bar  ▰▱
progress_bar() {
  local pct=$1
  local color=$2
  local filled=0
  if [ -n "$pct" ] && [ "$pct" != "null" ]; then
    filled=$(echo "$pct" | awk '{printf "%d", $1/10}')
    [ "$filled" -gt 10 ] && filled=10
  fi
  local bar=""
  local i=0
  while [ $i -lt 10 ]; do
    if [ $i -lt "$filled" ]; then
      bar="${bar}▰"
    else
      bar="${bar}▱"
    fi
    i=$((i+1))
  done
  printf '%b%s%b' "$color" "$bar" "$COL_RESET"
}

# ── Git diff stat (added/deleted lines) ──────────────────────────────────────
added=0
deleted=0
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  diff_stat=$(git -C "$cwd" -c core.hooksPath=/dev/null diff --cached --numstat 2>/dev/null)
  unstaged=$(git -C "$cwd" -c core.hooksPath=/dev/null diff --numstat 2>/dev/null)
  # sum added / deleted from staged + unstaged
  combined=$(printf '%s\n%s' "$diff_stat" "$unstaged")
  added=$(echo "$combined" | awk '{a+=$1} END {print (a==""?0:a)}')
  deleted=$(echo "$combined" | awk '{d+=$2} END {print (d==""?0:d)}')
fi

# ── Git branch ────────────────────────────────────────────────────────────────
branch=""
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" -c core.hooksPath=/dev/null symbolic-ref --short HEAD 2>/dev/null \
           || git -C "$cwd" -c core.hooksPath=/dev/null rev-parse --short HEAD 2>/dev/null)
fi

# ── Rate limit: fetch with cache ──────────────────────────────────────────────
CACHE_FILE="/tmp/claude-usage-cache.json"
CACHE_TTL=360

fetch_usage() {
  # Retrieve OAuth token from macOS Keychain
  local token
  token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
          | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('claudeAiOauth',{}).get('accessToken',''))" 2>/dev/null)
  [ -z "$token" ] && return 1

  local http_code resp
  http_code=$(curl -sf --max-time 5 -o /tmp/claude-usage-resp.tmp -w "%{http_code}" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
  resp=$(cat /tmp/claude-usage-resp.tmp 2>/dev/null)
  rm -f /tmp/claude-usage-resp.tmp
  # 401 = Pro plan: endpoint not supported
  [ "$http_code" = "401" ] && echo '{"_unavailable":true}' > "$CACHE_FILE" && return 1
  [ -z "$resp" ] && return 1

  echo "$resp" > "$CACHE_FILE"
  echo "$resp"
}

usage_json=""
if [ -f "$CACHE_FILE" ]; then
  age=$(( $(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0) ))
  if [ "$age" -lt "$CACHE_TTL" ]; then
    usage_json=$(cat "$CACHE_FILE")
  fi
fi
if [ -z "$usage_json" ]; then
  usage_json=$(fetch_usage)
fi

five_pct=""
seven_pct=""
five_resets=""
seven_resets=""
if [ -n "$usage_json" ]; then
  five_pct=$(echo "$usage_json"   | jq -r '.five_hour.utilization  // empty' 2>/dev/null)
  seven_pct=$(echo "$usage_json"  | jq -r '.seven_day.utilization  // empty' 2>/dev/null)
  five_resets_epoch=$(echo "$usage_json"  | jq -r '.five_hour.resets_at  // empty' 2>/dev/null)
  seven_resets_epoch=$(echo "$usage_json" | jq -r '.seven_day.resets_at  // empty' 2>/dev/null)

  # Fallback: try stdin rate_limits fields
  if [ -z "$five_pct" ]; then
    five_pct=$(echo "$input"  | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
    five_resets_epoch=$(echo "$input"  | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)
  fi
  if [ -z "$seven_pct" ]; then
    seven_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
    seven_resets_epoch=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty' 2>/dev/null)
  fi

  # Format reset times in Asia/Tokyo
  if [ -n "$five_resets_epoch" ] && [ "$five_resets_epoch" != "null" ]; then
    five_resets=$(TZ="Asia/Tokyo" date -r "$five_resets_epoch" "+%-I%p" 2>/dev/null \
                  | sed 's/AM/am/;s/PM/pm/')
    [ -z "$five_resets" ] && \
    five_resets=$(TZ="Asia/Tokyo" date -d "@$five_resets_epoch" "+%-I%p" 2>/dev/null \
                  | sed 's/AM/am/;s/PM/pm/')
    five_resets="Resets ${five_resets} (Asia/Tokyo)"
  fi
  if [ -n "$seven_resets_epoch" ] && [ "$seven_resets_epoch" != "null" ]; then
    seven_resets=$(TZ="Asia/Tokyo" date -r "$seven_resets_epoch" "+%b %-d at %-I%p" 2>/dev/null \
                   | sed 's/AM/am/;s/PM/pm/')
    [ -z "$seven_resets" ] && \
    seven_resets=$(TZ="Asia/Tokyo" date -d "@$seven_resets_epoch" "+%b %-d at %-I%p" 2>/dev/null \
                   | sed 's/AM/am/;s/PM/pm/')
    seven_resets="Resets ${seven_resets} (Asia/Tokyo)"
  fi
fi

# Convert utilization (0.0-1.0) to percentage if needed
to_pct() {
  local v=$1
  if [ -z "$v" ] || [ "$v" = "null" ]; then echo ""; return; fi
  # If value <= 1.0, multiply by 100
  echo "$v" | awk '{if($1<=1) printf "%.1f", $1*100; else printf "%.1f", $1}'
}

five_pct=$(to_pct "$five_pct")
seven_pct=$(to_pct "$seven_pct")

# ── Line 1: 🤖 Model │ 📊 ctx% │ ✏️ +add/-del │ 🔀 branch ─────────────────
ctx_display="n/a"
ctx_col="$COL_GRAY"
if [ -n "$used" ]; then
  ctx_display=$(printf '%.0f%%' "$used")
  ctx_col=$(pct_color "$used")
fi

diff_display=""
if [ "$added" -gt 0 ] || [ "$deleted" -gt 0 ]; then
  diff_display="${COL_GREEN}+${added}${COL_RESET}${COL_GRAY}/${COL_RESET}${COL_RED}-${deleted}${COL_RESET}"
else
  diff_display="${COL_GRAY}+0/-0${COL_RESET}"
fi

branch_display="${COL_GRAY}(no git)${COL_RESET}"
[ -n "$branch" ] && branch_display="${COL_GREEN}${branch}${COL_RESET}"

printf '🤖 %b%s%b %b│%b 📊 %b%s%b %b│%b ✏️  %b %b│%b 🔀 %b\n' \
  "$COL_GREEN" "$model" "$COL_RESET" \
  "$COL_SEP" "$COL_RESET" \
  "$ctx_col" "$ctx_display" "$COL_RESET" \
  "$COL_SEP" "$COL_RESET" \
  "$diff_display" \
  "$COL_SEP" "$COL_RESET" \
  "$branch_display"

# ── Lines 2 & 3: rate limits ──────────────────────────────────────────────────
print_rate_line() {
  local label=$1   # e.g. "5h" or "7d"
  local pct=$2     # percentage string e.g. "13.0"
  local resets=$3  # e.g. "Resets 4pm (Asia/Tokyo)"

  if [ -z "$pct" ]; then
    local icon="⏱"
    [ "$label" = "7d" ] && icon="📅"
    printf '%b%s %s  —%b\n' "$COL_GRAY" "$icon" "$label" "$COL_RESET"
    return
  fi

  local ipct
  ipct=$(printf '%.0f' "$pct")
  local col
  col=$(pct_color "$ipct")
  local bar
  bar=$(progress_bar "$ipct" "$col")

  local resets_str=""
  [ -n "$resets" ] && resets_str="  ${COL_GRAY}${resets}${COL_RESET}"

  if [ "$label" = "5h" ]; then
    printf '⏱ %b%s%b  %b  %b%s%%%b%b\n' \
      "$COL_GRAY" "$label" "$COL_RESET" \
      "$bar" \
      "$col" "$ipct" "$COL_RESET" \
      "$resets_str"
  else
    printf '📅 %b%s%b  %b  %b%s%%%b%b\n' \
      "$COL_GRAY" "$label" "$COL_RESET" \
      "$bar" \
      "$col" "$ipct" "$COL_RESET" \
      "$resets_str"
  fi
}
