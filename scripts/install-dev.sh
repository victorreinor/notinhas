#!/usr/bin/env bash
# Builds from source, replaces /Applications/Notinhas.app and opens it. Notes are kept:
# they live in ~/Library/Application Support/Notinhas, not inside the app.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

DEST="/Applications/Notinhas.app"
# SIGTERM makes the running app quit normally, saving pending edits.
if pkill -x Notinhas; then
  while pgrep -x Notinhas >/dev/null; do sleep 0.2; done
fi
rm -rf "$DEST"
cp -R build.noindex/Notinhas.app "$DEST"
open "$DEST"

echo "Installed $DEST"
