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
OFFLINE_APP="$DIST/$APP_NAME-Offline.app"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
MODEL_MANIFEST="$ROOT/macosApp/src/AutoNaming/FileNamingModelManifest.json"
RELEASE_SIGN_IDENTITY="${COVIO_CODE_SIGN_IDENTITY:-}"
INSTALLER_SIGN_IDENTITY="${COVIO_INSTALLER_SIGN_IDENTITY:-}"
DEVELOPMENT_TEAM="${COVIO_DEVELOPMENT_TEAM:-}"
NOTARY_PROFILE="${COVIO_NOTARY_PROFILE:-}"
CLEANUP_PATHS=()

cleanup_temporary_paths() {
  local path
  for path in "${CLEANUP_PATHS[@]:-}"; do
    if [[ -n "$path" && -e "$path" ]]; then
      find "$path" -depth -delete
    fi
  done
}
trap cleanup_temporary_paths EXIT

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
python3 -I "$ROOT/scripts/release_manifest.py" check-clean
VERSION="$(python3 -I "$ROOT/scripts/release_manifest.py" value productVersion)"
BUILD_NUMBER="$(python3 -I "$ROOT/scripts/release_manifest.py" value buildNumber)"
CHANNEL="$(python3 -I "$ROOT/scripts/release_manifest.py" value channel)"
COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
RELEASE_ID="$(python3 -I "$ROOT/scripts/release_manifest.py" release-id --commit "$COMMIT")"
DMG_PATH="$DIST/$APP_NAME-$VERSION.dmg"
APP_ZIP="$DIST/$APP_NAME-$VERSION.app.zip"
PKG_PATH="$DIST/$APP_NAME-$VERSION.pkg"
TRANSACTION_ID="build-$BUILD_NUMBER-${COMMIT:0:12}"
STAGED_APP_RELATIVE="Library/Application Support/Covio/Installer/staged/$APP_NAME.app"
STAGED_APP_PATH="/$STAGED_APP_RELATIVE"
OFFLINE_DMG="$DIST/$APP_NAME-Offline-$VERSION.dmg"

if [[ "$CHANNEL" == "public" ]]; then
  if [[ -z "$RELEASE_SIGN_IDENTITY" || "$RELEASE_SIGN_IDENTITY" == "-" ]]; then
    printf 'Public packaging requires COVIO_CODE_SIGN_IDENTITY.\n' >&2
    exit 1
  fi
  if [[ -z "$INSTALLER_SIGN_IDENTITY" ]]; then
    printf 'Public packaging requires COVIO_INSTALLER_SIGN_IDENTITY.\n' >&2
    exit 1
  fi
  if [[ -z "$DEVELOPMENT_TEAM" ]]; then
    printf 'Public packaging requires COVIO_DEVELOPMENT_TEAM.\n' >&2
    exit 1
  fi
  if [[ -z "$NOTARY_PROFILE" ]]; then
    printf 'Public packaging requires COVIO_NOTARY_PROFILE.\n' >&2
    exit 1
  fi
fi

if [[ -d "$APP_IMAGE" ]]; then
  find "$APP_IMAGE" -depth -delete
fi
if [[ -d "$OFFLINE_APP" ]]; then
  find "$OFFLINE_APP" -depth -delete
fi
for artifact in "$DMG_PATH" "$APP_ZIP" "$PKG_PATH" "$OFFLINE_DMG"; do
  if [[ -e "$artifact" ]]; then
    unlink "$artifact"
  fi
done
mkdir -p "$DIST"

cd "$ROOT"

# ARCHS 在工程里也写死为 arm64：kmpDomain.framework 只有 macosArm64 一个切片。
# 这里再传一次，任何人从命令行归档都得到同样的结果。
XCODE_SIGN_ARGS=()
if [[ -n "$RELEASE_SIGN_IDENTITY" && "$RELEASE_SIGN_IDENTITY" != "-" ]]; then
  XCODE_SIGN_ARGS+=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$RELEASE_SIGN_IDENTITY"
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
  )
else
  XCODE_SIGN_ARGS+=(CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY=-)
fi

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
  "${XCODE_SIGN_ARGS[@]}" \
  archive

ARCHIVED_APP="$ARCHIVE/Products/Applications/$APP_NAME.app"
if [[ ! -d "$ARCHIVED_APP" ]]; then
  printf 'Archive has no app bundle: %s\n' "$ARCHIVED_APP" >&2
  exit 1
fi

# ditto 保留符号链接与扩展属性。cp -R 会丢掉 framework 里的版本链接。
/usr/bin/ditto "$ARCHIVED_APP" "$APP_IMAGE"

# 默认包只携带模型清单和许可证。模型权重由离线包或首次使用下载提供。
if ! cmp -s "$MODEL_MANIFEST" "$APP_IMAGE/Contents/Resources/FileNamingModelManifest.json"; then
  printf 'Model manifest is missing or differs from the source manifest.\n' >&2
  exit 1
fi
if [[ -n "$(find "$APP_IMAGE/Contents/Resources/Models" -name '*.safetensors' -type f -print -quit 2>/dev/null)" ]]; then
  printf 'Default app bundle must not contain model weights.\n' >&2
  exit 1
fi

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
require_plist CovioReleaseChannel "$CHANNEL"
require_plist CovioGitCommit "$COMMIT"
require_plist CovioReleaseId "$RELEASE_ID"
require_plist CovioHelperProtocolVersion "$(python3 -I "$ROOT/scripts/release_manifest.py" value helperProtocolVersion)"
require_plist CovioInstallTransactionVersion "1"
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

# 先签整个 bundle，确保嵌套 helper 的最终字节稳定。生成发布清单后只重签 app 外层，
# 避免复制清单使签名失效，也避免 helper 摘要随 deep 签名再次变化。
if [[ -n "$RELEASE_SIGN_IDENTITY" && "$RELEASE_SIGN_IDENTITY" != "-" ]]; then
  /usr/bin/codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "$RELEASE_SIGN_IDENTITY" \
    "$APP_IMAGE"
else
  /usr/bin/codesign --force --deep --sign - "$APP_IMAGE"
fi
/usr/bin/codesign --verify --deep --strict "$APP_IMAGE"

BUNDLED_MANIFEST="$APP_IMAGE/Contents/Resources/release-manifest.json"
python3 -I "$ROOT/scripts/release_manifest.py" generate-bundle-manifest \
  --helper "$HELPER" \
  --output "$BUNDLED_MANIFEST" \
  --commit "$COMMIT"

if [[ -n "$RELEASE_SIGN_IDENTITY" && "$RELEASE_SIGN_IDENTITY" != "-" ]]; then
  /usr/bin/codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$RELEASE_SIGN_IDENTITY" \
    "$APP_IMAGE"
else
  /usr/bin/codesign --force --sign - "$APP_IMAGE"
fi
/usr/bin/codesign --verify --deep --strict "$APP_IMAGE"

notarize_and_staple() {
  local target="$1"
  local submit_path="$2"
  printf 'Submitting %s for notarization\n' "$target"
  /usr/bin/xcrun notarytool submit "$submit_path" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  /usr/bin/xcrun stapler staple "$target"
  /usr/bin/xcrun stapler validate "$target"
}

if [[ -n "$NOTARY_PROFILE" ]]; then
  APP_NOTARY_ZIP="$DIST/$APP_NAME-$VERSION-notary.zip"
  /usr/bin/ditto -c -k --keepParent "$APP_IMAGE" "$APP_NOTARY_ZIP"
  notarize_and_staple "$APP_IMAGE" "$APP_NOTARY_ZIP"
  unlink "$APP_NOTARY_ZIP"
fi

bash "$ROOT/scripts/verify-helper-daemon.sh" "$APP_IMAGE" --require-manifest

# app.zip lets the publish command download and verify the app and helper pair again.
/usr/bin/ditto -c -k --keepParent "$APP_IMAGE" "$APP_ZIP"

# 镜像的根要同时有 app 与指向 /Applications 的链接，装的时候才能拖进去。
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/covio-dmg-stage.XXXXXX")"
CLEANUP_PATHS+=("$STAGE")
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

if [[ -n "$RELEASE_SIGN_IDENTITY" && "$RELEASE_SIGN_IDENTITY" != "-" ]]; then
  /usr/bin/codesign --force --timestamp --sign "$RELEASE_SIGN_IDENTITY" "$DMG_PATH"
  /usr/bin/codesign --verify --strict "$DMG_PATH"
fi

PKG_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/covio-pkg-root.XXXXXX")"
PKG_SCRIPTS="$(mktemp -d "${TMPDIR:-/tmp}/covio-pkg-scripts.XXXXXX")"
CLEANUP_PATHS+=("$PKG_ROOT" "$PKG_SCRIPTS")
TRANSACTION_BINARY="$PKG_ROOT/Library/Application Support/Covio/Installer/bin/CovioTransaction"
INSTALLER_PAYLOAD="$PKG_ROOT/Library/Application Support/Covio/Installer"
mkdir -p \
  "$(dirname "$TRANSACTION_BINARY")" \
  "$INSTALLER_PAYLOAD/staged"

/usr/bin/xcrun clang \
  -arch arm64 \
  -mmacosx-version-min=14.0 \
  -Wall -Wextra -Werror \
  "$ROOT/installer/atomic_swap.c" \
  -o "$TRANSACTION_BINARY"
if [[ -n "$RELEASE_SIGN_IDENTITY" && "$RELEASE_SIGN_IDENTITY" != "-" ]]; then
  /usr/bin/codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$RELEASE_SIGN_IDENTITY" \
    "$TRANSACTION_BINARY"
else
  /usr/bin/codesign --force --sign - "$TRANSACTION_BINARY"
fi
/usr/bin/ditto "$APP_IMAGE" "$PKG_ROOT/$STAGED_APP_RELATIVE"
/usr/bin/ditto "$ROOT/installer/transaction.sh" "$INSTALLER_PAYLOAD/transaction.sh"
/usr/bin/ditto "$ROOT/installer/recover.sh" "$INSTALLER_PAYLOAD/recover.sh"
chmod 0755 "$INSTALLER_PAYLOAD/recover.sh" "$INSTALLER_PAYLOAD/transaction.sh"

/usr/bin/ditto "$ROOT/installer/preinstall" "$PKG_SCRIPTS/preinstall"
/usr/bin/ditto "$ROOT/installer/postinstall" "$PKG_SCRIPTS/postinstall"
/usr/bin/ditto "$ROOT/installer/transaction.sh" "$PKG_SCRIPTS/transaction.sh"
chmod 0755 "$PKG_SCRIPTS/preinstall" "$PKG_SCRIPTS/postinstall"
HELPER_SHA256="$(/usr/bin/plutil -extract helperSHA256 raw -o - "$BUNDLED_MANIFEST")"
cat > "$PKG_SCRIPTS/transaction.env" <<EOF
TRANSACTION_ID='$TRANSACTION_ID'
EXPECTED_RELEASE_ID='$RELEASE_ID'
EXPECTED_PRODUCT_VERSION='$VERSION'
EXPECTED_BUILD_NUMBER='$BUILD_NUMBER'
EXPECTED_COMMIT='$COMMIT'
EXPECTED_PROTOCOL_VERSION='$(python3 -I "$ROOT/scripts/release_manifest.py" value helperProtocolVersion)'
EXPECTED_HELPER_SHA256='$HELPER_SHA256'
EXPECTED_CHANNEL='$CHANNEL'
STAGED_APP_PATH='$STAGED_APP_PATH'
EOF

PKG_SIGN_ARGS=()
if [[ -n "$INSTALLER_SIGN_IDENTITY" ]]; then
  PKG_SIGN_ARGS+=(--sign "$INSTALLER_SIGN_IDENTITY")
fi
if [[ -e "$PKG_PATH" ]]; then
  unlink "$PKG_PATH"
fi
PKG_COMMAND=(
  /usr/bin/pkgbuild
  --root "$PKG_ROOT"
  --scripts "$PKG_SCRIPTS"
  --install-location "/"
  --identifier "$APP_ID.pkg"
  --version "$VERSION.$BUILD_NUMBER"
)
if [[ ${#PKG_SIGN_ARGS[@]} -gt 0 ]]; then
  PKG_COMMAND+=("${PKG_SIGN_ARGS[@]}")
fi
PKG_COMMAND+=("$PKG_PATH")
"${PKG_COMMAND[@]}"

PKG_PAYLOAD_FILES="$(/usr/sbin/pkgutil --payload-files "$PKG_PATH")"
if [[ "$PKG_PAYLOAD_FILES" != *"Library/Application Support/Covio/Installer/staged/$APP_NAME.app/Contents/MacOS/CovioHelper"* ]]; then
  printf 'PKG payload is missing the staged app helper.\n' >&2
  exit 1
fi
if [[ "$PKG_PAYLOAD_FILES" != *"Library/Application Support/Covio/Installer/bin/CovioTransaction"* ]]; then
  printf 'PKG payload is missing the transaction executable.\n' >&2
  exit 1
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  notarize_and_staple "$DMG_PATH" "$DMG_PATH"
  if [[ ${#PKG_SIGN_ARGS[@]} -eq 0 ]]; then
    printf 'Public packaging requires a signed PKG before notarization.\n' >&2
    exit 1
  fi
  notarize_and_staple "$PKG_PATH" "$PKG_PATH"
fi

if [[ ! -f "$APP_ZIP" || ! -f "$PKG_PATH" ]]; then
  printf 'Packaging did not create the expected app zip or PKG.\n' >&2
  exit 1
fi

python3 -I "$ROOT/scripts/release_manifest.py" generate-artifact \
  --helper "$HELPER" \
  --default-dmg "$DMG_PATH" \
  --output "$DIST/release-manifest.json" \
  --commit "$COMMIT"

APP_BYTES="$(du -sk "$APP_IMAGE" | awk '{print $1 * 1024}')"
DMG_BYTES="$(stat -f %z "$DMG_PATH")"
printf 'Created %s\n' "$APP_IMAGE"
printf 'App bytes: %s\n' "$APP_BYTES"
printf 'Created %s\n' "$DMG_PATH"
printf 'DMG bytes: %s\n' "$DMG_BYTES"
printf 'Created %s\n' "$APP_ZIP"
printf 'Created %s\n' "$PKG_PATH"
