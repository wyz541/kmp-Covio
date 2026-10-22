#!/bin/bash
set -euo pipefail

# 跑 macOS SwiftUI 宿主的 XCTest。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="$ROOT/build/xcode-dd"
PROJECT="$ROOT/macosApp/Covio.xcodeproj"
SCHEME="Covio"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'This script requires macOS.\n' >&2
  exit 1
fi

cd "$ROOT"

# 本机有证书时把签名身份固定成证书。没有就保持工程默认的 ad-hoc。
# 不固定的话每次构建换一个 cdhash，系统会把新构建当成新应用重新要权限。
bash "$ROOT/scripts/setup-local-signing.sh"

# 先查合同常量有没有漂移。
#
# `ContractCopy.swift` 与 `ContractTokens.swift` 是生成文件，改了合同忘了重跑
# 生成器时界面用的还是旧文案。这一步在编译前拦住它，比事后比对便宜。
# 用 `-I` 跑：隔离模式不读当前目录，防止目录里被放一个同名模块顶替标准库。
python3 -I "$ROOT/scripts/generate-contract-constants.py" --check

# 再查合同的跨段规则。schema 管形状，管不了「macOS 下 swiftMapping 必填」这类要求。
python3 -I "$ROOT/scripts/validate-contract.py"

# spike 测试会把测量结果打到 stdout。--quiet 会压掉它们，所以不加。
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  test
