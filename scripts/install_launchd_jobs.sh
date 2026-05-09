#!/bin/bash
# install_launchd_jobs.sh — convert the 13 cron jobs to macOS launchd plists.
# Idempotent. Reads from $OVERLAY/launchd/*.plist if present, otherwise
# generates them from the cron registry via cron_to_launchd.py.
set -euo pipefail

OVERLAY="${HOME}/supa-work/Mejia-Supa-Hermes-Overlay"
PLIST_SRC="${OVERLAY}/launchd"
LA_DIR="${HOME}/Library/LaunchAgents"

mkdir -p "$LA_DIR"

# Generate plists from cron registry if helper exists.
if [[ -f "$OVERLAY/scripts/cron_to_launchd.py" ]]; then
  python3 "$OVERLAY/scripts/cron_to_launchd.py" --out "$PLIST_SRC" || true
fi

if [[ ! -d "$PLIST_SRC" ]]; then
  echo "❌ no launchd plists at $PLIST_SRC" >&2
  exit 1
fi

count=0
for plist in "$PLIST_SRC"/*.plist; do
  [[ -e "$plist" ]] || continue
  fname="$(basename "$plist")"
  cp "$plist" "$LA_DIR/$fname"
  # Unload first (ignore errors if not loaded), then load.
  launchctl unload "$LA_DIR/$fname" 2>/dev/null || true
  launchctl load -w "$LA_DIR/$fname"
  count=$((count + 1))
done

echo "✅ loaded $count launchd jobs into $LA_DIR"

if [[ $count -lt 13 ]]; then
  echo "⚠️  expected 13 jobs, got $count — review $PLIST_SRC" >&2
fi
