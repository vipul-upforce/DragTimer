#!/bin/bash
# Build a distributable zip for GitHub Releases (local use).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' DragTimer/Info.plist 2>/dev/null || echo 1.0.0)}"
./make-project.sh
./build-app.sh
codesign -s - --force --deep dist/DragTimer.app
export COPYFILE_DISABLE=1
OUT="dist/DragTimer-${VERSION}-macos.zip"
rm -f "$OUT"
(
  cd dist
  ditto -c -k --keepParent --norsrc --noextattr --noqtn DragTimer.app "DragTimer-${VERSION}-macos.zip"
)
ls -lh "$OUT"
echo "Packaged: $OUT"
