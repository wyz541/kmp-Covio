#!/bin/bash
set -euo pipefail

# 验证签名后的 Covio 包可在断网沙箱中完成文本和图片自动命名。
#
# 用法：
#   bash scripts/verify-file-naming-bundle.sh dist/Covio.app
#   bash scripts/verify-file-naming-bundle.sh dist/Covio-0.5.0.dmg

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACT="${1:-$ROOT/dist/Covio.app}"
MANIFEST="$ROOT/macosApp/src/AutoNaming/FileNamingModelManifest.json"
MODEL_VERIFY="$ROOT/scripts/file_naming_model.py"
TEMP="$(mktemp -d "${TMPDIR%/}/codex-file-naming-178-verify.XXXXXX")"
INSTALL_ROOT="$ROOT/build/file-naming-bundle-verify-$$"
MOUNT=""
PID=""

cleanup() {
  if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
    kill -TERM "$PID" 2>/dev/null || true
  fi
  if [[ -n "$MOUNT" ]]; then
    /usr/bin/hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
  fi
  find "$TEMP" -depth -delete 2>/dev/null || true
  find "$INSTALL_ROOT" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  printf 'This script requires an Apple Silicon Mac.\n' >&2
  exit 1
fi
if [[ ! -e "$ARTIFACT" ]]; then
  printf 'Missing artifact: %s\n' "$ARTIFACT" >&2
  exit 1
fi

if [[ "$ARTIFACT" == *.dmg ]]; then
  MOUNT="$TEMP/mount"
  mkdir -p "$MOUNT"
  /usr/sbin/diskutil image attach --readOnly --nobrowse --mountPoint "$MOUNT" "$ARTIFACT" >/dev/null
  SOURCE_APP="$MOUNT/Covio.app"
else
  SOURCE_APP="$ARTIFACT"
fi
if [[ ! -d "$SOURCE_APP" ]]; then
  printf 'Cannot find Covio.app in %s\n' "$ARTIFACT" >&2
  exit 1
fi

INSTALLED="$INSTALL_ROOT/Applications/Covio.app"
mkdir -p "$INSTALL_ROOT/Applications" "$TEMP/home" "$TEMP/tmp" "$TEMP/support"
/usr/bin/ditto "$SOURCE_APP" "$INSTALLED"
/usr/bin/codesign --verify --deep --strict "$INSTALLED"

INSTALLED_MANIFEST="$INSTALLED/Contents/Resources/FileNamingModelManifest.json"
if [[ ! -f "$INSTALLED_MANIFEST" ]] || ! cmp -s "$MANIFEST" "$INSTALLED_MANIFEST"; then
  printf 'Bundled model manifest is missing or differs from the source manifest.\n' >&2
  exit 1
fi
MODEL="$INSTALLED/Contents/Resources/Models/Qwen3VL-2B-Instruct-4bit"
python3 -I "$MODEL_VERIFY" --manifest "$MANIFEST" verify-directory "$MODEL"
for required in \
  "$INSTALLED/Contents/Resources/LICENSE" \
  "$INSTALLED/Contents/Resources/ThirdPartyNotices/THIRD_PARTY_NOTICES.md" \
  "$INSTALLED/Contents/Resources/ThirdPartyNotices/model/Qwen3-VL-2B-Instruct/LICENSE" \
  "$INSTALLED/Contents/Resources/ThirdPartyNotices/model/Qwen3-VL-2B-Instruct/NOTICE"
do
  if [[ ! -f "$required" ]]; then
    printf 'Missing third-party notice: %s\n' "$required" >&2
    exit 1
  fi
done

RESULT="$TEMP/result.json"
NETWORK_LOG="$TEMP/network.log"
FULL_ACCEPTANCE="${COVIO_FILE_NAMING_ACCEPTANCE:-0}"
if [[ "$FULL_ACCEPTANCE" == "1" ]]; then
  RESULT_ENV="COVIO_FILE_NAMING_ACCEPTANCE_PATH=$RESULT"
  TIMEOUT_SECONDS=600
else
  RESULT_ENV="COVIO_FILE_NAMING_SMOKE_PATH=$RESULT"
  TIMEOUT_SECONDS=240
fi
: > "$NETWORK_LOG"
env -i \
  HOME="$TEMP/home" \
  TMPDIR="$TEMP/tmp" \
  PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  COVIO_SUPPORT_DIR="$TEMP/support" \
  "$RESULT_ENV" \
  /usr/bin/sandbox-exec -p '(version 1)(allow default)(deny network*)' \
  "$INSTALLED/Contents/MacOS/Covio" &
PID=$!

for _ in $(seq 1 "$TIMEOUT_SECONDS"); do
  state="$(ps -p "$PID" -o stat= 2>/dev/null | tr -d ' ' || true)"
  if [[ -z "$state" || "$state" == Z* ]]; then
    break
  fi
  rows="$(lsof -nP -a -p "$PID" -i 2>/dev/null | tail -n +2 | grep -Ev '127\.0\.0\.1|\[::1\]|localhost' || true)"
  if [[ -n "$rows" ]]; then
    printf '%s\n' "$rows" >> "$NETWORK_LOG"
  fi
  sleep 1
done

if kill -0 "$PID" 2>/dev/null; then
  printf 'Bundle smoke test timed out.\n' >&2
  exit 1
fi
if wait "$PID"; then
  RUN_RESULT=0
else
  RUN_RESULT=$?
fi

if [[ -s "$NETWORK_LOG" ]]; then
  printf 'Non-loopback network sockets were observed:\n' >&2
  cat "$NETWORK_LOG" >&2
  exit 1
fi
if [[ "$RUN_RESULT" -ne 0 || ! -f "$RESULT" ]]; then
  printf 'Bundle smoke test failed with status %s.\n' "$RUN_RESULT" >&2
  [[ -f "$RESULT" ]] && cat "$RESULT" >&2
  exit 1
fi

python3 - "$RESULT" "$FULL_ACCEPTANCE" <<'PY'
import json
import pathlib
import sys
result = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
full = sys.argv[2] == "1"
if result.get("ok") is not True:
    raise SystemExit(f"bundle result is not ok: {result}")
if full:
    corpus = result.get("corpus")
    thresholds = result.get("thresholds")
    if not isinstance(corpus, list) or len(corpus) != 12:
        raise SystemExit(f"unexpected corpus: {corpus}")
    if not isinstance(thresholds, dict) or not all(thresholds.values()):
        raise SystemExit(f"acceptance threshold failed: {thresholds}")
else:
    if result.get("renamed") != 2 or result.get("undoSucceeded") != 2:
        raise SystemExit(f"unexpected rename counts: {result}")
    items = result.get("items")
    if not isinstance(items, list) or len(items) != 2:
        raise SystemExit(f"unexpected item list: {items}")
print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
PY

printf 'Offline bundle verification passed.\n'
printf 'smoke_processes=1\n'
printf 'non_loopback_network_rows=0\n'
