#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PRODUCT_NAME="MXLightkeeperApp"
APP_NAME="MXLightkeeper"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST_SOURCE="$ROOT_DIR/Packaging/Info.plist"
ICNS_SOURCE="$ROOT_DIR/Packaging/AppIcon.icns"

swift build -c release --arch arm64 --arch x86_64 --product "$PRODUCT_NAME"

EXECUTABLE_SOURCE="$(swift build -c release --arch arm64 --arch x86_64 --product "$PRODUCT_NAME" --show-bin-path)/$PRODUCT_NAME"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE_SOURCE" "$MACOS_DIR/$PRODUCT_NAME"
cp "$PLIST_SOURCE" "$CONTENTS_DIR/Info.plist"
cp "$ICNS_SOURCE" "$RESOURCES_DIR/AppIcon.icns"

codesign --force --deep --sign - "$APP_DIR"

print "Built universal app bundle: $APP_DIR"
lipo -info "$MACOS_DIR/$PRODUCT_NAME"
