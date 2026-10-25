#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

exec python3 -I "$ROOT/scripts/release_pipeline.py" verify "$@"
