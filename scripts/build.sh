#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD="$ROOT/.build-app"
DEST="${1:-$ROOT/dist/Next Up.app}"
APP="$BUILD/Next Up.app"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/dist"

swiftc -parse-as-library -O \
  -framework SwiftUI -framework AppKit -framework Charts -framework Security \
  "$ROOT"/Sources/NextUp/*.swift \
  -o "$APP/Contents/MacOS/NextUp"

cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
swift "$ROOT/scripts/render_icon.swift" "$BUILD/AppIcon.png"
cp "$BUILD/AppIcon.png" "$APP/Contents/Resources/AppIcon.png"

rm -rf "$DEST"
mkdir -p "${DEST:h}"
ditto "$APP" "$DEST"
codesign --force --deep --sign - "$DEST"
echo "$DEST"
