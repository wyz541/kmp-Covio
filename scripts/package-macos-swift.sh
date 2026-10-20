#!/bin/bash
set -euo pipefail

# 打包 macOS SwiftUI 宿主为 DMG。
#
# 这条链路不经过 jpackage：发布物由 Xcode 归档产出，不再是 jar 加 app-image。
#
# 版本号只有一个来源：kmpDomain 的 APP_VERSION。
# 与 create-release.sh 用同一个来源，避免打出一个与包内版本不同的标签。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
PROJECT="$ROOT/macosApp/Covio.xcodeproj"
SCHEME="Covio"
CONFIGURATION="Release"
DERIVED_DATA="$ROOT/build/xcode-archive"
ARCHIVE="$DERIVED_DATA/$SCHEME.xcarchive"
APP_NAME="Covio"
APP_ID="com.wyz.covio"
ICON="$ROOT/macosApp/src/Covio.icns"
MODELS="$ROOT/kmpDomain/src/com/wyz/covio/core/Models.kt"
APP_IMAGE="$DIST/$APP_NAME.app"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'This script requires macOS.\n' >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  printf 'Missing xcodebuild. Install Xcode.\n' >&2
  exit 1
fi

if [[ ! -f "$ICON" ]]; then
  printf 'Missing icon: %s\n' "$ICON" >&2
  exit 1
fi

VERSION="$(sed -n 's/^const val APP_VERSION = "\(.*\)"$/\1/p' "$MODELS")"
if [[ -z "$VERSION" ]]; then
  printf 'Could not read APP_VERSION from %s\n' "$MODELS" >&2
  exit 1
fi
DMG_PATH="$DIST/$APP_NAME-$VERSION.dmg"

if [[ -d "$APP_IMAGE" ]]; then
  find "$APP_IMAGE" -depth -delete
fi
if [[ -e "$DMG_PATH" ]]; then
  unlink "$DMG_PATH"
fi
mkdir -p "$DIST"

cd "$ROOT"

# ARCHS 在工程里也写死为 arm64：kmpDomain.framework 只有 macosArm64 一个切片。
# 这里再传一次，任何人从命令行归档都得到同样的结果。
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  -archivePath "$ARCHIVE" \
  -destination 'generic/platform=macOS' \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$VERSION" \
  archive

ARCHIVED_APP="$ARCHIVE/Products/Applications/$APP_NAME.app"
if [[ ! -d "$ARCHIVED_APP" ]]; then
  printf 'Archive has no app bundle: %s\n' "$ARCHIVED_APP" >&2
  exit 1
fi

# ditto 保留符号链接与扩展属性。cp -R 会丢掉 framework 里的版本链接。
/usr/bin/ditto "$ARCHIVED_APP" "$APP_IMAGE"

PLIST="$APP_IMAGE/Contents/Info.plist"

read_plist() {
  "$PLIST_BUDDY" -c "Print :$1" "$PLIST" 2>/dev/null || true
}

# 包内的键只断言，不回写。
# 回写会造出第二个版本来源，和 APP_VERSION 漂移时两边都看不出来。
require_plist() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(read_plist "$key")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'Bundle key %s is %s, expected %s. Check macosApp/src/Info.plist.\n' \
      "$key" "${actual:-<missing>}" "$expected" >&2
    exit 1
  fi
}

# 版本从 APP_VERSION 走到 MARKETING_VERSION，再经 Info.plist 的 $(MARKETING_VERSION) 落进包内。
require_plist CFBundleShortVersionString "$VERSION"
require_plist CFBundleIdentifier "$APP_ID"
# 代理应用：只有菜单栏状态项与顶部热区，没有 Dock 图标。
require_plist LSUIElement "true"

# 最低系统版本由工程里的 MACOSX_DEPLOYMENT_TARGET 决定。这里只确认 Xcode 替换过。
if [[ -z "$(read_plist LSMinimumSystemVersion)" ]]; then
  printf 'LSMinimumSystemVersion is empty. Check macosApp/src/Info.plist.\n' >&2
  exit 1
fi

# 图标是工程资源。`macosApp/src` 是同步目录组，非源码文件自动进 Resources。
# 打包这一步只断言它真的进了包，不回写。
if [[ ! -f "$APP_IMAGE/Contents/Resources/$APP_NAME.icns" ]]; then
  printf 'Missing icon in bundle: %s\n' "$APP_IMAGE/Contents/Resources/$APP_NAME.icns" >&2
  exit 1
fi
require_plist CFBundleIconFile "$APP_NAME.icns"

if [[ ! -d "$APP_IMAGE/Contents/Frameworks/kmpDomain.framework" ]]; then
  printf 'Missing embedded framework: %s\n' "$APP_IMAGE/Contents/Frameworks/kmpDomain.framework" >&2
  exit 1
fi

# 统一用 ad-hoc 签名对外发布。归档里的签名可能带本地开发者身份，不适合分发。
# 内嵌的 framework 由 --deep 一起签。
/usr/bin/codesign --force --deep --sign - "$APP_IMAGE"
/usr/bin/codesign --verify --deep --strict "$APP_IMAGE"

# 镜像的根要同时有 app 与指向 /Applications 的链接，装的时候才能拖进去。
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
/usr/bin/ditto "$APP_IMAGE" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
if [[ -e "$DMG_PATH" ]]; then
  unlink "$DMG_PATH"
fi
# hdiutil create 在 macOS 27 上已废弃，改用 diskutil。
/usr/sbin/diskutil image create from \
  --format UDZO \
  --volumeName "$APP_NAME" \
  "$STAGE" \
  "$DMG_PATH" >/dev/null

if [[ ! -d "$APP_IMAGE" || ! -f "$DMG_PATH" ]]; then
  printf 'Packaging did not create the expected artifacts.\n' >&2
  exit 1
fi

/usr/bin/hdiutil verify "$DMG_PATH" >/dev/null

printf 'Created %s\n' "$APP_IMAGE"
printf 'Created %s\n' "$DMG_PATH"
