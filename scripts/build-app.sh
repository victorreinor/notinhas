#!/usr/bin/env bash
# Builds build.noindex/Notinhas.app: release, universal (Apple Silicon + Intel), ad-hoc signed.
# No Xcode needed, just the Command Line Tools (xcode-select --install).
# The ".noindex" suffix keeps Spotlight from listing this copy next to /Applications/Notinhas.app.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build.noindex/Notinhas.app"
ARCHS=(--arch arm64 --arch x86_64)

swift build -c release "${ARCHS[@]}" --product Notinhas
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

if [ ! -f Resources/AppIcon.icns ]; then
  rm -rf build.noindex/AppIcon.iconset
  swift scripts/make-icon.swift build.noindex/AppIcon.iconset
  iconutil -c icns build.noindex/AppIcon.iconset -o Resources/AppIcon.icns
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Notinhas" "$APP/Contents/MacOS/Notinhas"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

echo "Built $APP"
