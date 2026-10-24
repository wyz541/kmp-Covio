#!/bin/bash
set -euo pipefail

# 产出 kmpDomain.framework，供 macosApp 的 Xcode 工程链接。
#
# 为什么不用 Amper 的 Xcode 集成：`kotlin tool xcode-integration` 只支持 iOS。
# 用 macOS 环境执行会报 `doesn't support ... sdk=macosx`。
# 证据见 docs/adr/adr-0001-macos-ui-swiftui.md 的实测 3。
# 若 Amper 将来支持 macOS SDK，删除本脚本，改用 xcode-integration。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE="kmpDomain"
PLATFORM="macosArm64"
# Amper 的任务名与产物目录把平台首字母大写：compileMacosArm64Debug。
# BSD sed 不支持 \U，用 cut 加 tr。
PLATFORM_ID="$(printf '%s' "$PLATFORM" | cut -c1 | tr '[:lower:]' '[:upper:]')$(printf '%s' "$PLATFORM" | cut -c2-)"
TARGET="macos_arm64"
BUILD_TYPE="${BUILD_TYPE:-Debug}"
SHARED_CACHE="${KOTLIN_SHARED_CACHE_DIR:-$HOME/Library/Caches/JetBrains/Kotlin}"
OUT_DIR="$ROOT/build/kmp-framework"
FRAMEWORK="$OUT_DIR/$MODULE.framework"
STATIC_OUT_DIR="$ROOT/build/kmp-framework-static"
STATIC_FRAMEWORK="$STATIC_OUT_DIR/$MODULE.framework"
KLIB="$ROOT/build/tasks/_${MODULE}_compile${PLATFORM_ID}${BUILD_TYPE}/${MODULE}.klib"
BUNDLE_ID="com.wyz.covio.$MODULE"

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  printf 'This script requires an Apple Silicon Mac.\n' >&2
  exit 1
fi

if [[ "$BUILD_TYPE" != "Debug" && "$BUILD_TYPE" != "Release" ]]; then
  printf 'BUILD_TYPE must be Debug or Release, got: %s\n' "$BUILD_TYPE" >&2
  exit 1
fi

# konanc 的路径随 Amper 版本变化，必须发现，不能写死。
find_konanc() {
  if [[ -n "${KONANC:-}" ]]; then
    printf '%s\n' "$KONANC"
    return
  fi
  local -a found=()
  local p
  for p in "$SHARED_CACHE"/extract.cache/*-kotlin-native-prebuilt-*-macos-aarch64.*/bin/konanc \
           "$HOME"/.konan/kotlin-native-prebuilt-*/bin/konanc; do
    [[ -x "$p" ]] && found+=("$p")
  done
  if [[ ${#found[@]} -eq 0 ]]; then
    return 1
  fi
  # 多个发行版时取版本号最大的一个。
  printf '%s\n' "${found[@]}" \
    | while read -r path; do
        version="$(printf '%s' "$path" | sed -E 's|.*kotlin-native-prebuilt-([0-9][0-9.]*)[-/].*|\1|')"
        printf '%s %s\n' "$version" "$path"
      done \
    | sort -k1,1V \
    | tail -1 \
    | cut -d' ' -f2-
}

# Amper CLI 自带 JRE，konanc 需要一个 java 可执行文件。
find_java_home() {
  if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/java" ]]; then
    printf '%s\n' "$JAVA_HOME"
    return
  fi
  local p
  for p in "$SHARED_CACHE"/cli/zulu*/*/*/Contents/Home \
           "$SHARED_CACHE"/cli/*/*/Contents/Home; do
    if [[ -x "$p/bin/java" ]]; then
      printf '%s\n' "$p"
      return
    fi
  done
  if p="$(/usr/libexec/java_home 2>/dev/null)" && [[ -x "$p/bin/java" ]]; then
    printf '%s\n' "$p"
    return
  fi
  return 1
}

# Amper 已经解析好依赖。读它的解析结果，避免自己算传递依赖与版本。
# 直接扫 .m2.cache 会同时看到多个版本，选错版本。
resolve_dep_klibs() {
  local graph
  graph="$(cd "$ROOT" && /bin/sh ./kotlin show dependencies \
    -m "$MODULE" --platform-group=native --scope=compile 2>/dev/null)" || return 1
  printf '%s\n' "$graph" \
    | LC_ALL=C grep -oE "[A-Za-z0-9._-]+:[A-Za-z0-9._-]+-$(printf '%s' "$PLATFORM" | tr '[:upper:]' '[:lower:]'):[A-Za-z0-9._-]+" \
    | sort -u
}

klib_path_for() {
  local coord="$1"
  local group="${coord%%:*}"
  local rest="${coord#*:}"
  local artifact="${rest%%:*}"
  local version="${rest#*:}"
  local group_path
  group_path="$(printf '%s' "$group" | tr '.' '/')"
  printf '%s/%s/%s/%s/%s-%s.klib\n' \
    "$SHARED_CACHE/.m2.cache" "$group_path" "$artifact" "$version" "$artifact" "$version"
}

cd "$ROOT"
printf 'Compiling %s [%s %s]...\n' "$MODULE" "$PLATFORM" "$BUILD_TYPE"
# Amper 在这一步把 konanc 与它自带的 JRE 解压到共享缓存。
# 冷机器上这一步之前缓存是空的，所以下面两处发现必须排在它之后。
# 顺序写反会让 CI 与刚克隆的机器报「Cannot find konanc」。
/bin/sh ./kotlin task ":${MODULE}:compile${PLATFORM_ID}${BUILD_TYPE}"

KONANC_BIN="$(find_konanc)" || {
  printf 'Cannot find konanc. Looked under %s/extract.cache and ~/.konan.\n' "$SHARED_CACHE" >&2
  printf 'Set KONANC=/path/to/konanc.\n' >&2
  exit 1
}

JAVA_HOME_DIR="$(find_java_home)" || {
  printf 'Cannot find a Java runtime for konanc. Set JAVA_HOME.\n' >&2
  exit 1
}
export JAVA_HOME="$JAVA_HOME_DIR"

printf 'konanc: %s\n' "$KONANC_BIN"
printf 'java:   %s\n' "$JAVA_HOME/bin/java"

if [[ ! -f "$KLIB" ]]; then
  printf 'Missing klib: %s\n' "$KLIB" >&2
  exit 1
fi

LIB_ARGS=()
while read -r coord; do
  [[ -z "$coord" ]] && continue
  dep_klib="$(klib_path_for "$coord")"
  if [[ ! -f "$dep_klib" ]]; then
    printf 'Missing dependency klib for %s\n  expected at: %s\n' "$coord" "$dep_klib" >&2
    exit 1
  fi
  printf 'linking %s\n' "$coord"
  LIB_ARGS+=(-library "$dep_klib")
done < <(resolve_dep_klibs)

LINK_FLAGS=(-produce framework -target "$TARGET" -Xbinary=bundleId="$BUNDLE_ID")
if [[ "$BUILD_TYPE" == "Release" ]]; then
  LINK_FLAGS+=(-opt)
else
  LINK_FLAGS+=(-g)
fi

rm -rf "$FRAMEWORK" "$FRAMEWORK.dSYM" "$STATIC_FRAMEWORK" "$STATIC_FRAMEWORK.dSYM"
mkdir -p "$OUT_DIR" "$STATIC_OUT_DIR"

# -Xinclude 把 Amper 编好的 klib 当作源码处理。
# 只用 -library 会报 `you have not specified any compilation arguments`。
LINK_LOG="$OUT_DIR/link.log"
if ! "$KONANC_BIN" \
  "${LINK_FLAGS[@]}" \
  -Xinclude="$KLIB" \
  ${LIB_ARGS[@]+"${LIB_ARGS[@]}"} \
  -o "$OUT_DIR/$MODULE" \
  >"$LINK_LOG" 2>&1; then
  grep -v '^WARNING: ' "$LINK_LOG" >&2 || true
  printf 'konanc failed. Full log: %s\n' "$LINK_LOG" >&2
  exit 1
fi

if [[ ! -f "$FRAMEWORK/$MODULE" ]]; then
  printf 'Framework was not produced: %s\n' "$FRAMEWORK" >&2
  exit 1
fi

if [[ ! -f "$FRAMEWORK/Headers/$MODULE.h" ]]; then
  printf 'Framework has no header: %s/Headers/%s.h\n' "$FRAMEWORK" "$MODULE" >&2
  exit 1
fi

printf 'Built %s\n' "$FRAMEWORK"
file "$FRAMEWORK/$MODULE"

STATIC_LINK_LOG="$STATIC_OUT_DIR/link.log"
if ! "$KONANC_BIN" \
  "${LINK_FLAGS[@]}" \
  -Xstatic-framework \
  -Xinclude="$KLIB" \
  ${LIB_ARGS[@]+"${LIB_ARGS[@]}"} \
  -o "$STATIC_OUT_DIR/$MODULE" \
  >"$STATIC_LINK_LOG" 2>&1; then
  grep -v '^WARNING: ' "$STATIC_LINK_LOG" >&2 || true
  printf 'konanc static link failed. Full log: %s\n' "$STATIC_LINK_LOG" >&2
  exit 1
fi

if [[ ! -f "$STATIC_FRAMEWORK/$MODULE" ]]; then
  printf 'Static framework was not produced: %s\n' "$STATIC_FRAMEWORK" >&2
  exit 1
fi

if [[ ! -f "$STATIC_FRAMEWORK/Headers/$MODULE.h" ]]; then
  printf 'Static framework has no header: %s/Headers/%s.h\n' "$STATIC_FRAMEWORK" "$MODULE" >&2
  exit 1
fi

printf 'Built %s\n' "$STATIC_FRAMEWORK"
file "$STATIC_FRAMEWORK/$MODULE"
