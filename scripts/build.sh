#!/bin/bash
# Builds "build/Unified Messenger.app" (ad-hoc signed). Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Unified Messenger.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 6 -target arm64-apple-macosx14.0 Sources/Core/*.swift Sources/App/*.swift \
  -o "$APP/Contents/MacOS/UnifiedMessenger"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --deep -s - "$APP"

if [[ "${1:-}" == "--install" ]]; then
  osascript -e 'quit app "Unified Messenger"' >/dev/null 2>&1 || true
  rm -rf "/Applications/Unified Messenger.app"
  cp -R "$APP" "/Applications/Unified Messenger.app"
  echo "Installed /Applications/Unified Messenger.app"
fi
echo "Built $APP"
