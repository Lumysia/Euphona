#!/bin/bash
# Launches the Mac debug build with the given arguments and saves every Euphona window to
# .build/shots/mac/<name>-<n>.png. It quits a running Euphona first, and seeds no demo data: on Mac the
# store is the person's real, iCloud-synced history.
# Usage: tools/screenshots/capture_mac.sh <name> [launch arguments...]   e.g. capture_mac.sh settings -demo_screen settings
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
APP="$ROOT/.build/DerivedData/Build/Products/Debug/Euphona.app"
OUT="$ROOT/.build/shots/mac"
NAME=$1; shift
mkdir -p "$OUT"

osascript -e 'tell application id "net.lumysia.Euphona" to quit' 2>/dev/null || true
for _ in $(seq 1 5); do pgrep -f "Euphona.app/Contents/MacOS/Euphona" >/dev/null || break; sleep 1; done
# An open sheet can hold up quitting; a second launch would then only bring the old instance forward.
pkill -f "Euphona.app/Contents/MacOS/Euphona" 2>/dev/null && sleep 1 || true
open "$APP" --args "$@"
sleep "${WAIT:-6}"

n=0
swift "$ROOT/tools/screenshots/mac_windows.swift" Euphona | while read -r id size title; do
  n=$((n + 1))
  screencapture -x -o -l "$id" "$OUT/$NAME-$n.png"
  echo "$OUT/$NAME-$n.png $size $title"
done
