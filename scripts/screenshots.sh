#!/usr/bin/env bash
# Regenerates the README images in docs/images by rendering real note views offscreen
# (works without Screen Recording permission). Run it after any visual change.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build --product Notinhas
mkdir -p docs/images
NOTINHAS_SNAPSHOT_DIR="$PWD/docs/images" "$(swift build --show-bin-path)/Notinhas"

swift scripts/make-icon.swift build.noindex/AppIcon.iconset
cp build.noindex/AppIcon.iconset/icon_128x128@2x.png docs/images/icon.png
ls -1 docs/images
