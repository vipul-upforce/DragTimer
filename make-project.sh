#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen not found. Install with: brew install xcodegen"
  exit 1
fi
xcodegen generate
printf '\nCreated DragTimer.xcodeproj\n'
