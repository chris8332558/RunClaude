#!/bin/bash
set -euo pipefail

# create-release.sh
#
# Builds a release .app bundle, zips it, and computes the SHA256
# needed for the Homebrew cask formula.
#
# Usage:
#   ./Scripts/create-release.sh [version]
#
# Example:
#   ./Scripts/create-release.sh 0.2.0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION="${1:-0.2.0}"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/RunClaude.app"
ZIP_NAME="RunClaude-v${VERSION}.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"

echo "=== RunClaude Release Builder ==="
echo "Version: $VERSION"
echo ""

# Step 1: Build release
echo "[1/4] Building release..."
cd "$PROJECT_DIR"
swift build -c release 2>&1
BINARY=".build/release/RunClaude"
echo "   Binary: $BINARY"

# Step 2: Assemble .app bundle
echo "[2/4] Assembling .app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BINARY" "$APP_DIR/Contents/MacOS/RunClaude"

# Update version in Info.plist
sed "s/0.1.0/$VERSION/g" "$PROJECT_DIR/Resources/Info.plist" > "$APP_DIR/Contents/Info.plist"
echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"

# Step 3: Code sign
echo "[3/4] Code signing..."
codesign --force --sign - "$APP_DIR" 2>&1 || echo "   Warning: codesign failed (okay for local builds)"

# Step 4: Create zip
echo "[4/4] Creating release archive..."
cd "$BUILD_DIR"
rm -f "$ZIP_NAME"
zip -r -q "$ZIP_NAME" "RunClaude.app"

SHA256=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')
SIZE=$(stat -f%z "$ZIP_PATH" 2>/dev/null || stat -c%s "$ZIP_PATH")

echo ""
echo "=== Release Ready ==="
echo ""
echo "Archive: $ZIP_PATH"
echo "Size:    $SIZE bytes"
echo "SHA256:  $SHA256"
echo ""
echo "To publish:"
echo "  1. Create a GitHub release tagged v$VERSION"
echo "  2. Upload $ZIP_PATH as a release asset"
echo "  3. Update the Homebrew cask formula with the new SHA256"
echo ""
echo "Cask formula values:"
echo "  version \"$VERSION\""
echo "  sha256 \"$SHA256\""
