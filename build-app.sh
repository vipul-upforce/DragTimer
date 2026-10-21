#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p dist
xcodebuild \
  -project DragTimer.xcodeproj \
  -scheme DragTimer \
  -configuration Release \
  -derivedDataPath .build \
  CODE_SIGNING_ALLOWED=NO \
  build
rm -rf dist/DragTimer.app
cp -R .build/Build/Products/Release/DragTimer.app dist/DragTimer.app
printf '\nBuilt: %s/dist/DragTimer.app\n' "$PWD"
