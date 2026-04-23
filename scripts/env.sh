# Source this to build MdEditor with Xcode's toolchain while
# global xcode-select still points at Command Line Tools.
#
# Usage:
#   source scripts/env.sh
#   xcodegen generate
#   xcodebuild -project MdEditor.xcodeproj -scheme MdEditor build
#
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

echo "DEVELOPER_DIR=$DEVELOPER_DIR"
xcode-select -p
xcrun --find swift
