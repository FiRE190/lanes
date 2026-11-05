#!/bin/bash
# Renders docs/menubar.png and docs/panel.png from demo data (no real system data).
# Usage: scripts/make-screenshots.sh
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product SystemMonitorApp
LANES_SCREENSHOT_DIR=docs "$(swift build -c release --show-bin-path)/SystemMonitorApp"
ls -la docs/*.png
