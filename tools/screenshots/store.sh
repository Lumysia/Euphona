#!/bin/bash
# App Store screenshots for one app language on the iPhone and iPad sizes App Store Connect asks for
# (6.9-inch iPhone, 13-inch iPad), saved under .build/shots/<device>-<language>/.
# Usage: tools/screenshots/store.sh <language>   e.g. store.sh zh-Hans   (build the simulator app first)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export LANGUAGE=$1
export SCREENS=${SCREENS:-"result analysis coach lesson-intro practice progress resonance rules"}
DEVICES=("iPhone 17 Pro Max" "iPad Pro 13-inch (M5)")

# Creates the simulator on the newest iOS runtime when the machine has the device type but no device.
ensure_device() {
  local name=$1 type runtime
  xcrun simctl list devices available -j | python3 -c "import json, sys
d = json.load(sys.stdin)['devices']
sys.exit(0 if any(x['name'] == sys.argv[1] for r in d for x in d[r]) else 1)" "$name" && return
  type=$(xcrun simctl list devicetypes -j | python3 -c "import json, sys
types = json.load(sys.stdin)['devicetypes']
match = [t['identifier'] for t in types if t['name'] == sys.argv[1]]
if not match: sys.exit('no device type ' + sys.argv[1] + '; have: ' + ', '.join(t['name'] for t in types))
print(match[0])" "$name")
  runtime=$(xcrun simctl list runtimes available -j | python3 -c "import json, sys
print([r['identifier'] for r in json.load(sys.stdin)['runtimes'] if r['platform'] == 'iOS'][-1])")
  xcrun simctl create "$name" "$type" "$runtime" >/dev/null
}

for device in "${DEVICES[@]}"; do
  ensure_device "$device"
  "$ROOT/tools/screenshots/capture.sh" "$device"
done
