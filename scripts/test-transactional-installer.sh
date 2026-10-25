#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/covio-installer-test.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT

fail() {
  printf 'transactional installer test failed: %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local message="$3"
  [[ "$actual" == "$expected" ]] || fail "$message (actual=$actual expected=$expected)"
}

assert_json() {
  local file="$1"
  local key="$2"
  local expected="$3"
  assert_eq "$(/usr/bin/plutil -extract "$key" raw -o - "$file")" "$expected" "$file $key"
}

assert_app_helper_record_match() {
  local app="$1"
  local expected_release_id="$2"
  assert_eq \
    "$(/usr/bin/plutil -extract CovioReleaseId raw -o - "$app/Contents/Info.plist")" \
    "$expected_release_id" \
    "app releaseId differs from the install transaction"
  assert_eq \
    "$(/usr/bin/plutil -extract releaseId raw -o - "$app/Contents/Resources/identity.json")" \
    "$expected_release_id" \
    "helper releaseId differs from the install transaction"
  assert_eq "$(/usr/bin/plutil -extract releaseId raw -o - "$TX_RECORD_PATH")" \
    "$expected_release_id" \
    "installed release record differs from the install transaction"
}

xcrun clang \
  -arch arm64 \
  -mmacosx-version-min=14.0 \
  -Wall -Wextra -Werror \
  "$ROOT/installer/atomic_swap.c" \
  -o "$TEST_ROOT/CovioTransaction"

FAKE_SOURCE="$TEST_ROOT/fake_covio.c"
cat > "$FAKE_SOURCE" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int bundle_root(char *output, size_t capacity, const char *executable) {
    const char *suffix = strstr(executable, "/Contents/MacOS/");
    if (suffix == NULL || (size_t)(suffix - executable) >= capacity) return 1;
    size_t length = (size_t)(suffix - executable);
    memcpy(output, executable, length);
    output[length] = '\0';
    return 0;
}

static int print_file(const char *path) {
    FILE *file = fopen(path, "r");
    if (file == NULL) return 1;
    char buffer[4096];
    while (fgets(buffer, sizeof(buffer), file) != NULL) fputs(buffer, stdout);
    fclose(file);
    return 0;
}

static int result_file(const char *bundle, const char *argument) {
    const char *name = argument + 2;
    char path[4096];
    snprintf(path, sizeof(path), "%s/Contents/Resources/%s.result", bundle, name);
    int value = 0;
    FILE *file = fopen(path, "r");
    if (file == NULL) return 0;
    if (fscanf(file, "%d", &value) != 1) value = 1;
    fclose(file);
    return value == 1 ? 0 : 1;
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    char bundle[4096];
    if (bundle_root(bundle, sizeof(bundle), argv[0]) != 0) return 1;
    if (strcmp(argv[1], "--print-release-identity") == 0) {
        char path[4096];
        snprintf(path, sizeof(path), "%s/Contents/Resources/identity.json", bundle);
        return print_file(path);
    }
    if (strcmp(argv[1], "--helper-version") == 0) {
        char path[4096];
        snprintf(path, sizeof(path), "%s/Contents/Resources/version.txt", bundle);
        return print_file(path);
    }
    if (strcmp(argv[1], "--uninstall-helper") == 0) return 0;
    if (strcmp(argv[1], "--register-install-transaction-helper") == 0) return 0;
    return result_file(bundle, argv[1]);
}
C

xcrun clang -arch arm64 -mmacosx-version-min=14.0 -Wall -Wextra -Werror \
  "$FAKE_SOURCE" -o "$TEST_ROOT/fake_covio"

build_app() {
  local app="$1"
  local version="$2"
  local build="$3"
  local commit="$4"
  local protocol="$5"
  local channel="$6"
  local verify_result="$7"
  local manifest_helper_sha="${8:-}"
  local transaction_version="${9:-1}"
  local prepare_result="${10:-1}"
  local release_id helper helper_sha manifest_sha info
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" \
    "$app/Contents/Library/LaunchDaemons"
  cp "$TEST_ROOT/fake_covio" "$app/Contents/MacOS/Covio"
  cp "$TEST_ROOT/fake_covio" "$app/Contents/MacOS/CovioHelper"
  chmod 0755 "$app/Contents/MacOS/Covio" "$app/Contents/MacOS/CovioHelper"
  printf '%s\n' "$version" > "$app/Contents/Resources/version.txt"
  printf '%s\n' "$verify_result" > "$app/Contents/Resources/verify-install-transaction.result"
  printf '%s\n' "$prepare_result" > "$app/Contents/Resources/prepare-install-transaction.result"
  printf '1\n' > "$app/Contents/Resources/install-helper.result"
  helper="$app/Contents/MacOS/CovioHelper"
  /usr/bin/codesign --force --sign - "$helper" >/dev/null 2>&1
  helper_sha="$(/usr/bin/shasum -a 256 "$helper" | awk '{print $1}')"
  manifest_sha="${manifest_helper_sha:-$helper_sha}"
  release_id="$version+$build+$commit"
  cat > "$app/Contents/Resources/identity.json" <<EOF
{"releaseId":"$release_id","productVersion":"$version","buildNumber":"$build","gitCommit":"$commit","protocolVersion":"$protocol","helperSHA256":"$helper_sha","channel":"$channel"}
EOF
  cat > "$app/Contents/Resources/release-manifest.json" <<EOF
{"schemaVersion":1,"releaseId":"$release_id","productVersion":"$version","buildNumber":$build,"gitCommit":"$commit","helperProtocolVersion":$protocol,"helperSHA256":"$manifest_sha","channel":"$channel"}
EOF
  info="$app/Contents/Info.plist"
  /usr/bin/plutil -create xml1 "$info" >/dev/null
  /usr/bin/plutil -insert CFBundleShortVersionString -string "$version" "$info" >/dev/null
  /usr/bin/plutil -insert CFBundleVersion -string "$build" "$info" >/dev/null
  /usr/bin/plutil -insert CovioReleaseId -string "$release_id" "$info" >/dev/null
  /usr/bin/plutil -insert CovioGitCommit -string "$commit" "$info" >/dev/null
  /usr/bin/plutil -insert CovioHelperProtocolVersion -string "$protocol" "$info" >/dev/null
  /usr/bin/plutil -insert CovioReleaseChannel -string "$channel" "$info" >/dev/null
  /usr/bin/plutil -insert CovioInstallTransactionVersion -string "$transaction_version" "$info" >/dev/null
  /usr/bin/codesign --force --sign - "$app" >/dev/null 2>&1
  /usr/bin/codesign --verify --deep --strict "$app"
}

OLD_COMMIT="1111111111111111111111111111111111111111"
NEW_COMMIT="2222222222222222222222222222222222222222"

setup_case() {
  CASE_ROOT="$TEST_ROOT/$1"
  export COVIO_TX_STATE_ROOT="$CASE_ROOT/state"
  export COVIO_TX_APPLICATIONS_ROOT="$CASE_ROOT/Applications"
  export COVIO_TX_ATOMIC_SWAP="$TEST_ROOT/CovioTransaction"
  export COVIO_TX_TEST_MODE=1
  export COVIO_TX_WAIT_ATTEMPTS=2
  mkdir -p "$COVIO_TX_APPLICATIONS_ROOT"
  TX_ENVIRONMENT_SOURCE="$CASE_ROOT/transaction.env"
  mkdir -p "$CASE_ROOT"
}

write_environment() {
  local new_app="$1"
  local helper_sha
  helper_sha="$(/usr/bin/plutil -extract helperSHA256 raw -o - \
    "$new_app/Contents/Resources/release-manifest.json")"
  cat > "$TX_ENVIRONMENT_SOURCE" <<EOF
TRANSACTION_ID='test-transaction'
EXPECTED_RELEASE_ID='$(/usr/bin/plutil -extract CovioReleaseId raw -o - "$new_app/Contents/Info.plist")'
EXPECTED_PRODUCT_VERSION='$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$new_app/Contents/Info.plist")'
EXPECTED_BUILD_NUMBER='$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$new_app/Contents/Info.plist")'
EXPECTED_COMMIT='$(/usr/bin/plutil -extract CovioGitCommit raw -o - "$new_app/Contents/Info.plist")'
EXPECTED_PROTOCOL_VERSION='$(/usr/bin/plutil -extract CovioHelperProtocolVersion raw -o - "$new_app/Contents/Info.plist")'
EXPECTED_HELPER_SHA256='$helper_sha'
EXPECTED_CHANNEL='internal'
STAGED_APP_PATH='$COVIO_TX_STATE_ROOT/Installer/staged/Covio.app'
EOF
}

# shellcheck source=../installer/transaction.sh
source "$ROOT/installer/transaction.sh"

prepare_case() {
  setup_case "$1"
  OLD_APP="$COVIO_TX_APPLICATIONS_ROOT/Covio.app"
  NEW_APP="$CASE_ROOT/new/Covio.app"
  build_app "$NEW_APP" "$2" "$3" "$4" 9 internal "${5:-1}" "${6:-}" "${7:-1}"
  build_app "$OLD_APP" 0.5.2 1 "$OLD_COMMIT" 8 internal 1 "" 1 "${8:-1}"
  write_environment "$NEW_APP"
  covio_tx_load_environment "$TX_ENVIRONMENT_SOURCE"
  covio_tx_configure
}

stage_new_app() {
  mkdir -p "$COVIO_TX_STATE_ROOT/Installer/staged"
  /usr/bin/ditto "$NEW_APP" "$TX_STAGED_APP"
}

printf 'case: successful upgrade commits app, helper and record\n'
prepare_case success 0.5.2 2 "$NEW_COMMIT"
covio_tx_prepare
stage_new_app
covio_tx_commit
assert_eq "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$TX_APP_PATH/Contents/Info.plist")" 2 "app was not upgraded"
assert_json "$TX_RECORD_PATH" releaseId "0.5.2+2+$NEW_COMMIT"
assert_app_helper_record_match "$TX_APP_PATH" "0.5.2+2+$NEW_COMMIT"
assert_json "$TX_REPORT_PATH" result installed
assert_json "$TX_REPORT_PATH" source pkg
assert_json "$TX_REPORT_PATH" previousReleaseId "0.5.2+1+$OLD_COMMIT"
assert_eq "$(cat "$(cat "$TX_LAST_POINTER")/state")" committed "transaction was not committed"

printf 'case: failed first handshake rolls back to the previous pair\n'
prepare_case handler-failure 0.5.2 3 "$NEW_COMMIT" 0
create_codesign_ok=1
covio_tx_prepare
stage_new_app
if covio_tx_commit; then
  fail "handler failure unexpectedly committed"
fi
assert_eq "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$TX_APP_PATH/Contents/Info.plist")" 1 "app did not roll back"
assert_json "$TX_RECORD_PATH" releaseId "0.5.2+1+$OLD_COMMIT"
assert_app_helper_record_match "$TX_APP_PATH" "0.5.2+1+$OLD_COMMIT"
assert_json "$TX_REPORT_PATH" result rolled-back
assert_eq "$(/usr/bin/plutil -extract source raw -o - "$TX_REPORT_PATH")" pkg "rollback report source"
[[ -n "$(/usr/bin/plutil -extract rollbackReason raw -o - "$TX_REPORT_PATH")" ]] || \
  fail "rollback reason is empty"
case "$(cat "$(cat "$TX_LAST_POINTER")/state")" in
  rolled-back|rollback-failed) ;;
  *) fail "rollback state was not recorded" ;;
esac

printf 'case: privileged state restore failure blocks the upgrade\n'
prepare_case restore-failure 0.5.2 4 "$NEW_COMMIT" 1 "" 1 0
if covio_tx_prepare; then
  fail "restore failure unexpectedly prepared the transaction"
fi
assert_eq "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$TX_APP_PATH/Contents/Info.plist")" 1 "app changed after restore failure"
assert_json "$TX_REPORT_PATH" result failed

printf 'case: downgrade is rejected before the bundle exchange\n'
prepare_case downgrade 0.5.2 1 "$NEW_COMMIT"
covio_tx_prepare
stage_new_app
if covio_tx_commit; then
  fail "downgrade unexpectedly committed"
fi
assert_eq "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$TX_APP_PATH/Contents/Info.plist")" 1 "downgrade changed the app"
assert_json "$TX_REPORT_PATH" result failed

printf 'case: helper digest mismatch is rejected\n'
prepare_case digest-mismatch 0.5.2 5 "$NEW_COMMIT" 1 "$(printf 'd%.0s' {1..64})"
covio_tx_prepare
stage_new_app
if covio_tx_commit; then
  fail "digest mismatch unexpectedly committed"
fi
assert_eq "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$TX_APP_PATH/Contents/Info.plist")" 1 "digest mismatch changed the app"
assert_json "$TX_REPORT_PATH" result failed

printf 'case: invalid signature is rejected\n'
prepare_case bad-signature 0.5.2 6 "$NEW_COMMIT"
covio_tx_prepare
stage_new_app
printf 'changed after signing\n' > "$TX_STAGED_APP/Contents/Resources/version.txt"
if covio_tx_commit; then
  fail "invalid signature unexpectedly committed"
fi
assert_eq "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$TX_APP_PATH/Contents/Info.plist")" 1 "invalid signature changed the app"
assert_json "$TX_REPORT_PATH" result failed

printf 'case: interruption after bundle exchange is recoverable\n'
prepare_case interruption 0.5.2 7 "$NEW_COMMIT"
covio_tx_prepare
stage_new_app
if ! covio_tx_verify_new_app "$TX_STAGED_APP"; then
  fail "staged app verification failed before interruption probe"
fi
"$COVIO_TX_ATOMIC_SWAP" "$TX_APP_PATH" "$TX_STAGED_APP"
covio_tx_write_state app-installed
covio_tx_recover
assert_eq "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$TX_APP_PATH/Contents/Info.plist")" 1 "interrupted transaction did not recover"
assert_json "$TX_RECORD_PATH" releaseId "0.5.2+1+$OLD_COMMIT"

printf 'case: clean install commits a matching app and record\n'
setup_case clean-install
NEW_APP="$CASE_ROOT/new/Covio.app"
build_app "$NEW_APP" 0.5.2 8 "$NEW_COMMIT" 9 internal 1 "" 1
write_environment "$NEW_APP"
covio_tx_load_environment "$TX_ENVIRONMENT_SOURCE"
covio_tx_configure
covio_tx_prepare
stage_new_app
covio_tx_commit
assert_eq "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$TX_APP_PATH/Contents/Info.plist")" 8 "clean install did not commit"
assert_json "$TX_RECORD_PATH" releaseId "0.5.2+8+$NEW_COMMIT"
assert_app_helper_record_match "$TX_APP_PATH" "0.5.2+8+$NEW_COMMIT"
assert_json "$TX_REPORT_PATH" result installed

printf 'transactional installer tests passed\n'
