#!/bin/bash
# Builds dist/ClaudeUsageBar.app (ad-hoc signed). Pass --install to copy it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP=dist/ClaudeUsageBar.app
swift build -c release
BIN="$(swift build -c release --show-bin-path)/ClaudeUsageBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeUsageBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    pkill -x ClaudeUsageBar 2>/dev/null || true
    rm -rf "$HOME/Applications/ClaudeUsageBar.app"
    cp -R "$APP" "$HOME/Applications/"
    echo "Installed to ~/Applications/ClaudeUsageBar.app"
fi
