#!/bin/bash
set -euo pipefail

# Build RunClaude and assemble it into a macOS .app bundle.
#
# Usage:
#   ./Scripts/make-app.sh [release|debug]
#
# Output:
#   ./build/RunClaude.app

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG="${1:-debug}"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/RunClaude.app"

echo "=== RunClaude Build ==="
echo "Configuration: $CONFIG"
echo "Project: $PROJECT_DIR"
echo ""

# Step 1: Build with SwiftPM
echo "[1/3] Building with swift build..."
cd "$PROJECT_DIR"
if [ "$CONFIG" = "release" ]; then
    swift build -c release 2>&1
    BINARY_DIR=".build/release"
else
    swift build 2>&1
    BINARY_DIR=".build/debug"
fi

BINARY="$BINARY_DIR/RunClaude"
if [ ! -f "$BINARY" ]; then
    echo "Error: Binary not found at $BINARY"
    exit 1
fi
echo "   Built: $BINARY"

# Step 2: Assemble .app bundle
echo "[2/3] Assembling .app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP_DIR/Contents/MacOS/RunClaude"

# Copy Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# Create PkgInfo
echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"

echo "   Bundle: $APP_DIR"

# Step 3: Code sign (ad-hoc for local development)
echo "[3/3] Code signing (ad-hoc)..."
codesign --force --sign - "$APP_DIR" 2>&1 || echo "   Warning: codesign failed (okay for development)"

echo ""
echo "=== Done ==="
echo ""
echo "To run:"
echo "  open $APP_DIR"
echo ""
echo "To install:"
echo "  cp -r $APP_DIR /Applications/"
echo ""
echo "The app runs in the menu bar (no Dock icon)."
echo "Right-click the menu bar icon to quit."
