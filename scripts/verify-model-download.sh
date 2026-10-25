#!/bin/bash
set -euo pipefail

# Exercise the real Hugging Face download and persisted resume path on one Mac.
# This script needs network access. It uses an isolated HOME and support directory.
#
# Usage:
#   bash scripts/verify-model-download.sh dist/Covio.app
#   bash scripts/verify-model-download.sh dist/Covio-0.5.2.dmg

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACT="${1:-$ROOT_DIR/dist/Covio.app}"
TEMP_ROOT="${COVIO_MODEL_DOWNLOAD_ACCEPTANCE_ROOT:-}"
KEEP_ROOT=0
if [[ -n "$TEMP_ROOT" ]]; then
  KEEP_ROOT=1
  if [[ -d "$TEMP_ROOT" && -n "$(find "$TEMP_ROOT" -mindepth 1 -print -quit)" ]]; then
    printf 'Acceptance root is not empty: %s\n' "$TEMP_ROOT" >&2
    exit 1
  fi
else
  TEMP_ROOT="$(mktemp -d "${TMPDIR%/}/covio-model-download-acceptance.XXXXXX")"
fi
mkdir -p "$TEMP_ROOT"
HOME_DIR="$TEMP_ROOT/home"
TMP_DIR="$TEMP_ROOT/tmp"
SUPPORT="$TEMP_ROOT/support"
RESULT="$TEMP_ROOT/result.json"
MOUNT=""

cleanup() {
  if [[ -n "$MOUNT" ]]; then
    /usr/bin/diskutil unmount "$MOUNT" >/dev/null 2>&1 || true
  fi
  if [[ "$KEEP_ROOT" -eq 0 ]]; then
    find "$TEMP_ROOT" -depth -delete 2>/dev/null || true
  fi
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
  MOUNT="$TEMP_ROOT/mount"
  mkdir -p "$MOUNT"
  /usr/bin/diskutil image attach --readOnly --nobrowse --mountPoint "$MOUNT" "$ARTIFACT" >/dev/null
  SOURCE_APP="$MOUNT/Covio.app"
else
  SOURCE_APP="$ARTIFACT"
fi
if [[ ! -d "$SOURCE_APP" ]]; then
  printf 'Cannot find Covio.app in %s\n' "$ARTIFACT" >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict "$SOURCE_APP"
for required in \
  "$SOURCE_APP/Contents/Resources/FileNamingModelManifest.json" \
  "$SOURCE_APP/Contents/Resources/ThirdPartyNotices/model/Qwen3-VL-2B-Instruct/LICENSE" \
  "$SOURCE_APP/Contents/Resources/ThirdPartyNotices/model/Qwen3-VL-2B-Instruct/NOTICE"
do
  if [[ ! -f "$required" ]]; then
    printf 'Missing model source resource: %s\n' "$required" >&2
    exit 1
  fi
done

mkdir -p "$HOME_DIR" "$TMP_DIR" "$SUPPORT"
env -i \
  HOME="$HOME_DIR" \
  TMPDIR="$TMP_DIR" \
  PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  COVIO_SUPPORT_DIR="$SUPPORT" \
  COVIO_MODEL_DOWNLOAD_ACCEPTANCE_PATH="$RESULT" \
  COVIO_MODEL_DOWNLOAD_ACCEPTANCE_PAUSE_BYTES="${COVIO_MODEL_DOWNLOAD_ACCEPTANCE_PAUSE_BYTES:-33554432}" \
  "$SOURCE_APP/Contents/MacOS/Covio" --verify-model-download

if [[ ! -f "$RESULT" ]]; then
  printf 'Model download acceptance produced no result.\n' >&2
  exit 1
fi
python3 -I - "$RESULT" <<'PY'
import json
import pathlib
import sys

result = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
if result.get("ok") is not True:
    raise SystemExit(f"model download acceptance is not ok: {result}")
if result.get("paused", {}).get("phase") != "paused":
    raise SystemExit(f"pause was not persisted: {result}")
if result.get("resume", {}).get("phaseBeforeResume") != "paused":
    raise SystemExit(f"restart did not load paused state: {result}")
if result.get("resume", {}).get("readyPhase") != "ready":
    raise SystemExit(f"resume did not finish ready: {result}")
if result.get("corruption", {}).get("rejectedErrorCode") != "checksumMismatch":
    raise SystemExit(f"corruption was not rejected: {result}")
if result.get("registry", {}).get("registeredRevision") != result.get("revision"):
    raise SystemExit(f"model was not registered at the pinned revision: {result}")
print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
PY

printf 'Real model download acceptance passed.\n'
if [[ "$KEEP_ROOT" -eq 1 ]]; then
  printf 'Acceptance root retained: %s\n' "$TEMP_ROOT"
fi
