#!/bin/bash
# Mac App Store screenshots for one app language: each main-window tab and the analysis window, with
# demo history, set on a 16:10 canvas (tools/screenshots/mac_store_frame.swift). Saved under
# .build/shots/mac-<language>/. It seeds demo data, so it runs only in CI, where the Mac has no history.
# Usage: tools/screenshots/store_mac.sh <language>   (build the Mac app first)
set -euo pipefail
[ -n "${CI:-}" ] || { echo "store_mac.sh seeds demo data and runs only in CI" >&2; exit 1; }
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
LANGUAGE=$1
APP="$ROOT/.build/DerivedData/Build/Products/Debug/Euphona.app"
AUDIO="$ROOT/Packages/EuphonaKit/Tests/EuphonaKitTests/Fixtures"
OUT="$ROOT/.build/shots/mac-$LANGUAGE"
RAW="$OUT/raw"
mkdir -p "$RAW"
# Use the sharpest display mode the machine offers: a HiDPI mode gives 2x captures for the 2880x1800
# canvas, otherwise the largest mode keeps the window at its full default size.
if command -v displayplacer >/dev/null || brew install -q jakehilborn/jakehilborn/displayplacer >/dev/null 2>&1; then
  mode=$(displayplacer list | python3 -c "import re, sys
text = sys.stdin.read()
screen = re.search(r'Persistent screen id: (\S+)', text).group(1)
modes = [(int(n), int(w), 'scaling:on' in line) for line, n, w in re.findall(r'(mode (\d+): res:(\d+)x\d+[^\n]*)', text)]
number, _, _ = max(modes, key=lambda m: (m[2] and m[1] >= 1440, m[1]))
print(f'id:{screen} mode:{number}')" 2>/dev/null) && displayplacer "$mode" || true
fi
system_profiler SPDisplaysDataType | grep -E 'Resolution|UI Looks like' || true

defaults delete net.lumysia.Euphona 2>/dev/null || true
rm -rf ~/Library/Containers/net.lumysia.Euphona "$HOME/Library/Application Support/default.store"*

shot() {
  local name=$1; shift
  osascript -e 'tell application id "net.lumysia.Euphona" to quit' 2>/dev/null || true
  for _ in $(seq 1 5); do pgrep -f "Euphona.app/Contents/MacOS/Euphona" >/dev/null || break; sleep 1; done
  pkill -f "Euphona.app/Contents/MacOS/Euphona" 2>/dev/null && sleep 1 || true
  open "$APP" --args -onboarding 4 -demo_audio "$AUDIO" -AppleLanguages "($LANGUAGE)" -AppleLocale "$LANGUAGE" "$@"
  sleep "${WAIT:-10}"
  # The frontmost Euphona window: the analysis window when it is open, the main window otherwise.
  local id
  id=$(swift "$ROOT/tools/screenshots/mac_windows.swift" Euphona | head -1 | cut -d' ' -f1)
  screencapture -x -l "$id" "$RAW/$name.png"
  swift "$ROOT/tools/screenshots/mac_store_frame.swift" "$RAW/$name.png" "$OUT/$name.png"
  echo "$OUT/$name.png"
}

WAIT=40 shot today
for screen in progress coach practice analysis; do
  shot "$screen" -demo_screen "$screen"
done
osascript -e 'tell application id "net.lumysia.Euphona" to quit' 2>/dev/null || true
