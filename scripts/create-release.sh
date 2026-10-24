#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
# 发布身份只有一个来源：release/release-manifest.json。
VERSION="$(python3 -I "$ROOT/scripts/release_manifest.py" value productVersion)"
TAG="v$VERSION"
DMG="$DIST/Covio-$VERSION.dmg"
CHECKSUM="$DMG.sha256"
MANIFEST="$DIST/release-manifest.json"
NOTES="$ROOT/RELEASE_NOTES.md"

if ! command -v gh >/dev/null 2>&1; then
  printf 'Install the GitHub CLI first: brew install gh\n' >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  printf 'Authenticate first: gh auth login\n' >&2
  exit 1
fi

# Use the active GitHub repository instead of a hard-coded owner. The remote
# repository moved before, and a stale owner would publish to the wrong place.
REPO="${RELEASE_REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
if [[ -z "$REPO" ]]; then
  printf 'Could not resolve the GitHub repository.\n' >&2
  exit 1
fi

TARGET="$(git -C "$ROOT" rev-parse HEAD)"
if [[ ! -f "$DMG" ]]; then
  printf 'Missing artifact: %s\nRun scripts/package-macos-swift.sh first.\n' "$DMG" >&2
  exit 1
fi
if [[ ! -f "$MANIFEST" ]]; then
  printf 'Missing artifact manifest: %s\nRun scripts/package-macos-swift.sh first.\n' "$MANIFEST" >&2
  exit 1
fi

python3 -I "$ROOT/scripts/release_manifest.py" verify-artifact \
  "$MANIFEST" \
  --helper "$DIST/Covio.app/Contents/MacOS/CovioHelper"

DMG_BYTES="$(stat -f %z "$DMG")"
GITHUB_ASSET_LIMIT=2147483648
if [[ "$DMG_BYTES" -ge "$GITHUB_ASSET_LIMIT" ]]; then
  printf 'DMG is %s bytes. GitHub assets must be smaller than %s bytes.\n'     "$DMG_BYTES" "$GITHUB_ASSET_LIMIT" >&2
  exit 1
fi
bash "$ROOT/scripts/verify-file-naming-bundle.sh" "$DMG"
(cd "$DIST" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$CHECKSUM")")

# The app reads the Releases page.
# Therefore this release must stay a full release, not a pre-release.
gh release create "$TAG" "$DMG" "$CHECKSUM" "$MANIFEST" \
  --repo "$REPO" \
  --target "$TARGET" \
  --title "Covio $VERSION (internal test)" \
  --notes-file "$NOTES"

printf 'Created release %s in %s\n' "$TAG" "$REPO"
