#!/bin/bash
set -euo pipefail

# 打包 macOS SwiftUI 宿主为 DMG。
#
# 这条链路不经过 jpackage：发布物由 Xcode 归档产出，不再是 jar 加 app-image。
#
# 发布身份只有一个来源：release/release-manifest.json。
# 生成文件与工作树由 release_manifest.py 校验。

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
APP_IMAGE="$DIST/$APP_NAME.app"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
FILE_NAMING_MODEL_DIR="${COVIO_FILE_NAMING_MODEL_DIR:-}"
MODEL_MANIFEST="$ROOT/macosApp/src/AutoNaming/FileNamingModelManifest.json"
MODEL_VERIFY="$ROOT/scripts/file_naming_model.py"

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
if [[ -z "$FILE_NAMING_MODEL_DIR" ]]; then
  printf 'Set COVIO_FILE_NAMING_MODEL_DIR to the verified local model directory.\n' >&2
  printf 'Run python3 scripts/file_naming_model.py download <directory> first.\n' >&2
  exit 1
fi
python3 -I "$MODEL_VERIFY" --manifest "$MODEL_MANIFEST" verify-directory "$FILE_NAMING_MODEL_DIR"

python3 -I "$ROOT/scripts/release_manifest.py" check-clean
VERSION="$(python3 -I "$ROOT/scripts/release_manifest.py" value productVersion)"
BUILD_NUMBER="$(python3 -I "$ROOT/scripts/release_manifest.py" value buildNumber)"
COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
RELEASE_ID="$(python3 -I "$ROOT/scripts/release_manifest.py" release-id --commit "$COMMIT")"
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
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  COVIO_GIT_COMMIT="$COMMIT" \
  COVIO_RELEASE_ID="$RELEASE_ID" \
  archive

ARCHIVED_APP="$ARCHIVE/Products/Applications/$APP_NAME.app"
if [[ ! -d "$ARCHIVED_APP" ]]; then
  printf 'Archive has no app bundle: %s\n' "$ARCHIVED_APP" >&2
  exit 1
fi

# ditto 保留符号链接与扩展属性。cp -R 会丢掉 framework 里的版本链接。
/usr/bin/ditto "$ARCHIVED_APP" "$APP_IMAGE"

# 模型随应用内置。运行时只读取应用资源，不需要网络或额外安装步骤。
if ! cmp -s "$MODEL_MANIFEST" "$APP_IMAGE/Contents/Resources/FileNamingModelManifest.json"; then
  printf 'Bundled model manifest is missing or differs from the source manifest.\n' >&2
  exit 1
fi
MODEL_RESOURCE="$APP_IMAGE/Contents/Resources/Models/Qwen3VL-2B-Instruct-4bit"
mkdir -p "$MODEL_RESOURCE"
/usr/bin/ditto "$FILE_NAMING_MODEL_DIR" "$MODEL_RESOURCE"
python3 -I "$MODEL_VERIFY" --manifest "$MODEL_MANIFEST" verify-directory "$MODEL_RESOURCE"

NOTICES_DIR="$APP_IMAGE/Contents/Resources/ThirdPartyNotices"
mkdir -p "$NOTICES_DIR/licenses" "$NOTICES_DIR/model"
/usr/bin/ditto "$ROOT/LICENSE" "$APP_IMAGE/Contents/Resources/LICENSE"
/usr/bin/ditto "$ROOT/THIRD_PARTY_NOTICES.md" "$NOTICES_DIR/THIRD_PARTY_NOTICES.md"
/usr/bin/ditto "$ROOT/third_party/licenses" "$NOTICES_DIR/licenses"
/usr/bin/ditto "$ROOT/third_party/models/Qwen3-VL-2B-Instruct" "$NOTICES_DIR/model/Qwen3-VL-2B-Instruct"

PLIST="$APP_IMAGE/Contents/Info.plist"
HELPER="$APP_IMAGE/Contents/MacOS/CovioHelper"
DAEMON_PLIST="$APP_IMAGE/Contents/Library/LaunchDaemons/com.wyz.covio.helper.plist"

read_plist() {
  "$PLIST_BUDDY" -c "Print :$1" "$PLIST" 2>/dev/null || true
}

# 包内的键只断言，不回写。
# 回写会造出第二个版本来源。
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

# 版本从 release manifest 走到 MARKETING_VERSION，再经 Info.plist 落进包内。
require_plist CFBundleShortVersionString "$VERSION"
require_plist CFBundleVersion "$BUILD_NUMBER"
require_plist CovioReleaseChannel "$(python3 -I "$ROOT/scripts/release_manifest.py" value channel)"
require_plist CovioGitCommit "$COMMIT"
require_plist CovioReleaseId "$RELEASE_ID"
require_plist CovioHelperProtocolVersion "$(python3 -I "$ROOT/scripts/release_manifest.py" value helperProtocolVersion)"
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

if [[ ! -x "$HELPER" || ! -f "$DAEMON_PLIST" ]]; then
  printf 'Missing bundled CovioHelper or daemon plist.\n' >&2
  exit 1
fi

# 统一用 ad-hoc 签名对外发布。归档里的签名可能带本地开发者身份，不适合分发。
# 内嵌的 framework 由 --deep 一起签。
/usr/bin/codesign --force --deep --sign - "$APP_IMAGE"
/usr/bin/codesign --verify --deep --strict "$APP_IMAGE"

python3 -I "$ROOT/scripts/release_manifest.py" generate-artifact \
  --helper "$HELPER" \
  --output "$DIST/release-manifest.json" \
  --commit "$COMMIT"

bash "$ROOT/scripts/verify-helper-daemon.sh" "$APP_IMAGE"

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

APP_BYTES="$(du -sk "$APP_IMAGE" | awk '{print $1 * 1024}')"
DMG_BYTES="$(stat -f %z "$DMG_PATH")"
printf 'Created %s\n' "$APP_IMAGE"
printf 'App bytes: %s\n' "$APP_BYTES"
printf 'Created %s\n' "$DMG_PATH"
printf 'DMG bytes: %s\n' "$DMG_BYTES"
