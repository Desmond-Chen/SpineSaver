#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${SPINESAVER_APP_PATH:-$ROOT/build/SpineSaver.app}"
DMG="${SPINESAVER_DMG_PATH:-$ROOT/build/SpineSaver.dmg}"

if [[ ! -d "$APP" ]]; then
  echo "App not found: $APP" >&2
  echo "Run: bash scripts/build-app.sh" >&2
  exit 1
fi

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/spinesaver-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/SpineSaver.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$(dirname "$DMG")"
rm -f "$DMG"
hdiutil create \
  -volname "SpineSaver" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
echo "Built $DMG"
shasum -a 256 "$DMG"
