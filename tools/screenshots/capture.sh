#!/bin/bash
# Installs the debug build on a simulator, seeds demo analyses from the package's test clips, and saves
# one screenshot per screen to .build/shots/<device>[-dark]/. Usage: tools/screenshots/capture.sh ["iPhone 17"]
# APPEARANCE=dark captures dark mode; SCREENS="progress result" limits the screens (today is the first launch);
# PALETTE=ocean uses another theme palette (saved to .build/shots/<device>-ocean/); LANGUAGE=de another
# app language (saved to .build/shots/<device>-de/).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DEVICE=${1:-iPhone 17}
APP="$ROOT/.build/DerivedData/Build/Products/Debug-iphonesimulator/Euphona.app"
AUDIO="$ROOT/Packages/EuphonaKit/Tests/EuphonaKitTests/Fixtures"
APPEARANCE=${APPEARANCE:-light}
OUT="$ROOT/.build/shots/${DEVICE// /-}"
if [ "$APPEARANCE" = dark ]; then OUT="$OUT-dark"; fi
PALETTE_ARGS=()
if [ -n "${PALETTE:-}" ]; then OUT="$OUT-$PALETTE"; PALETTE_ARGS=(-palette "$PALETTE"); fi
if [ -n "${LANGUAGE:-}" ]; then OUT="$OUT-$LANGUAGE"; PALETTE_ARGS+=(-AppleLanguages "($LANGUAGE)" -AppleLocale "$LANGUAGE"); fi
BUNDLE=net.lumysia.Euphona

UDID=$(xcrun simctl list devices available -j | python3 -c "import json,sys; d=json.load(sys.stdin)['devices']; print([x['udid'] for r in d for x in d[r] if x['name']=='$DEVICE'][0])")
# Boot the simulator if needed, and shut it down again at the end if this script booted it.
if xcrun simctl list devices booted | grep -q "$UDID"; then
  WAS_BOOTED=1
else
  WAS_BOOTED=0
  xcrun simctl boot "$UDID"
fi
trap 'xcrun simctl status_bar "$UDID" clear; [ "$WAS_BOOTED" = 1 ] || xcrun simctl shutdown "$UDID"' EXIT
xcrun simctl bootstatus "$UDID" -b >/dev/null
# The status bar Apple uses in its own screenshots, so every shot shows the same clean one.
xcrun simctl status_bar "$UDID" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100
xcrun simctl ui "$UDID" appearance "$APPEARANCE"
xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant microphone "$BUNDLE" 2>/dev/null || true
mkdir -p "$OUT"
# The system briefly expands the Dynamic Island when a screen starts sound; on iPhone, a shot is taken
# again a few seconds later while it shows.
ISLAND=""
if [[ $DEVICE == iPhone* && $APPEARANCE == light ]]; then
  ISLAND="$ROOT/.build/island_open"
  [ -x "$ISLAND" ] || swiftc -O -o "$ISLAND" "$ROOT/tools/screenshots/island_open.swift"
fi

shot() {
  local name=$1; shift
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE" -onboarding 4 -demo_audio "$AUDIO" ${PALETTE_ARGS[@]+"${PALETTE_ARGS[@]}"} "$@" >/dev/null
  sleep "${WAIT:-12}"
  for _ in 1 2 3 4 5 6; do
    xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null 2>&1
    if [ -z "$ISLAND" ] || ! "$ISLAND" "$OUT/$name.png"; then break; fi
    sleep 4
  done
  echo "$(date +%T) $OUT/$name.png"
}

# The first launch seeds the demo history; Today is shot again at the end, when a slow machine has
# surely finished seeding.
WAIT=25 shot today
for screen in ${SCREENS:-practice progress coach lesson lesson-intro analysis result rules pitch timbre resonance spectrum piano quality settings history}; do
  shot "$screen" -demo_screen "$screen"
done
shot today
xcrun simctl ui "$UDID" appearance light
