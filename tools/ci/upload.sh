#!/bin/bash
# Archives the app for one platform, signs it for App Store distribution and uploads it to App Store
# Connect, where it appears in TestFlight and can be submitted for review.
# Usage: tools/ci/upload.sh <iOS|macOS> <build number>
# Needs an App Store Connect API key with the Admin role (cloud-managed signing creates the
# certificates and profiles): ASC_KEY_PATH (the .p8 file), ASC_KEY_ID, ASC_ISSUER_ID.
set -euo pipefail
cd "$(dirname "$0")/../.."
platform=$1
build=$2
work="${RUNNER_TEMP:-.build}/upload-$platform"
auth=(-allowProvisioningUpdates
      -authenticationKeyPath "$ASC_KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")
rm -rf "$work"
mkdir -p "$work"

xcodebuild archive \
  -project Euphona.xcodeproj \
  -scheme Euphona \
  -configuration Release \
  -destination "generic/platform=$platform" \
  -archivePath "$work/Euphona.xcarchive" \
  CURRENT_PROJECT_VERSION="$build" \
  "${auth[@]}" \
  | xcbeautify --renderer github-actions

# ONNX Runtime ships a static library wrapped as a .framework. It is already linked into the app
# binary, but Xcode still copies the bundle into the app, and App Store Connect rejects that copy
# (ITMS-90208). Export re-signs the app, so removing it here is safe.
app="$work/Euphona.xcarchive/Products/Applications/Euphona.app"
rm -rf "$app/Frameworks/onnxruntime.framework" "$app/Contents/Frameworks/onnxruntime.framework"

xcodebuild -exportArchive \
  -archivePath "$work/Euphona.xcarchive" \
  -exportOptionsPlist tools/ci/ExportOptions.plist \
  -exportPath "$work/export" \
  "${auth[@]}"
