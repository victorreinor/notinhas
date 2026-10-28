#!/usr/bin/env bash
# Publishes a GitHub release with build/Notinhas.zip, tagged with CFBundleShortVersionString
# from Resources/Info.plist (bump it there first). install.sh always fetches the latest release.
#
#   ./scripts/release.sh "Notas desta versão"
set -euo pipefail
cd "$(dirname "$0")/.."

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
tag="v$version"
notes="${1:-Notinhas $version}"

if [ -n "$(git status --porcelain)" ]; then
  echo "Commit your changes before releasing." >&2
  exit 1
fi
if git rev-parse "$tag" >/dev/null 2>&1; then
  echo "Tag $tag already exists; bump CFBundleShortVersionString in Resources/Info.plist." >&2
  exit 1
fi

./scripts/test.sh
./scripts/build-app.sh
rm -f build/Notinhas.zip
ditto -c -k --keepParent build/Notinhas.app build/Notinhas.zip

# Annotated, so it also works when tag.gpgsign is on (signed tags need a message).
git tag -a "$tag" -m "Notinhas $version"
git push origin "$tag"
gh release create "$tag" build/Notinhas.zip --title "Notinhas $version" --notes "$notes"
