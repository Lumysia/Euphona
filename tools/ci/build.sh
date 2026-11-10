#!/bin/bash
# Builds the app without code signing, for CI and releases. Usage: tools/ci/build.sh "<xcodebuild destination>"
set -euo pipefail
cd "$(dirname "$0")/../.."
xcodebuild build \
  -project Euphona.xcodeproj \
  -scheme Euphona \
  -configuration Release \
  -destination "$1" \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  | xcbeautify --renderer github-actions
