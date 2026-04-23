# Source this to build the spike with Xcode's toolchain while
# global xcode-select still points at Command Line Tools.
#
# Usage:
#   cd spikes/d01_textkit2
#   source scripts/env.sh
#   swift build
#
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

# Confirm which toolchain is active
echo "DEVELOPER_DIR=$DEVELOPER_DIR"
xcode-select -p
xcrun --find swift
