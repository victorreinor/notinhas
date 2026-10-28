#!/usr/bin/env bash
# Installs (or updates) the latest Notinhas release:
#
#   curl -fsSL https://raw.githubusercontent.com/victorreinor/notinhas/main/install.sh | bash
#
# Downloads Notinhas.zip from GitHub Releases, puts Notinhas.app in /Applications
# (or ~/Applications when /Applications isn't writable) and opens it. Existing notes are kept.
set -euo pipefail

REPO="victorreinor/notinhas"
URL="https://github.com/$REPO/releases/latest/download/Notinhas.zip"

if [ "$(uname)" != "Darwin" ]; then
  echo "Notinhas só roda no macOS." >&2
  exit 1
fi
major="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$major" -lt 14 ]; then
  echo "Notinhas precisa do macOS 14 (Sonoma) ou mais novo. Este Mac está no $(sw_vers -productVersion)." >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "→ Baixando a última versão do Notinhas…"
curl -fsSL "$URL" -o "$tmp/Notinhas.zip"
ditto -x -k "$tmp/Notinhas.zip" "$tmp"

dest="/Applications"
[ -w "$dest" ] || { dest="$HOME/Applications"; mkdir -p "$dest"; }

# A running copy quits normally on SIGTERM and saves pending edits first.
if pkill -x Notinhas; then
  while pgrep -x Notinhas >/dev/null; do sleep 0.2; done
fi

echo "→ Instalando em $dest/Notinhas.app"
rm -rf "$dest/Notinhas.app"
ditto "$tmp/Notinhas.app" "$dest/Notinhas.app"
# The app isn't notarized by Apple; without this macOS would refuse to open it.
xattr -dr com.apple.quarantine "$dest/Notinhas.app" 2>/dev/null || true

open "$dest/Notinhas.app"
echo "✓ Pronto! Uma nota amarela deve ter aparecido. Depois é só abrir pelo Spotlight: ⌘ Espaço → Notinhas"
