#!/bin/bash
# Build + wrap the SwiftPM executable as a proper .app bundle so macOS
# gives it a real window. Without the bundle, window activation is flaky.

set -euo pipefail

SPIKE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SPIKE_DIR"

echo "Building..."
swift build

EXEC_PATH=".build/debug/D12Spike"
if [[ ! -x "$EXEC_PATH" ]]; then
    echo "ERROR: executable not found at $EXEC_PATH" >&2
    exit 1
fi

APP_DIR="D12Spike.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

cp "$EXEC_PATH" "$APP_DIR/Contents/MacOS/D12Spike"

cat > "$APP_DIR/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>D12Spike</string>
    <key>CFBundleIdentifier</key>
    <string>com.portablemind.d12spike</string>
    <key>CFBundleName</key>
    <string>D12 Cell Caret Spike</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "Launching $APP_DIR..."
open "$APP_DIR"
echo "Launched. Console logs go to system log; use Console.app to view if needed."
