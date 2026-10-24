#!/bin/bash
set -euo pipefail

# Amper 0.12.1 uses Ktor to download build tools. Some responses now contain
# a header or body line longer than Ktor's 8192-character limit. Download the
# same assets with curl and put them in Amper's cache before Amper starts.
#
# Cache names are the first 10 hex characters of SHA-256("<url>V1"), from:
#   org.jetbrains.amper.core.downloader.Downloader

cache_root="${KOTLIN_SHARED_CACHE_DIR:-${AMPER_SHARED_CACHE_DIR:-$HOME/Library/Caches/JetBrains/Kotlin}}"
download_cache="$cache_root/download.cache"
mkdir -p "$download_cache"

provision() {
  local target_name="$1"
  local url="$2"
  local sha256="$3"
  local target="$download_cache/$target_name"

  if [[ -f "$target" ]] && printf '%s  %s\n' "$sha256" "$target" | shasum -a 256 -c - >/dev/null 2>&1; then
    return
  fi

  local temporary
  temporary=$(mktemp "$download_cache/.amper-download.XXXXXX")
  trap 'rm -f "$temporary"' RETURN

  printf 'Provisioning %s...\n' "$target_name"
  curl --fail --location --silent --show-error \
    --retry 4 --retry-all-errors --connect-timeout 30 \
    --output "$temporary" "$url"
  printf '%s  %s\n' "$sha256" "$temporary" | shasum -a 256 -c - >/dev/null
  mv "$temporary" "$target"
  trap - RETURN
}

provision \
  "bfff255e35-pnpm-darwin-arm64.tar.gz" \
  "https://github.com/pnpm/pnpm/releases/download/v11.9.0/pnpm-darwin-arm64.tar.gz" \
  "ca6f98a8911ec975509464026205e2b54aed74cecd36c5ae9932e5997bd7de2a"

provision \
  "f8362503fc-OpenJDK25U-jdk_aarch64_mac_hotspot_25.0.5_8.tar.gz" \
  "https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.5%2B8/OpenJDK25U-jdk_aarch64_mac_hotspot_25.0.5_8.tar.gz" \
  "36dc14d797aaff6d89aab302cd053fdba6207dfdcf772052fa7b023a94b0e857"

provision \
  "c132514727-xcbeautify-3.2.1-arm64-apple-macosx.zip" \
  "https://github.com/cpisciotta/xcbeautify/releases/download/3.2.1/xcbeautify-3.2.1-arm64-apple-macosx.zip" \
  "ed32972e41bc3aa19588f8b0f4a0209ef70c663ad60bbf4ad84a2de73355d637"

provision \
  "26d759b7fb-kotlin-native-prebuilt-2.4.10-macos-aarch64.tar.gz" \
  "https://repo1.maven.org/maven2/org/jetbrains/kotlin/kotlin-native-prebuilt/2.4.10/kotlin-native-prebuilt-2.4.10-macos-aarch64.tar.gz" \
  "55ded039bb56a69aec9df354a92b42df9e916104e3c53d8d9852d9cc6617ed9d"
