#!/bin/bash
set -euo pipefail

# 验证 app 内的 CovioHelper、daemon plist 和发布身份。只读，不注册服务。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/xcode-dd/Build/Products/Debug/Covio.app}"
HELPER="$APP/Contents/MacOS/CovioHelper"
DAEMON="$APP/Contents/Library/LaunchDaemons/com.wyz.covio.helper.plist"

fail() {
  printf 'helper daemon verification failed: %s\n' "$1" >&2
  exit 1
}

[[ -d "$APP" ]] || fail "missing app: $APP"
[[ -x "$HELPER" ]] || fail "missing helper executable"
[[ -f "$DAEMON" ]] || fail "missing daemon plist"

plutil -lint "$DAEMON" >/dev/null || fail "invalid daemon plist"
python3 -I - "$DAEMON" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as stream:
    plist = plistlib.load(stream)
if plist.get("BundleProgram") != "Contents/MacOS/CovioHelper":
    raise SystemExit("BundleProgram is wrong")
if plist.get("MachServices", {}).get("com.wyz.covio.helper.xpc") is not True:
    raise SystemExit("XPC Mach service is not declared")
if plist.get("Label") != "com.wyz.covio.helper":
    raise SystemExit("daemon label is wrong")
PY

codesign --verify --strict "$HELPER" >/dev/null 2>&1 || fail "helper signature is invalid"
[[ "$(lipo -archs "$HELPER")" == "arm64" ]] || fail "helper must be arm64"

if otool -L "$HELPER" | grep -Eq 'kmpDomain|AppKit|SwiftUI|Vision|AVFoundation'; then
  fail "helper links an app-only dynamic framework"
fi
service_management_linked=false
for app_binary in "$APP/Contents/MacOS/Covio" "$APP/Contents/MacOS/Covio.debug.dylib"; do
  if [[ -f "$app_binary" ]] && otool -L "$app_binary" | grep -Fq 'ServiceManagement.framework'; then
    service_management_linked=true
    break
  fi
done
[[ "$service_management_linked" == true ]] || fail "app does not link ServiceManagement"

identity_json="$("$HELPER" --print-release-identity)" || fail "helper identity probe failed"
xpc_requirement="$("$HELPER" --print-xpc-requirement)" || fail "XPC requirement probe failed"
if [[ "$xpc_requirement" != *'identifier "com.wyz.covio"'* &&
      "$xpc_requirement" != cdhash\ H* ]]; then
  fail "XPC requirement does not identify the Covio app"
fi
python3 -I - "$identity_json" "$HELPER" "$APP" <<'PY'
import hashlib
import json
import plistlib
import sys
from pathlib import Path

identity = json.loads(sys.argv[1])
helper = Path(sys.argv[2])
app = Path(sys.argv[3])
info_path = app / "Contents" / "Info.plist"
with info_path.open("rb") as stream:
    info = plistlib.load(stream)

digest = hashlib.sha256(helper.read_bytes()).hexdigest()
expected = {
    "productVersion": info["CFBundleShortVersionString"],
    "buildNumber": info["CFBundleVersion"],
    "gitCommit": info["CovioGitCommit"],
    "releaseId": info["CovioReleaseId"],
    "protocolVersion": info["CovioHelperProtocolVersion"],
    "helperSHA256": digest,
    "channel": info["CovioReleaseChannel"],
}
for key, value in expected.items():
    if identity.get(key) != str(value):
        raise SystemExit(f"identity mismatch for {key}: {identity.get(key)!r} != {value!r}")
PY

echo "helper daemon verification passed"
