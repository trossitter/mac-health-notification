#!/usr/bin/env zsh
# mac_health.sh — Level 2 health monitor for Apple M1 Max / macOS Sonoma
# Runs via cron every 30 minutes; silent unless a threshold is breached.

LOG="${MAC_HEALTH_LOG:-$HOME/mac_health_log.txt}"

# ── Collect metrics ──────────────────────────────────────────────────────────

LOAD_RAW=$(sysctl -n vm.loadavg 2>/dev/null)
# vm.loadavg returns "{ 1min 5min 15min }" — grab the 1-min value
LOAD=$(echo "$LOAD_RAW" | awk '{print $2}')

# Free RAM in GB (pages * page_size / 1024^3)
PAGE_SIZE=$(pagesize)
FREE_PAGES=$(vm_stat | awk '/Pages free/ {gsub(/\./,"",$3); print $3}')
FREE_RAM=$(echo "scale=2; $FREE_PAGES * $PAGE_SIZE / 1073741824" | bc)

# Compressor size in GB
COMP_PAGES=$(vm_stat | awk '/Pages stored in compressor/ {gsub(/\./,"",$5); print $5}')
COMP_GB=$(echo "scale=2; $COMP_PAGES * $PAGE_SIZE / 1073741824" | bc)

# Swapouts since boot
SWAPOUTS=$(vm_stat | awk '/Swapouts/ {gsub(/\./,"",$2); print $2}')

# Docker
DOCKER_RUNNING=false
CONTAINER_COUNT=0
if pgrep -x "Docker Desktop" >/dev/null 2>&1 || pgrep -f "com.docker" >/dev/null 2>&1; then
    DOCKER_RUNNING=true
    CONTAINER_COUNT=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
fi

# Top 5 memory consumers (RSS in MB)
TOP5=$(ps -Ao pid,rss,comm -r 2>/dev/null | head -6 | tail -5 | \
    awk '{printf "  PID %-6s  %6.1f MB  %s\n", $1, $2/1024, $3}')

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# ── Evaluate thresholds ───────────────────────────────────────────────────────

REASONS=()

# Load avg > 6
if (( $(echo "$LOAD > ${THRESH_LOAD:-6}" | bc -l) )); then
    REASONS+=("load avg ${LOAD} > 6")
fi

# Free RAM < 4 GB
if (( $(echo "$FREE_RAM < ${THRESH_FREE_RAM:-4}" | bc -l) )); then
    REASONS+=("free RAM ${FREE_RAM} GB < 4 GB")
fi

# Compressor > 4 GB
if (( $(echo "$COMP_GB > ${THRESH_COMP:-4}" | bc -l) )); then
    REASONS+=("compressor ${COMP_GB} GB > 4 GB")
fi

# Swapouts > 0
if [[ "$SWAPOUTS" -gt 0 ]]; then
    REASONS+=("swapouts ${SWAPOUTS} > 0")
fi

# Silent exit if healthy
[[ ${#REASONS[@]} -eq 0 ]] && exit 0

# ── Build alert entry ─────────────────────────────────────────────────────────

REASON_STR=$(printf " • %s\n" "${REASONS[@]}")

DOCKER_STATUS="not running"
if [[ "$DOCKER_RUNNING" == true ]]; then
    DOCKER_STATUS="running — ${CONTAINER_COUNT} container(s) active"
fi

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
  Stop Docker+EMR  : emr-down
  Flush DNS cache  : sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
  Memory overview  : top -o mem
  View log         : open $LOG
════════════════════════════════════════════════════════
EOF
)

# ── Write log ─────────────────────────────────────────────────────────────────

echo "$ENTRY" >> "$LOG"

# ── macOS notification ────────────────────────────────────────────────────────

ALERT_TITLE="Mac Health Alert"
ALERT_BODY=$(printf "%s" "${REASONS[*]}" | tr '\n' ' ')

osascript <<APPLESCRIPT
set theMessage to "$ALERT_BODY"
set theLogPath to "$LOG"
display notification theMessage with title "$ALERT_TITLE" subtitle "See mac_health_log.txt for details" sound name "Basso"
APPLESCRIPT
