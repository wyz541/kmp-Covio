#!/bin/bash
set -euo pipefail

# 特权 helper 的割接验证。对应迁移计划的风险项 R4。
#
# 做三件事：
#   1. 报告当前装的是哪个 helper（Compose 版还是 SwiftUI 版）。
#   2. 走真实安装路径装上本版 helper。
#   3. 断言 socket、plist、allowed_uid、version 与在线应答都对。
#
# 用法：
#   scripts/verify-helper-cutover.sh preflight   只看不改，不需要 root
#   scripts/verify-helper-cutover.sh verify      只看不改，不需要 root
#   scripts/verify-helper-cutover.sh selftest    在临时目录里跑断言，不碰系统
#   scripts/verify-helper-cutover.sh all         卸载旧 helper、装新 helper、验证
#   scripts/verify-helper-cutover.sh uninstall   卸载，需要管理员授权
#
# **警告：** `all` 与 `uninstall` 会先卸载已装的 helper。
# 卸载期间合盖睡眠保护与休眠模式设置都失效，直到装回为止。
# 如果当前是用户的日常环境，先确认可以中断。
#
# **警告：** 本脚本不按进程名杀进程。旧 helper 由 `launchctl bootout` 正常停止。
# 直接 kill 会让 `pmset disablesleep` 留在 1，用户的 Mac 之后无法睡眠。
#
# 下面几个路径可以用环境变量改写。默认值是真实的系统路径。
# 改写只服务于 `selftest`：真实断言跑在真路径上，才说明得了真环境的状况。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Debug}"
# 用 xcodebuild 的产物：它是本版真实的可执行文件。
APP_BINARY="${COVIO_APP_BINARY:-$ROOT/build/xcode-dd/Build/Products/$CONFIGURATION/Covio.app/Contents/MacOS/Covio}"

HELPER_DIR="${COVIO_HELPER_DIR:-/Library/Application Support/Covio}"
SOCKET_PATH="$HELPER_DIR/helper.sock"
ALLOWED_UID_PATH="$HELPER_DIR/allowed_uid"
VERSION_PATH="$HELPER_DIR/version"
APP_PATH_FILE="$HELPER_DIR/Covio.app"
SLEEP_OWNER_PATH="$HELPER_DIR/sleep_owner"
LOG_PATH="$HELPER_DIR/helper.log"
PLIST_PATH="${COVIO_HELPER_PLIST:-/Library/LaunchDaemons/com.wyz.covio.helper.plist}"
LABEL="${COVIO_HELPER_LABEL:-com.wyz.covio.helper}"

# 这两个在真环境里是固定的。`selftest` 建的临时 plist 归当前用户所有，
# 所以要能改写。断言逻辑本身不变。
EXPECTED_PLIST_OWNER="${COVIO_EXPECT_PLIST_OWNER:-root:wheel}"
EXPECTED_PLIST_MODE="${COVIO_EXPECT_PLIST_MODE:-644}"
# 临时 label 不会注册到 launchd，临时二进制也不会作为 helper 在跑。
# `selftest` 用这个跳过两项依赖真机的检查。
SKIP_LIVE_CHECKS="${COVIO_SKIP_LIVE_CHECKS:-0}"

FAILURES=0

pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }
info() { printf '  --   %s\n' "$1"; }
step() { printf '\n== %s ==\n' "$1"; }

require_app() {
  if [[ ! -x "$APP_BINARY" ]]; then
    printf 'App binary not found: %s\nRun: bash scripts/build-macos-swift.sh\n' "$APP_BINARY" >&2
    exit 1
  fi
}

# 期望的版本号取自发布清单，不在这里抄。
expected_version() {
  "$APP_BINARY" --helper-version >/dev/null 2>&1 || true
  # 发布身份只有一份来源。
  python3 -I "$ROOT/scripts/release_manifest.py" value productVersion
}

expected_protocol_version() {
  sed -n 's/^const val HELPER_PROTOCOL_VERSION = "\(.*\)"$/\1/p' "$ROOT/kmpDomain/src/com/wyz/covio/core/HelperContract.kt"
}

# ---------------------------------------------------------------- preflight

# 打印当前安装状态。不改动任何文件。
cmd_preflight() {
  step "当前安装状态"

  if [[ -e "$PLIST_PATH" ]]; then
    pass "plist 存在：$PLIST_PATH"
    local label
    label="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$PLIST_PATH" 2>/dev/null || echo '')"
    if [[ "$label" == "$LABEL" ]]; then
      pass "plist 的 Label 是 $LABEL"
    else
      fail "plist 的 Label 是 '$label'，期望 $LABEL"
    fi

    # 谁在提供 helper。这一条区分 Compose 版与 SwiftUI 版。
    local program
    program="$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$PLIST_PATH" 2>/dev/null || echo '')"
    if [[ -z "$program" ]]; then
      fail "plist 没有 ProgramArguments[0]"
    elif [[ "$program" == "$APP_BINARY" ]]; then
      pass "已装的是本版二进制：$program"
    else
      info "已装的是其它版本的 helper：$program"
      info "本版二进制是：$APP_BINARY"
      info "旧版由 Compose 宿主提供。装本版前必须先卸载，见下面的 install 步骤。"
    fi
  else
    info "没有装 helper：$PLIST_PATH 不存在"
  fi

  if [[ -S "$SOCKET_PATH" ]]; then
    pass "socket 存在：$SOCKET_PATH"
  else
    info "socket 不存在：$SOCKET_PATH"
  fi

  for file in "$ALLOWED_UID_PATH" "$VERSION_PATH" "$APP_PATH_FILE" "$SLEEP_OWNER_PATH"; do
    if [[ -f "$file" ]]; then
      info "$(basename "$file") = $(cat "$file")"
    else
      info "$(basename "$file") 不存在"
    fi
  done

  # 正在跑的 helper 进程。只看，不杀。
  local running
  running="$(/bin/ps -Ao pid=,command= | /usr/bin/grep -F -- '--helper' | /usr/bin/grep -v grep || true)"
  if [[ -n "$running" ]]; then
    info "正在运行的 helper 进程："
    printf '%s\n' "$running" | while IFS= read -r line; do info "    $line"; done
  else
    info "没有 helper 进程在运行"
  fi

  if [[ "$FAILURES" -eq 0 ]]; then
    printf '\npreflight 通过。\n'
  else
    printf '\npreflight 有 %d 处不通过。\n' "$FAILURES" >&2
    return 1
  fi
}

# ---------------------------------------------------------------- verify

# 断言 helper 已按契约装好并能应答。不需要 root。
cmd_verify() {
  step "验证 helper 安装"

  local expected expected_protocol
  expected="$(expected_version)"
  expected_protocol="$(expected_protocol_version)"
  if [[ -z "$expected" ]]; then
    printf 'Could not read productVersion from release manifest\n' >&2
    exit 1
  fi
  if [[ -z "$expected_protocol" ]]; then
    printf 'Could not read HELPER_PROTOCOL_VERSION from HelperContract.kt\n' >&2
    exit 1
  fi
  info "本版版本号：$expected"
  info "本版协议版本：$expected_protocol"

  # 1. plist
  if [[ -f "$PLIST_PATH" ]]; then
    pass "plist 存在"
  else
    fail "plist 不存在：$PLIST_PATH"
  fi
  if [[ -f "$PLIST_PATH" ]]; then
    local label program mode owner
    label="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$PLIST_PATH" 2>/dev/null || echo '')"
    [[ "$label" == "$LABEL" ]] && pass "Label 是 $LABEL" || fail "Label 是 '$label'"

    program="$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$PLIST_PATH" 2>/dev/null || echo '')"
    [[ "$program" == "$APP_BINARY" ]] \
      && pass "ProgramArguments[0] 指向本版二进制" \
      || fail "ProgramArguments[0] 是 '$program'，期望 $APP_BINARY"

    local argument
    argument="$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:1' "$PLIST_PATH" 2>/dev/null || echo '')"
    [[ "$argument" == "--helper" ]] \
      && pass "ProgramArguments[1] 是 --helper" \
      || fail "ProgramArguments[1] 是 '$argument'"

    owner="$(/usr/bin/stat -f '%Su:%Sg' "$PLIST_PATH")"
    [[ "$owner" == "$EXPECTED_PLIST_OWNER" ]] \
      && pass "plist 属于 $EXPECTED_PLIST_OWNER" \
      || fail "plist 属于 ${owner}，期望 $EXPECTED_PLIST_OWNER"

    mode="$(/usr/bin/stat -f '%Lp' "$PLIST_PATH")"
    [[ "$mode" == "$EXPECTED_PLIST_MODE" ]] \
      && pass "plist 权限是 0$EXPECTED_PLIST_MODE" \
      || fail "plist 权限是 ${mode}，期望 $EXPECTED_PLIST_MODE"
  fi

  # 2. 安装目录里的三个文件
  local uid_value version_value app_path_value
  uid_value="$(cat "$ALLOWED_UID_PATH" 2>/dev/null || echo '')"
  version_value="$(cat "$VERSION_PATH" 2>/dev/null || echo '')"
  app_path_value="$(cat "$APP_PATH_FILE" 2>/dev/null || echo '')"

  [[ "$uid_value" == "$(/usr/bin/id -u)" ]] \
    && pass "allowed_uid 是当前用户（${uid_value}）" \
    || fail "allowed_uid 是 '$uid_value'，期望 $(/usr/bin/id -u)"

  [[ "$version_value" == "$expected" ]] \
    && pass "version 是 $expected" \
    || fail "version 是 '$version_value'，期望 $expected"

  [[ "$app_path_value" == "$APP_BINARY" ]] \
    && pass "Covio.app 记录的是本版二进制" \
    || fail "Covio.app 记录的是 '$app_path_value'"

  # 3. socket
  if [[ -S "$SOCKET_PATH" ]]; then
    pass "socket 存在"
    local mode
    mode="$(/usr/bin/stat -f '%Lp' "$SOCKET_PATH")"
    [[ "$mode" == "666" ]] && pass "socket 权限是 0666" || fail "socket 权限是 $mode"
  else
    fail "socket 不存在：$SOCKET_PATH"
  fi

  # 4. LaunchDaemon 已加载
  if [[ "$SKIP_LIVE_CHECKS" == "1" ]]; then
    info "跳过 LaunchDaemon 检查（COVIO_SKIP_LIVE_CHECKS=1）"
  elif /bin/launchctl print "system/$LABEL" >/dev/null 2>&1; then
    pass "LaunchDaemon 已加载"
  else
    fail "LaunchDaemon 没有加载：system/$LABEL"
  fi

  # 5. 在线应答。走真实的客户端代码，不是脚本里拼 JSON。
  local reported
  reported="$("$APP_BINARY" --helper-version 2>/dev/null || echo '')"
  if [[ "$reported" == "$expected" ]]; then
    pass "helper 在线应答的版本是 $expected"
  else
    fail "helper 在线应答 '$reported'，期望 $expected"
  fi

  local reported_protocol
  reported_protocol="$("$APP_BINARY" --helper-protocol-version 2>/dev/null || echo '')"
  if [[ "$reported_protocol" == "$expected_protocol" ]]; then
    pass "helper 在线应答的协议版本是 $expected_protocol"
  else
    fail "helper 在线协议 '$reported_protocol'，期望 $expected_protocol"
  fi

  # 6. 正在跑的进程必须是本版二进制
  if [[ "$SKIP_LIVE_CHECKS" == "1" ]]; then
    info "跳过运行进程检查（COVIO_SKIP_LIVE_CHECKS=1）"
  else
    local running
    running="$(/bin/ps -Ao command= | /usr/bin/grep -F -- '--helper' | /usr/bin/grep -v grep || true)"
    if [[ -z "$running" ]]; then
      info "没有 helper 进程在运行（LaunchDaemon 可能刚启动，稍后重试）"
    elif printf '%s' "$running" | /usr/bin/grep -qF "$APP_BINARY"; then
      pass "运行的 helper 是本版二进制"
    else
      fail "运行的 helper 不是本版：$running"
    fi
  fi

  if [[ "$FAILURES" -eq 0 ]]; then
    printf '\nverify 通过。\n'
  else
    printf '\nverify 有 %d 处不通过。\n' "$FAILURES" >&2
    return 1
  fi
}

# ---------------------------------------------------------------- 改动性操作

# 卸载。走应用自己的安装器，不在脚本里重抄卸载步骤。
cmd_uninstall() {
  require_app
  step "卸载 helper"
  printf '需要管理员授权。会弹出系统对话框。\n'
  if "$APP_BINARY" --uninstall-helper; then
    pass "卸载完成"
  else
    fail "卸载失败"
    return 1
  fi
}

# 割接：先卸旧版，再装本版，最后验证。
cmd_all() {
  require_app

  printf '**警告：** 本命令会先卸载已装的 helper。\n'
  printf '卸载期间合盖睡眠保护失效。按回车继续，Ctrl-C 取消。\n'
  read -r _

  # 旧 helper 必须由 launchctl 正常停止，不能 kill。
  # 直接 kill 会把 pmset disablesleep 留在 1。
  cmd_uninstall || true

  step "安装本版 helper"
  printf '需要管理员授权。会弹出系统对话框。\n'
  if ! "$APP_BINARY" --install-helper; then
    fail "安装失败"
    return 1
  fi
  pass "安装完成"

  # LaunchDaemon 启动到 socket 可用之间有一小段延迟。
  sleep 2

  FAILURES=0
  cmd_verify
}

usage() {
  /usr/bin/sed -n '3,25p' "$0"
  exit 1
}

# ---------------------------------------------------------------- selftest

# 在临时目录里跑 `verify` 的断言，不碰系统。
#
# 为什么需要它：`verify` 只有在割接之后才能跑，而割接需要管理员授权。
# 在那之前那些断言一次都没执行过。这里用一套自造的 fixture 把断言跑一遍：
# 先证明布局正确时全部通过，再逐项破坏，证明每一项失败都真的被抓到。
#
# 破坏一项就重置 fixture，所以每一项失败都是独立证据。
cmd_selftest() {
  local sandbox
  sandbox="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/covio-cutover-selftest.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '$sandbox'" EXIT

  local helper_dir="$sandbox/helper"
  local plist="$sandbox/com.wyz.covio.helper.plist"
  local stub="$sandbox/Covio"
  mkdir -p "$helper_dir"

  # 桩二进制。`verify` 用 `--helper-version` 问版本，桩照抄发布清单的值。
  local version protocol_version
  version="$(expected_version)"
  protocol_version="$(expected_protocol_version)"
  if [[ -z "$version" ]]; then
    printf 'Could not read productVersion from release manifest\n' >&2
    exit 1
  fi
  if [[ -z "$protocol_version" ]]; then
    printf 'Could not read HELPER_PROTOCOL_VERSION from HelperContract.kt\n' >&2
    exit 1
  fi
  cat > "$stub" <<STUB
#!/bin/bash
if [[ "\${1:-}" == "--helper-version" ]]; then printf '%s\n' "$version"; fi
if [[ "\${1:-}" == "--helper-protocol-version" ]]; then printf '%s\n' "$protocol_version"; fi
STUB
  chmod +x "$stub"

  local script="$ROOT/scripts/verify-helper-cutover.sh"

  # 造一套正确的安装布局。
  reset_fixture() {
    rm -rf "$helper_dir"
    mkdir -p "$helper_dir"
    /usr/bin/id -u > "$helper_dir/allowed_uid"
    printf '%s\n' "$version" > "$helper_dir/version"
    printf '%s\n' "$stub" > "$helper_dir/Covio.app"
    # socket 权限断言要 0666。用 python 建，`nc -lU` 会阻塞。
    python3 -I -c "
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sys.argv[1])
import os
os.chmod(sys.argv[1], 0o666)
" "$helper_dir/helper.sock"

    cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$stub</string>
    <string>--helper</string>
  </array>
</dict>
</plist>
PLIST
    chmod "$EXPECTED_PLIST_MODE" "$plist"
  }

  # 跑一次 verify，返回它的退出码。
  run_verify() {
    COVIO_HELPER_DIR="$helper_dir" \
    COVIO_HELPER_PLIST="$plist" \
    COVIO_APP_BINARY="$stub" \
    COVIO_EXPECT_PLIST_OWNER="$(/usr/bin/id -un):$(/usr/bin/id -gn)" \
    COVIO_SKIP_LIVE_CHECKS=1 \
      "$script" verify >/dev/null 2>&1
  }

  local sandbox_failures=0

  # 每一步：改什么，期望通过还是失败。
  # 破环手法都用「换掉一个值」，不改文件数量与权限，免得连带触发别的断言。
  check_case() {
    local name="$1" expect="$2" mutate="$3"
    reset_fixture
    eval "$mutate"
    local actual=ok
    run_verify || actual=broken
    if [[ "$actual" == "$expect" ]]; then
      pass "$name"
    else
      fail "${name}：期望 ${expect}，实际 $actual"
      sandbox_failures=$((sandbox_failures + 1))
    fi
  }

  step "正确布局必须通过"
  check_case "完整布局" "ok" ":"

  step "逐项破坏必须被抓到"
  check_case "version 过期" "broken" \
    "printf '0.0.1\n' > '$helper_dir/version'"
  check_case "allowed_uid 不是当前用户" "broken" \
    "printf '99999\n' > '$helper_dir/allowed_uid'"
  check_case "Covio.app 指向别的二进制" "broken" \
    "printf '/bin/false\n' > '$helper_dir/Covio.app'"
  check_case "socket 不存在" "broken" \
    "rm -f '$helper_dir/helper.sock'"
  check_case "plist 的 Label 不对" "broken" \
    "/usr/libexec/PlistBuddy -c 'Set :Label com.example.other' '$plist'"
  check_case "ProgramArguments 少了 --helper" "broken" \
    "/usr/libexec/PlistBuddy -c 'Delete :ProgramArguments:1' '$plist'"
  check_case "ProgramArguments[0] 指向别的二进制" "broken" \
    "/usr/libexec/PlistBuddy -c 'Set :ProgramArguments:0 /bin/false' '$plist'"
  check_case "plist 权限过宽" "broken" \
    "chmod 666 '$plist'"

  step "桩二进制离线时的表现"
  # `--helper-version` 无输出：install 目录其他项都对，只有在线应答错。
  # 这一条证明版本断言真的读了二进制，不是只读了 version 文件。
  reset_fixture
  printf '#!/bin/bash\nexit 1\n' > "$stub"
  chmod +x "$stub"
  if run_verify; then
    fail "桩二进制无应答时应当失败"
    sandbox_failures=$((sandbox_failures + 1))
  else
    pass "桩二进制无应答时被抓到"
  fi

  if [[ "$sandbox_failures" -eq 0 ]]; then
    printf '\nselftest 通过。断言在自造 fixture 上按预期工作。\n'
    printf '这些断言还没有在真机上跑过。真机验证用：%s all\n' "$(basename "$0")"
  else
    printf '\nselftest 有 %d 处不符合预期。\n' "$sandbox_failures" >&2
    return 1
  fi
}

case "${1:-}" in
  preflight) cmd_preflight ;;
  verify) cmd_verify ;;
  selftest) cmd_selftest ;;
  uninstall) cmd_uninstall ;;
  all) cmd_all ;;
  *) usage ;;
esac
