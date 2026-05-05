#!/usr/bin/env zsh
# install.sh — installs mac_health.sh and registers the cron job

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
INSTALL_DIR="$HOME/scripts"
INSTALL_PATH="$INSTALL_DIR/mac_health.sh"
CRON_SCHEDULE="*/30 * * * *"
CRON_CMD="/bin/zsh $INSTALL_PATH"
CRON_ENTRY="$CRON_SCHEDULE $CRON_CMD"

# ── Preflight ─────────────────────────────────────────────────────────────────

if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: macOS required." >&2
    exit 1
fi

if ! command -v bc >/dev/null 2>&1; then
    echo "Error: 'bc' not found. Install via Homebrew: brew install bc" >&2
    exit 1
fi

# ── Install script ────────────────────────────────────────────────────────────

mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/mac_health.sh" "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"
echo "Installed: $INSTALL_PATH"

# ── Register cron job (idempotent) ────────────────────────────────────────────

EXISTING=$(crontab -l 2>/dev/null || true)

if echo "$EXISTING" | grep -qF "$INSTALL_PATH"; then
    echo "Cron job already present — skipping."
else
    (echo "$EXISTING"; echo "$CRON_ENTRY") | grep -v '^$' | crontab -
    echo "Cron job installed: $CRON_ENTRY"
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "Installation complete."
echo "  Script : $INSTALL_PATH"
echo "  Schedule: every 30 minutes"
echo "  Log     : \$HOME/mac_health_log.txt"
echo ""
echo "To test now:  zsh $INSTALL_PATH"
echo "To uninstall: crontab -l | grep -v mac_health | crontab -  &&  rm $INSTALL_PATH"
