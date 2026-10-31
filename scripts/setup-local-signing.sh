#!/bin/bash
set -euo pipefail

# 给本机准备固定的签名身份。
#
# ad-hoc 签名没有 Team ID，TCC 的识别依据退化成 cdhash。每次构建换一个 cdhash，
# 系统就把新构建当成新应用，重新要辅助功能与桌面文件夹权限。换成证书签名后
# 识别依据锚定证书，授权跨构建保留。
#
# Signing.local.xcconfig 不进仓库，所以每个 worktree 各要一份。本脚本负责补上。
# 原理与建证书的步骤见 docs/adr/adr-0005-local-code-signing.md。
#
# 下面四种情况什么都不写，保持工程默认的 ad-hoc：
#   - 不是 macOS
#   - 工程没有 Signing.xcconfig（旧分支，还没合并签名修复）
#   - 已经有 Signing.local.xcconfig（里面可能是别的身份，不动它）
#   - 本机没有这张证书（CI 与别人的克隆）

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_CONFIG="$ROOT/macosApp/Signing.xcconfig"
OVERRIDE="$ROOT/macosApp/Signing.local.xcconfig"
IDENTITY="${COVIO_SIGN_IDENTITY:-Covio Dev}"
PRINT_IDENTITY=0

if [[ $# -gt 1 ]]; then
  printf 'Usage: %s [--print-identity]\n' "$0" >&2
  exit 2
fi
if [[ $# -eq 1 ]]; then
  if [[ "$1" != "--print-identity" ]]; then
    printf 'Usage: %s [--print-identity]\n' "$0" >&2
    exit 2
  fi
  PRINT_IDENTITY=1
fi

message() {
  if [[ "$PRINT_IDENTITY" -eq 1 ]]; then
    printf '%s\n' "$1" >&2
  else
    printf '%s\n' "$1"
  fi
}

read_override_identity() {
  sed -n \
    's/^[[:space:]]*CODE_SIGN_IDENTITY[[:space:]]*=[[:space:]]*//p' \
    "$OVERRIDE" | tail -1
}

print_identity() {
  local identity="$1"
  if [[ -z "$identity" || "$identity" == "-" ]]; then
    printf 'No stable local signing identity is configured.\n' >&2
    exit 1
  fi
  if ! security find-identity -p codesigning 2>/dev/null | grep -Fq "\"$identity\""; then
    printf 'Missing local signing identity: %s\n' "$identity" >&2
    exit 1
  fi
  printf '%s\n' "$identity"
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  if [[ "$PRINT_IDENTITY" -eq 1 ]]; then
    printf 'A stable local signing identity requires macOS.\n' >&2
    exit 1
  fi
  exit 0
fi

if [[ ! -f "$PROJECT_CONFIG" ]]; then
  if [[ "$PRINT_IDENTITY" -eq 1 ]]; then
    printf 'Missing signing configuration: %s\n' "$PROJECT_CONFIG" >&2
    exit 1
  fi
  exit 0
fi

if [[ -f "$OVERRIDE" ]]; then
  if [[ "$PRINT_IDENTITY" -eq 1 ]]; then
    print_identity "$(read_override_identity)"
  fi
  exit 0
fi

# 不用 -v。`security find-identity -v` 只列受信任的身份，自签名证书不在其中。
if ! security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
  if [[ "$PRINT_IDENTITY" -eq 1 ]]; then
    printf 'Missing local signing identity: %s\n' "$IDENTITY" >&2
    exit 1
  fi
  exit 0
fi

cat > "$OVERRIDE" <<EOF
// 本机签名身份。此文件不进仓库，由 scripts/setup-local-signing.sh 生成。
// 说明见 macosApp/Signing.xcconfig 与 docs/adr/adr-0005-local-code-signing.md。

CODE_SIGN_IDENTITY = $IDENTITY
CODE_SIGN_STYLE = Manual
EOF

message "本机签名身份已固定为 ${IDENTITY}。"
message "写入 $OVERRIDE"

if [[ "$PRINT_IDENTITY" -eq 1 ]]; then
  print_identity "$IDENTITY"
fi
