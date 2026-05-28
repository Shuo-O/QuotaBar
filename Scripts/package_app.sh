#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/build/QuotaBar.app"

cd "$ROOT"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/QuotaBar" "$APP_DIR/Contents/MacOS/QuotaBar"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp -R "$ROOT/Resources/Icons" "$APP_DIR/Contents/Resources/Icons"
chmod +x "$APP_DIR/Contents/MacOS/QuotaBar"

xattr -cr "$APP_DIR" >/dev/null 2>&1 || true
xattr -d com.apple.FinderInfo "$APP_DIR" >/dev/null 2>&1 || true
xattr -d "com.apple.fileprovider.fpfs#P" "$APP_DIR" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "$APP_DIR"
