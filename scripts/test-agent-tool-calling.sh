#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL_DIR="${COVIO_FILE_NAMING_MODEL_DIR:-}"
RESULT_PATH="${COVIO_AGENT_TOOL_RESULTS_PATH:-$ROOT/build/agent-tool-results.json}"
DERIVED_DATA="$ROOT/build/xcode-agent-tool-dd"

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  printf 'This script requires an Apple Silicon Mac.\n' >&2
  exit 1
fi
if [[ -z "$MODEL_DIR" ]]; then
  printf 'Set COVIO_FILE_NAMING_MODEL_DIR to a verified local model directory.\n' >&2
  exit 1
fi

cd "$ROOT"
bash "$ROOT/scripts/setup-local-signing.sh"
mkdir -p "$(dirname "$RESULT_PATH")" "$ROOT/build"

xcodebuild \
  -project "$ROOT/macosApp/Covio.xcodeproj" \
  -scheme Covio \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  -only-testing:CovioTests/AgentToolCallingIntegrationTests \
  test

printf 'Agent tool results: %s\n' "$RESULT_PATH"
