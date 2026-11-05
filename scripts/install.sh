#!/bin/bash
# Builds Lanes and installs it to /Applications (or ~/Applications if that is not writable).
# Afterwards open Lanes from Finder or Launchpad like any other app.
# Usage: scripts/install.sh
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/make-app.sh

DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

# Quit a running copy so the new one can replace it.
pkill -x SystemMonitorApp 2>/dev/null || true
sleep 1

rm -rf "$DEST/Lanes.app"
cp -R build/Lanes.app "$DEST/Lanes.app"
# Remove the build copy so Spotlight and Launchpad show only one Lanes.
rm -rf build/Lanes.app
echo "Installed $DEST/Lanes.app"
echo "Open it from Finder or Launchpad. It lives in the menu bar (no Dock icon)."
