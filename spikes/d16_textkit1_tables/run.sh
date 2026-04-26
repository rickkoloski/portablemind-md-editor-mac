#!/bin/bash
# D16 spike — TextKit 1 tables.
# Build the SwiftPM executable, wrap it in a .app bundle so macOS
# treats it as a real app (window activation reliable), and launch.

set -euo pipefail

SPIKE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SPIKE_DIR"

echo "Building..."
swift build

EXEC_PATH=".build/debug/D16Spike"
if [[ ! -x "$EXEC_PATH" ]]; then
    echo "ERROR: executable not found at $EXEC_PATH" >&2
    exit 1
fi

APP_DIR="D16Spike.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$EXEC_PATH" "$APP_DIR/Contents/MacOS/D16Spike"

cat > "$APP_DIR/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>D16Spike</string>
    <key>CFBundleIdentifier</key>
    <string>com.portablemind.d16spike</string>
    <key>CFBundleName</key>
    <string>D16 TextKit 1 Tables Spike</string>
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
echo "Logs to stderr / Console.app filter for 'D16'."
