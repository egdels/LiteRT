#!/usr/bin/env bash
# ============================================================================
# build-fdroid.sh — Build tensorflow-lite.aar from source (F-Droid compatible)
#
# This script builds the LiteRT Android AAR without Docker, suitable for:
#   - F-Droid build VMs (Debian/Linux x86_64)
#   - Local development (macOS, Linux)
#   - GitHub Actions (via the existing workflow)
#
# Prerequisites:
#   - Java JDK (11+)
#   - Android SDK with at least one platform and build-tools version
#   - Android NDK r25b (version 25.2.9519653) — Bazel only supports NDK ≤25
#   - Python 3
#   - Internet access (Bazel fetches external dependencies)
#
# Environment variables (all optional, sensible defaults provided):
#   ANDROID_HOME        — Path to Android SDK (auto-detected if possible)
#   ANDROID_NDK_HOME    — Path to Android NDK (default: $ANDROID_HOME/ndk/25.2.9519653 or auto-detected)
#   ANDROID_SDK_API_LEVEL   — SDK API level (default: auto-detected highest)
#   ANDROID_NDK_API_LEVEL   — NDK minimum API level (default: 21)
#   ANDROID_BUILD_TOOLS_VERSION — Build tools version (default: auto-detected highest)
#   OUTPUT_DIR          — Where to copy the AAR (default: ./output)
#   BAZELISK_VERSION    — Bazelisk version to install (default: 1.25.0)
#   FAT_APK_CPUS        — Comma-separated ABIs (default: x86,x86_64,arm64-v8a,armeabi-v7a)
#
# Usage:
#   ./ci/build-fdroid.sh
# ============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
info()  { echo "==> $*"; }
warn()  { echo "WARNING: $*" >&2; }
die()   { echo "ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Configuration defaults
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ANDROID_NDK_API_LEVEL="${ANDROID_NDK_API_LEVEL:-21}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/output}"
BAZELISK_VERSION="${BAZELISK_VERSION:-1.25.0}"
FAT_APK_CPUS="${FAT_APK_CPUS:-arm64-v8a}"

# ---------------------------------------------------------------------------
# 1. Detect OS and architecture
# ---------------------------------------------------------------------------
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Linux)
    BAZELISK_OS="linux"
    ;;
  Darwin)
    BAZELISK_OS="darwin"
    ;;
  *)
    die "Unsupported OS: $OS"
    ;;
esac

case "$ARCH" in
  x86_64|amd64)  BAZELISK_ARCH="amd64" ;;
  arm64|aarch64) BAZELISK_ARCH="arm64" ;;
  *)             die "Unsupported architecture: $ARCH" ;;
esac

info "Platform: $OS/$ARCH"

# ---------------------------------------------------------------------------
# 2. Check prerequisites
# ---------------------------------------------------------------------------
command -v java >/dev/null 2>&1   || die "Java JDK not found. Install JDK 11+."
command -v python3 >/dev/null 2>&1 || die "Python 3 not found."

# Android SDK
if [ -z "${ANDROID_HOME:-}" ]; then
  if [ -n "${ANDROID_SDK_ROOT:-}" ]; then
    ANDROID_HOME="$ANDROID_SDK_ROOT"
  elif [ -d "$HOME/Android/Sdk" ]; then
    ANDROID_HOME="$HOME/Android/Sdk"
  elif [ -d "$HOME/Library/Android/sdk" ]; then
    ANDROID_HOME="$HOME/Library/Android/sdk"
  else
    die "ANDROID_HOME not set and Android SDK not found in default locations."
  fi
fi
export ANDROID_HOME
info "Android SDK: $ANDROID_HOME"
[ -d "$ANDROID_HOME" ] || die "Android SDK directory does not exist: $ANDROID_HOME"

# Auto-detect SDK API level (highest installed platform)
if [ -z "${ANDROID_SDK_API_LEVEL:-}" ]; then
  ANDROID_SDK_API_LEVEL="$(ls "$ANDROID_HOME/platforms/" 2>/dev/null | grep -o '[0-9]\+' | sort -n | tail -1 || true)"
  [ -n "$ANDROID_SDK_API_LEVEL" ] || die "No Android platforms found in $ANDROID_HOME/platforms/"
fi
export ANDROID_SDK_API_LEVEL
info "Android SDK API level: $ANDROID_SDK_API_LEVEL"

# Auto-detect build-tools version (highest installed)
if [ -z "${ANDROID_BUILD_TOOLS_VERSION:-}" ]; then
  ANDROID_BUILD_TOOLS_VERSION="$(ls "$ANDROID_HOME/build-tools/" 2>/dev/null | grep -E '^[0-9]' | sort -V | tail -1 || true)"
  [ -n "$ANDROID_BUILD_TOOLS_VERSION" ] || die "No build-tools found in $ANDROID_HOME/build-tools/"
fi
export ANDROID_BUILD_TOOLS_VERSION
info "Android build-tools: $ANDROID_BUILD_TOOLS_VERSION"

# Android NDK — Bazel only supports NDK ≤25; override any env pointing to newer NDK
_find_ndk25() {
  for candidate in \
    "$ANDROID_HOME/ndk/25.2.9519653" \
    "$ANDROID_HOME/ndk/25.1.8937393"; do
    if [ -d "$candidate" ]; then
      echo "$candidate"
      return
    fi
  done
  # Try any 25.x
  ls -d "$ANDROID_HOME/ndk"/25.* 2>/dev/null | head -1 || true
}

if [ -n "${ANDROID_NDK_HOME:-}" ] && [ -d "$ANDROID_NDK_HOME" ]; then
  # Validate: extract major version from source.properties
  _ndk_major="$(grep 'Pkg.Revision' "$ANDROID_NDK_HOME/source.properties" 2>/dev/null | grep -o '[0-9]\+' | head -1 || echo 0)"
  if [ "$_ndk_major" -gt 25 ] 2>/dev/null; then
    warn "ANDROID_NDK_HOME points to NDK $_ndk_major ($ANDROID_NDK_HOME) which is unsupported by Bazel."
    warn "Searching for NDK r25 instead..."
    _ndk25="$(_find_ndk25)"
    if [ -n "$_ndk25" ]; then
      ANDROID_NDK_HOME="$_ndk25"
    else
      die "ANDROID_NDK_HOME points to NDK $_ndk_major (unsupported) and no NDK r25 found.
    Install NDK r25b:  sdkmanager 'ndk;25.2.9519653'
    Then re-run this script."
    fi
  fi
else
  ANDROID_NDK_HOME="$(_find_ndk25)"
  if [ -z "${ANDROID_NDK_HOME:-}" ]; then
    die "No NDK r25 found. Bazel only supports NDK ≤25 and NDK 28 causes 'undeclared inclusion' errors.
    Install NDK r25b:  sdkmanager 'ndk;25.2.9519653'
    Then re-run this script."
  fi
fi
export ANDROID_NDK_HOME
info "Android NDK: $ANDROID_NDK_HOME"
[ -d "$ANDROID_NDK_HOME" ] || die "Android NDK directory does not exist: $ANDROID_NDK_HOME"

# ---------------------------------------------------------------------------
# 3. Install Bazel (via Bazelisk) if not available
# ---------------------------------------------------------------------------
# Force Bazel version from repo root .bazelversion (not TF submodule's)
export USE_BAZEL_VERSION="$(cat "$REPO_ROOT/.bazelversion" 2>/dev/null || echo '7.4.1')"
info "Bazel version pinned to: $USE_BAZEL_VERSION"

if command -v bazel >/dev/null 2>&1; then
  info "Bazel found: $(bazel --version 2>/dev/null | head -1)"
else
  info "Bazel not found — installing Bazelisk v${BAZELISK_VERSION}..."
  BAZELISK_URL="https://github.com/bazelbuild/bazelisk/releases/download/v${BAZELISK_VERSION}/bazelisk-${BAZELISK_OS}-${BAZELISK_ARCH}"
  LOCAL_BIN="$REPO_ROOT/.local/bin"
  mkdir -p "$LOCAL_BIN"
  curl -fSL -o "$LOCAL_BIN/bazel" "$BAZELISK_URL"
  chmod +x "$LOCAL_BIN/bazel"
  export PATH="$LOCAL_BIN:$PATH"
  info "Bazelisk installed to $LOCAL_BIN/bazel"
  info "Bazel version: $(bazel --version 2>/dev/null | head -1)"
fi

# ---------------------------------------------------------------------------
# 4. Run TensorFlow configure
# ---------------------------------------------------------------------------
TF_DIR="$REPO_ROOT/third_party/tensorflow"
[ -d "$TF_DIR" ] || die "TensorFlow submodule not found at $TF_DIR. Run: git submodule update --init --recursive"

info "Running TensorFlow configure..."

export TF_SET_ANDROID_WORKSPACE=1
export ANDROID_SDK_HOME="$ANDROID_HOME"
export ANDROID_NDK_API_LEVEL
export CC_OPT_FLAGS="-Wno-sign-compare"
export PYTHON_BIN_PATH="$(command -v python3)"
export PYTHON_LIB_PATH="$(python3 -c 'import site; print(site.getsitepackages()[0])' 2>/dev/null || python3 -c 'import sysconfig; print(sysconfig.get_path("purelib"))')"
export TF_NEED_CUDA=0
export TF_NEED_ROCM=0
export TF_DOWNLOAD_CLANG=0
export TF_NEED_CLANG=0
export TF_CONFIGURE_IOS=0
export HERMETIC_PYTHON_VERSION=3.12
export USE_LOCAL_TF=true
export TF_LOCAL_SOURCE_PATH="$TF_DIR"

cd "$TF_DIR"
# Use a subshell to avoid pipefail killing the script when 'yes' gets SIGPIPE
(yes "" || true) | ./configure
cp .tf_configure.bazelrc "$REPO_ROOT/"
cd "$REPO_ROOT"

info "TensorFlow configure complete."

# ---------------------------------------------------------------------------
# 5. Build the AAR
# ---------------------------------------------------------------------------
info "Building tensorflow-lite.aar (ABIs: $FAT_APK_CPUS)..."

# On macOS, force Bazel to fully re-detect the Xcode/Apple toolchain.
# A simple shutdown or deleting external/local_config_apple_cc is not enough
# because the repository rule re-creates it from Bazel's install-base cache.
# "bazel clean --expunge" wipes the entire output base, forcing full re-detection.
if [ "$OS" = "Darwin" ]; then
  info "Expunging Bazel cache to re-detect Xcode toolchain..."
  bazel clean --expunge 2>/dev/null || true
fi

bazel build -c opt --cxxopt=--std=c++17 \
  --config=android \
  --cpu=armeabi-v7a \
  --fat_apk_cpu="$FAT_APK_CPUS" \
  --define=android_dexmerger_tool=d8_dexmerger \
  --define=android_incremental_dexing_tool=d8_dexbuilder \
  --define=tflite_with_xnnpack=false \
  --define=tflite_kernel_use_xnnpack=false \
  --copt=-DTF_LITE_DISABLE_X86_NEON \
  --repo_env=HERMETIC_PYTHON_VERSION=3.12 \
  //tflite/java:tensorflow-lite

# ---------------------------------------------------------------------------
# 6. Copy AAR to output directory
# ---------------------------------------------------------------------------
AAR_PATH="$REPO_ROOT/bazel-bin/tflite/java/tensorflow-lite.aar"
[ -f "$AAR_PATH" ] || die "AAR not found at expected path: $AAR_PATH"

mkdir -p "$OUTPUT_DIR"
cp "$AAR_PATH" "$OUTPUT_DIR/tensorflow-lite.aar"

info "============================================"
info "Build successful!"
info "AAR: $OUTPUT_DIR/tensorflow-lite.aar"
info "============================================"
