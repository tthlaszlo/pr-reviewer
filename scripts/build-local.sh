#!/bin/bash
# Fallback packaging with Command Line Tools; Xcode remains required for UI tests.
set -euo pipefail
cd "$(dirname "$0")/.."
arguments=(-c release)
if [[ -n "${SDKROOT:-}" ]]; then arguments+=(--sdk "$SDKROOT"); fi
swift build "${arguments[@]}"
bin_path="$(swift build "${arguments[@]}" --show-bin-path)"
app="$PWD/.build/local/AIBuddy.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_path/BuddyDesktop" "$app/Contents/MacOS/AIBuddy"
cp -R "$bin_path/AIBuddy_BuddyDesktop.bundle" "$app/Contents/Resources/"
python3 - "$app" <<'PY'
import os, plistlib, sys
from pathlib import Path
with open('Config/Info.plist', 'rb') as stream:
    info = plistlib.load(stream)
info['GitHubClientID'] = os.environ.get('GITHUB_CLIENT_ID', '')
with open(Path(sys.argv[1]) / 'Contents/Info.plist', 'wb') as stream:
    plistlib.dump(info, stream)
PY
codesign --force --deep --sign - "$app"
printf '\nBuilt: %s\n' "$app"
