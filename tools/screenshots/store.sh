#!/bin/bash
# App Store screenshots in the given app languages on the iPhone and iPad sizes App Store Connect asks
# for (6.9-inch iPhone, 13-inch iPad), saved under .build/shots/<device>-<language>/.
# Usage: tools/screenshots/store.sh <language>...   e.g. store.sh en zh-Hans   (build the simulator app first)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export SCREENS=${SCREENS:-"result analysis coach lesson-intro practice progress resonance rules"}
DEVICES=("iPhone 17 Pro Max" "iPad Pro 13-inch (M5)")

# The device's UDID, creating it on the newest iOS runtime that supports it when the machine has none.
device_udid() {
  local name=$1 type runtime
  if ! xcrun simctl list devices available -j | python3 -c "import json, sys
d = json.load(sys.stdin)['devices']
sys.exit(0 if any(x['name'] == sys.argv[1] for r in d for x in d[r]) else 1)" "$name"; then
    type=$(xcrun simctl list devicetypes -j | python3 -c "import json, sys
types = json.load(sys.stdin)['devicetypes']
match = [t['identifier'] for t in types if t['name'] == sys.argv[1]]
if not match: sys.exit('no device type ' + sys.argv[1] + '; have: ' + ', '.join(t['name'] for t in types))
print(match[0])" "$name")
    runtime=$(xcrun simctl list runtimes available -j | python3 -c "import json, sys
runtimes = [r for r in json.load(sys.stdin)['runtimes']
            if r['platform'] == 'iOS' and any(t['identifier'] == sys.argv[1] for t in r.get('supportedDeviceTypes', []))]
print(max(runtimes, key=lambda r: [int(p) for p in r['version'].split('.')])['identifier'])" "$type")
    xcrun simctl create "$name" "$type" "$runtime" >/dev/null
  fi
  xcrun simctl list devices available -j | python3 -c "import json, sys
d = json.load(sys.stdin)['devices']
print([x['udid'] for r in d for x in d[r] if x['name'] == sys.argv[1]][0])" "$1"
}

# Boot every device once; capture.sh leaves a simulator it did not boot running.
UDIDS=()
for device in "${DEVICES[@]}"; do
  udid=$(device_udid "$device")
  UDIDS+=("$udid")
  xcrun simctl boot "$udid" 2>/dev/null || true
done
trap 'for udid in "${UDIDS[@]}"; do xcrun simctl shutdown "$udid" 2>/dev/null || true; done' EXIT

for language in "$@"; do
  for device in "${DEVICES[@]}"; do
    LANGUAGE=$language "$ROOT/tools/screenshots/capture.sh" "$device"
  done
done
