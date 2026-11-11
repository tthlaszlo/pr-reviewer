#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-Release}"
# Xcode resolves the optional Config/Local.xcconfig. A CLI value overrides it.
arguments=("ARCHS=arm64")
if [[ -n "${GITHUB_CLIENT_ID:-}" ]]; then arguments+=("GITHUB_CLIENT_ID=$GITHUB_CLIENT_ID"); fi
xcodebuild -project AIBuddy.xcodeproj -scheme AIBuddy -configuration "$configuration" \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode \
  "${arguments[@]}" build
printf '\nBuilt: %s/.build/xcode/Build/Products/%s/AIBuddy.app\n' "$PWD" "$configuration"
