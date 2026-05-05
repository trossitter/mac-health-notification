# mac-health-monitor

A lightweight, zero-dependency macOS health monitor that runs silently in the background and fires a native notification — with sound — the moment your machine crosses a memory or load threshold. Nothing is written to disk unless a threshold is actually breached.

Designed for developer machines that run long-lived workloads (Docker stacks, ML training, video renders) and need a low-overhead early-warning system.

---

## What it monitors

| Metric | Default threshold | Why it matters |
|---|---|---|
| 1-min load average | > 6 | Sustained CPU saturation across all cores |
| Free RAM | < 4 GB | Imminent paging / compressor pressure |
| VM compressor size | > 4 GB | macOS is actively compressing RAM — swap is next |
| Swapouts since boot | > 0 | Any swap write is a performance cliff on Apple Silicon |
| Docker Desktop | status + container count | Reported in every alert (no threshold) |

When **all** metrics are healthy the script exits silently — no output, no log write, no notification.

When **any** threshold is breached the script:

1. Appends a formatted alert block to `~/mac_health_log.txt`
2. Lists the top 5 memory consumers by RSS
3. Provides copy-paste quick-action commands
4. Fires a native macOS notification with the **Basso** alert sound

### Example log entry

```
════════════════════════════════════════════════════════
  HEALTH ALERT — 2026-05-05 03:30:00
════════════════════════════════════════════════════════
TRIGGERED BY:
 • free RAM 2.34 GB < 4 GB
 • compressor 5.10 GB > 4 GB
 • swapouts 142 > 0

SNAPSHOT:
  Load avg (1 min) : 3.81
  Free RAM         : 2.34 GB
  Compressor       : 5.10 GB
  Swapouts         : 142
  Docker           : running — 7 container(s) active

TOP 5 MEMORY CONSUMERS:
  PID 1823    19324.0 MB  com.docker.hyperkit
  PID 812      3201.5 MB  firefox
  PID 2201      892.3 MB  Xcode
  PID 441       741.0 MB  mds_stores
  PID 3310      612.8 MB  python3

QUICK ACTIONS:
  Stop Docker      : docker stop $(docker ps -q) && osascript -e 'quit app "Docker Desktop"'
  Flush DNS cache  : sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
  Memory overview  : top -o mem
  View log         : open ~/mac_health_log.txt
════════════════════════════════════════════════════════
```

---

## Requirements

- **macOS** Ventura 13+ (tested on Sonoma 14)
- **zsh** (default shell since macOS Catalina)
- **bc** — arbitrary-precision calculator, used for floating-point comparisons

  ```zsh
  # Check if bc is present (it usually is on macOS)
  which bc

  # Install via Homebrew if missing
  brew install bc
  ```

- Standard macOS utilities: `vm_stat`, `sysctl`, `pagesize`, `ps`, `osascript` — all present by default
- No Python, no Homebrew packages beyond `bc`, no third-party dependencies

---

## Installation

```zsh
git clone https://github.com/YOUR_USERNAME/mac-health-monitor.git
cd mac-health-monitor
zsh install.sh
```

`install.sh` will:

1. Copy `mac_health.sh` to `~/scripts/mac_health.sh`
2. Set executable permissions
3. Add a cron job: `*/30 * * * *` (every 30 minutes, idempotent)

### First-run permissions

macOS may prompt for two permissions the first time cron fires:

- **Notifications** — needed to display the alert banner
- **Full Disk Access** — needed if your log path is outside `~/Library`

Grant both in **System Settings → Privacy & Security**.

### Test it immediately

```zsh
zsh ~/scripts/mac_health.sh
```

If all thresholds are healthy, the script exits silently (correct behaviour). To force a visible test, temporarily lower a threshold:

```zsh
THRESH_FREE_RAM=999 zsh ~/scripts/mac_health.sh
```

---

## Configuration

Thresholds are plain variables at the top of `mac_health.sh` — edit them before installing, or after:

```zsh
# Inside mac_health.sh
THRESH_LOAD=6        # 1-min load average
THRESH_FREE_RAM=4    # GB
THRESH_COMP=4        # GB
THRESH_SWAPOUTS=0    # any swap = alert
```

The log path can be overridden at runtime via the `MAC_HEALTH_LOG` environment variable:

```zsh
MAC_HEALTH_LOG=/tmp/test.log zsh ~/scripts/mac_health.sh
```

---

## Uninstall

```zsh
# Remove the cron job
crontab -l | grep -v mac_health | crontab -

# Remove the script
rm ~/scripts/mac_health.sh

# Optionally remove the log
rm ~/mac_health_log.txt
```

---

## How it works

The script uses only macOS-native commands:

- `sysctl vm.loadavg` — load averages from the kernel
- `vm_stat` — virtual memory statistics (free pages, compressor pages, swapouts)
- `pagesize` — hardware page size in bytes (16 KB on Apple Silicon)
- `ps -Ao pid,rss,comm -r` — process list sorted by RSS
- `osascript` — AppleScript bridge for native notifications

All floating-point math is handled by `bc` to avoid bash integer rounding.

---

## License

MIT
