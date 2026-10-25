#!/bin/bash
set -euo pipefail

# Verify the real disk preflight on a small isolated APFS volume.
# This script does not contact the model source.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACT="${1:-$ROOT_DIR/dist/Covio.app}"
TEMP_ROOT="$(mktemp -d "${TMPDIR%/}/covio-model-disk-guard.XXXXXX")"
IMAGE="$TEMP_ROOT/guard.sparseimage"
MOUNT="$TEMP_ROOT/volume"
SUPPORT="$MOUNT/support"
RESULT="$TEMP_ROOT/result.json"
ATTACHED=0

cleanup() {
  if [[ "$ATTACHED" -eq 1 ]]; then
    /usr/sbin/diskutil unmount "$MOUNT" >/dev/null 2>&1 || true
  fi
  find "$TEMP_ROOT" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  printf 'This script requires an Apple Silicon Mac.\n' >&2
  exit 1
fi
if [[ ! -d "$ARTIFACT" ]]; then
  printf 'Missing app bundle: %s\n' "$ARTIFACT" >&2
  exit 1
fi

mkdir -p "$MOUNT"
/usr/bin/codesign --verify --deep --strict "$ARTIFACT"
/usr/bin/hdiutil create \
  -size 64m \
  -fs APFS \
  -volname CovioDiskGuard \
  -type SPARSE \
  -quiet \
  "$IMAGE"
/usr/sbin/diskutil image attach --mountPoint "$MOUNT" "$IMAGE" >/dev/null
ATTACHED=1
mkdir -p "$SUPPORT"

env -i \
  HOME="$TEMP_ROOT/home" \
  TMPDIR="$TEMP_ROOT/tmp" \
  PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  COVIO_SUPPORT_DIR="$SUPPORT" \
  COVIO_MODEL_DOWNLOAD_ACCEPTANCE_PATH="$RESULT" \
  COVIO_MODEL_DOWNLOAD_ACCEPTANCE_DISK_GUARD_ONLY=1 \
  "$ARTIFACT/Contents/MacOS/Covio" --verify-model-download

python3 -I - "$RESULT" "$SUPPORT" <<'PY'
import json
import pathlib
import sys

result = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
if result.get("ok") is not True:
    raise SystemExit(f"disk guard acceptance is not ok: {result}")
if result.get("errorCode") != "insufficientDisk":
    raise SystemExit(f"unexpected disk guard error: {result}")
if result.get("registered") is not False:
    raise SystemExit(f"disk guard registered a model: {result}")
if not result.get("supportDirectory", "").startswith(sys.argv[2]):
    raise SystemExit(f"acceptance did not use the restricted volume: {result}")
print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
PY

printf 'Model disk guard acceptance passed.\n'
