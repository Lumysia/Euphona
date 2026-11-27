#!/bin/bash
# App Store screenshots for one app language on the iPhone and iPad sizes App Store Connect asks for
# (6.9-inch iPhone, 13-inch iPad), saved under .build/shots/<device>-<language>/.
# Usage: tools/screenshots/store.sh <language>   e.g. store.sh zh-Hans   (build the simulator app first)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export LANGUAGE=$1
export SCREENS=${SCREENS:-"result analysis coach lesson-intro practice progress resonance rules"}
for device in "iPhone 17 Pro Max" "iPad Pro 13-inch (M5)"; do
  "$ROOT/tools/screenshots/capture.sh" "$device"
done
