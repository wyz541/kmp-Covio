#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ "$(/usr/bin/id -u)" != "0" ]]; then
  printf 'Run this command with administrator privileges:\n  sudo %q\n' "$0" >&2
  exit 2
fi

unset COVIO_TX_TEST_MODE COVIO_TX_STATE_ROOT COVIO_TX_APPLICATIONS_ROOT \
  COVIO_TX_ATOMIC_SWAP COVIO_TX_CODESIGN COVIO_TX_DITTO COVIO_TX_FIND \
  COVIO_TX_INSTALL COVIO_TX_LIPO COVIO_TX_PGREP COVIO_TX_PLUTIL \
  COVIO_TX_SHASUM COVIO_TX_SPCTL COVIO_TX_STAPLER COVIO_TX_UNAME COVIO_TX_ID \
  COVIO_TX_WAIT_ATTEMPTS
umask 077
# shellcheck source=transaction.sh
source "$SCRIPT_DIR/transaction.sh"
covio_tx_configure "/Library/Application Support/Covio" "/Applications"
covio_tx_recover "$@"
