#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/generate-project.py
if [[ -n "${CI:-}" ]]; then git diff --exit-code -- AIBuddy.xcodeproj; fi
swift test --enable-code-coverage
xcodebuild -project AIBuddy.xcodeproj -scheme AIBuddy -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode \
  -resultBundlePath ".build/UITests-$(date +%s).xcresult" test
scripts/build-app.sh
