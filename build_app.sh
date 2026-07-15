#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="ClaudeUsage.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
cp ".build/release/ClaudeUsage" "$APP/Contents/MacOS/ClaudeUsage"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
