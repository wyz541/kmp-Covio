#!/bin/bash
set -euo pipefail

# 把已经编译并签名的 helper 放入 app bundle 的标准 daemon 布局。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="${1:-}"
HELPER="$ROOT/build/helper/CovioHelper"
PLIST="$ROOT/macosApp/daemons/com.wyz.covio.helper.plist"

if [[ -z "$APP_BUNDLE" || ! -d "$APP_BUNDLE" ]]; then
  printf 'Usage: %s <Covio.app>\n' "$0" >&2
  exit 1
fi
if [[ ! -f "$HELPER" ]]; then
  printf 'Missing built helper: %s\n' "$HELPER" >&2
  exit 1
fi

MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
DAEMON_DIR="$APP_BUNDLE/Contents/Library/LaunchDaemons"
mkdir -p "$MACOS_DIR" "$DAEMON_DIR"
/usr/bin/ditto "$HELPER" "$MACOS_DIR/CovioHelper"
/usr/bin/ditto "$PLIST" "$DAEMON_DIR/com.wyz.covio.helper.plist"
chmod 0755 "$MACOS_DIR/CovioHelper"
chmod 0644 "$DAEMON_DIR/com.wyz.covio.helper.plist"

/usr/bin/codesign --verify --strict "$MACOS_DIR/CovioHelper"
/usr/libexec/PlistBuddy -c 'Print :BundleProgram' \
  "$DAEMON_DIR/com.wyz.covio.helper.plist" | grep -Fxq 'Contents/MacOS/CovioHelper'
/usr/libexec/PlistBuddy -c 'Print :MachServices:com.wyz.covio.helper.xpc' \
  "$DAEMON_DIR/com.wyz.covio.helper.plist" | grep -Fxq 'true'

printf 'Installed helper daemon into %s\n' "$APP_BUNDLE"
