#!/bin/bash
# Prints the CHANGELOG.md section of a version, for the release description.
# Usage: tools/ci/release_notes.sh 1.2.0   (fails if the version has no section)
set -euo pipefail
cd "$(dirname "$0")/../.."
VERSION=${1#v}
NOTES=$(awk -v version="$VERSION" '
  /^## / { inside = ($2 == version || $2 == "[" version "]"); next }
  inside { print }
' CHANGELOG.md | sed -e '/./,$!d')
if [ -z "$NOTES" ]; then
  echo "CHANGELOG.md has no section for $VERSION" >&2
  exit 1
fi
printf '%s\n' "$NOTES"
