#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
if [[ "$CONFIG" != "debug" && "$CONFIG" != "release" ]]; then
  echo "usage: $0 [debug|release]" >&2
  exit 2
fi

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/SpineSaver"
APP="${SPINESAVER_APP_PATH:-$ROOT/build/SpineSaver.app}"

if [[ -z "${SPINESAVER_APP_PATH:-}" && -e "$APP" && "${SPINESAVER_ALLOW_REPLACE_APP:-0}" != "1" ]]; then
  echo "Refusing to replace $APP without SPINESAVER_ALLOW_REPLACE_APP=1" >&2
  exit 3
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SpineSaver"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/SpineSaver"

# Ad-hoc signing is enough for a local app bundle and gives UserNotifications a stable identity.
codesign --force --sign - --timestamp=none "$APP" >/dev/null
echo "Built $APP"
