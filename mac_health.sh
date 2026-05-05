#!/usr/bin/env zsh
# mac_health.sh — Level 2 health monitor for macOS
# Runs via cron every 30 minutes; silent unless a threshold is breached.
#
# Thresholds (edit to taste):
#   THRESH_LOAD     — 1-min load average
#   THRESH_FREE_RAM — free RAM floor in GB
#   THRESH_COMP     — VM compressor size ceiling in GB
#   THRESH_SWAPOUTS — swapouts since boot (0 = any swap triggers alert)

THRESH_LOAD=6
THRESH_FREE_RAM=4
THRESH_COMP=4
THRESH_SWAPOUTS=0

LOG="${MAC_HEALTH_LOG:-$HOME/mac_health_log.txt}"

# ── Collect metrics ──────────────────────────────────────────────────────────

LOAD_RAW=$(sysctl -n vm.loadavg 2>/dev/null)
LOAD=$(echo "$LOAD_RAW" | awk '{print $2}')

PAGE_SIZE=$(pagesize)
FREE_PAGES=$(vm_stat | awk '/Pages free/ {gsub(/\./,"",$3); print $3}')
FREE_RAM=$(echo "scale=2; $FREE_PAGES * $PAGE_SIZE / 1073741824" | bc)

COMP_PAGES=$(vm_stat | awk '/Pages stored in compressor/ {gsub(/\./,"",$5); print $5}')
COMP_GB=$(echo "scale=2; $COMP_PAGES * $PAGE_SIZE / 1073741824" | bc)

SWAPOUTS=$(vm_stat | awk '/Swapouts/ {gsub(/\./,"",$2); print $2}')

DOCKER_RUNNING=false
CONTAINER_COUNT=0
if pgrep -x "Docker Desktop" >/dev/null 2>&1 || pgrep -f "com.docker" >/dev/null 2>&1; then
    DOCKER_RUNNING=true
    CONTAINER_COUNT=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
fi

TOP5=$(ps -Ao pid,rss,comm -r 2>/dev/null | head -6 | tail -5 | \
    awk '{printf "  PID %-6s  %6.1f MB  %s\n", $1, $2/1024, $3}')

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# ── Evaluate thresholds ───────────────────────────────────────────────────────

REASONS=()

(( $(echo "$LOAD > $THRESH_LOAD" | bc -l) ))         && REASONS+=("load avg ${LOAD} > ${THRESH_LOAD}")
(( $(echo "$FREE_RAM < $THRESH_FREE_RAM" | bc -l) )) && REASONS+=("free RAM ${FREE_RAM} GB < ${THRESH_FREE_RAM} GB")
(( $(echo "$COMP_GB > $THRESH_COMP" | bc -l) ))      && REASONS+=("compressor ${COMP_GB} GB > ${THRESH_COMP} GB")
[[ "$SWAPOUTS" -gt "$THRESH_SWAPOUTS" ]]              && REASONS+=("swapouts ${SWAPOUTS} > ${THRESH_SWAPOUTS}")

[[ ${#REASONS[@]} -eq 0 ]] && exit 0

# ── Build alert entry ─────────────────────────────────────────────────────────

REASON_STR=$(printf " • %s\n" "${REASONS[@]}")

DOCKER_STATUS="not running"
[[ "$DOCKER_RUNNING" == true ]] && DOCKER_STATUS="running — ${CONTAINER_COUNT} container(s) active"

ENTRY=$(cat <<EOF

════════════════════════════════════════════════════════
  HEALTH ALERT — $TIMESTAMP
════════════════════════════════════════════════════════
TRIGGERED BY:
$REASON_STR

SNAPSHOT:
  Load avg (1 min) : $LOAD
  Free RAM         : ${FREE_RAM} GB
  Compressor       : ${COMP_GB} GB
  Swapouts         : $SWAPOUTS
  Docker           : $DOCKER_STATUS

TOP 5 MEMORY CONSUMERS:
$TOP5

QUICK ACTIONS:
  Stop Docker      : docker stop \$(docker ps -q) && osascript -e 'quit app "Docker Desktop"'
  Flush DNS cache  : sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
  Memory overview  : top -o mem
  View log         : open $LOG
════════════════════════════════════════════════════════
EOF
)

# ── Write log ─────────────────────────────────────────────────────────────────

echo "$ENTRY" >> "$LOG"

# ── macOS notification ────────────────────────────────────────────────────────

ALERT_BODY=$(printf "%s" "${REASONS[*]}" | tr '\n' ' ')

osascript <<APPLESCRIPT
display notification "$ALERT_BODY" with title "Mac Health Alert" subtitle "See mac_health_log.txt for details" sound name "Basso"
APPLESCRIPT
