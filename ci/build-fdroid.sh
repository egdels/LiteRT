#!/usr/bin/env bash
# ============================================================================
# build-fdroid.sh — Build tensorflow-lite.aar from source (F-Droid compatible)
#
# This script builds the LiteRT Android AAR without Docker, suitable for:
#   - F-Droid build VMs (Debian/Linux x86_64)
#   - Local development (macOS, Linux)
#   - GitHub Actions (via build-fdroid-aar.yml)
#
# F-Droid compliance:
#   - All toolchain versions are pinned (Bazel, NDK, SDK, Python)
#   - Bazelisk download is verified via SHA256 checksum
#   - Supports --repository_cache for offline/reproducible builds
#   - No proprietary dependencies (CUDA/NCCL stubbed, no Google Play Services)
#   - TF configure can be skipped with a pre-generated .tf_configure.bazelrc
#
# Prerequisites:
#   - Java JDK 17
#   - Android SDK with platform android-35 and build-tools 35.0.1
#   - Android NDK r25b (version 25.2.9519653) — Bazel only supports NDK ≤25
#   - Python 3.9–3.12
#   - Internet access (unless BAZEL_REPO_CACHE is provided)
#
# Environment variables (all optional, sensible defaults provided):
#   ANDROID_HOME              — Path to Android SDK (auto-detected)
#   ANDROID_NDK_HOME          — Path to Android NDK (default: $ANDROID_HOME/ndk/25.2.9519653)
#   ANDROID_SDK_API_LEVEL     — SDK API level (default: 35)
#   ANDROID_NDK_API_LEVEL     — NDK minimum API level (default: 21)
#   ANDROID_BUILD_TOOLS_VERSION — Build tools version (default: 35.0.1)
#   OUTPUT_DIR                — Where to copy the AAR (default: ./output)
#   BAZELISK_VERSION          — Bazelisk version to install (default: 1.25.0)
#   FAT_APK_CPUS              — Comma-separated ABIs (default: arm64-v8a)
#   BAZEL_REPO_CACHE          — Path to pre-populated Bazel repository cache
#                               (enables offline builds; see ci/README-fdroid.md)
#   SKIP_CONFIGURE            — Set to 1 to skip TF configure (uses existing
#                               .tf_configure.bazelrc in repo root)
#
# F-Droid metadata example (fdroiddata):
#   srclibs:
#     - LiteRT@v1.4.1-patch
#   prebuild:
#     - sdkmanager 'platforms;android-35' 'build-tools;35.0.1' 'ndk;25.2.9519653'
#   build:
#     - cd $$LiteRT$$ && ANDROID_HOME=$$SDK$$ ANDROID_NDK_HOME=$$NDK$$ ./ci/build-fdroid.sh
#     - cp $$LiteRT$$/output/tensorflow-lite.aar app/libs/
#   ndk: 25.2.9519653
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
# Pinned versions — change these when upgrading
# ---------------------------------------------------------------------------
PINNED_SDK_API_LEVEL="35"
PINNED_BUILD_TOOLS="35.0.1"
PINNED_NDK_VERSION="25.2.9519653"
PINNED_BAZELISK_VERSION="1.25.0"

# Bazelisk SHA256 checksums (v1.25.0)
declare -A BAZELISK_SHA256=(
  ["linux-amd64"]="fd8fdff418a1758887520fa42da7e6ae39aefc788cf5e7f7bb8db6934d279fc4"
  ["linux-arm64"]="4c8d966e40ac2c4efcc7f1a5a5cceef2c0a2f16b957e791fa7a867cce31e8fcb"
  ["darwin-amd64"]="0af019eeb642fa70744419d02aa32df55e6e7a084105d49fb26801a660aa56d3"
  ["darwin-arm64"]="b13dd89c6ecd90944ca3539f5a2c715a18f69b7458878c471a902a8e482ceb4b"
)

# ---------------------------------------------------------------------------
# Configuration defaults
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ANDROID_SDK_API_LEVEL="${ANDROID_SDK_API_LEVEL:-$PINNED_SDK_API_LEVEL}"
ANDROID_BUILD_TOOLS_VERSION="${ANDROID_BUILD_TOOLS_VERSION:-$PINNED_BUILD_TOOLS}"
ANDROID_NDK_API_LEVEL="${ANDROID_NDK_API_LEVEL:-21}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/output}"
BAZELISK_VERSION="${BAZELISK_VERSION:-$PINNED_BAZELISK_VERSION}"
FAT_APK_CPUS="${FAT_APK_CPUS:-arm64-v8a}"
SKIP_CONFIGURE="${SKIP_CONFIGURE:-0}"

# ---------------------------------------------------------------------------
# 1. Detect OS and architecture
# ---------------------------------------------------------------------------
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Linux)  BAZELISK_OS="linux" ;;
  Darwin) BAZELISK_OS="darwin" ;;
  *)      die "Unsupported OS: $OS" ;;
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
command -v java >/dev/null 2>&1    || die "Java JDK not found. Install JDK 17."
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

# Validate SDK platform exists
if [ ! -d "$ANDROID_HOME/platforms/android-$ANDROID_SDK_API_LEVEL" ]; then
  warn "SDK platform android-$ANDROID_SDK_API_LEVEL not found."
  # Fall back to auto-detection for local dev convenience
  _detected="$(ls "$ANDROID_HOME/platforms/" 2>/dev/null | grep -o '[0-9]\+' | sort -n | tail -1 || true)"
  if [ -n "$_detected" ]; then
    warn "Using detected platform android-$_detected instead."
    ANDROID_SDK_API_LEVEL="$_detected"
  else
    die "No Android platforms found. Install: sdkmanager 'platforms;android-$PINNED_SDK_API_LEVEL'"
  fi
fi
export ANDROID_SDK_API_LEVEL
info "Android SDK API level: $ANDROID_SDK_API_LEVEL"

# Validate build-tools exist
if [ ! -d "$ANDROID_HOME/build-tools/$ANDROID_BUILD_TOOLS_VERSION" ]; then
  warn "Build-tools $ANDROID_BUILD_TOOLS_VERSION not found."
  _detected="$(ls "$ANDROID_HOME/build-tools/" 2>/dev/null | grep -E '^[0-9]' | sort -V | tail -1 || true)"
  if [ -n "$_detected" ]; then
    warn "Using detected build-tools $_detected instead."
    ANDROID_BUILD_TOOLS_VERSION="$_detected"
  else
    die "No build-tools found. Install: sdkmanager 'build-tools;$PINNED_BUILD_TOOLS'"
  fi
fi
export ANDROID_BUILD_TOOLS_VERSION
info "Android build-tools: $ANDROID_BUILD_TOOLS_VERSION"

# Android NDK — Bazel only supports NDK ≤25
_find_ndk25() {
  for candidate in \
    "$ANDROID_HOME/ndk/$PINNED_NDK_VERSION" \
    "$ANDROID_HOME/ndk/25.1.8937393"; do
    if [ -d "$candidate" ]; then
      echo "$candidate"
      return
    fi
  done
  ls -d "$ANDROID_HOME/ndk"/25.* 2>/dev/null | head -1 || true
}

if [ -n "${ANDROID_NDK_HOME:-}" ] && [ -d "$ANDROID_NDK_HOME" ]; then
  _ndk_major="$(grep 'Pkg.Revision' "$ANDROID_NDK_HOME/source.properties" 2>/dev/null | grep -o '[0-9]\+' | head -1 || echo 0)"
  if [ "$_ndk_major" -gt 25 ] 2>/dev/null; then
    warn "ANDROID_NDK_HOME points to NDK $_ndk_major ($ANDROID_NDK_HOME) which is unsupported by Bazel."
    warn "Searching for NDK r25 instead..."
    _ndk25="$(_find_ndk25)"
    if [ -n "$_ndk25" ]; then
      ANDROID_NDK_HOME="$_ndk25"
    else
      die "NDK $_ndk_major is unsupported and no NDK r25 found.
    Install NDK r25b:  sdkmanager 'ndk;$PINNED_NDK_VERSION'
    Then re-run this script."
    fi
  fi
else
  ANDROID_NDK_HOME="$(_find_ndk25)"
  if [ -z "${ANDROID_NDK_HOME:-}" ]; then
    die "No NDK r25 found. Bazel only supports NDK ≤25.
    Install NDK r25b:  sdkmanager 'ndk;$PINNED_NDK_VERSION'
    Then re-run this script."
  fi
fi
export ANDROID_NDK_HOME
info "Android NDK: $ANDROID_NDK_HOME"
[ -d "$ANDROID_NDK_HOME" ] || die "Android NDK directory does not exist: $ANDROID_NDK_HOME"

# ---------------------------------------------------------------------------
# 3. Install Bazel (via Bazelisk) if not available — with SHA256 verification
# ---------------------------------------------------------------------------
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

  # Verify SHA256 checksum
  EXPECTED_SHA="${BAZELISK_SHA256["${BAZELISK_OS}-${BAZELISK_ARCH}"]:-}"
  if [ -n "$EXPECTED_SHA" ]; then
    if command -v sha256sum >/dev/null 2>&1; then
      ACTUAL_SHA="$(sha256sum "$LOCAL_BIN/bazel" | cut -d' ' -f1)"
    else
      ACTUAL_SHA="$(shasum -a 256 "$LOCAL_BIN/bazel" | cut -d' ' -f1)"
    fi
    if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
      rm -f "$LOCAL_BIN/bazel"
      die "Bazelisk SHA256 mismatch!
    Expected: $EXPECTED_SHA
    Actual:   $ACTUAL_SHA
    This could indicate a corrupted download or supply-chain attack."
    fi
    info "Bazelisk SHA256 verified: $ACTUAL_SHA"
  else
    warn "No SHA256 checksum available for ${BAZELISK_OS}-${BAZELISK_ARCH} — skipping verification."
  fi

  chmod +x "$LOCAL_BIN/bazel"
  export PATH="$LOCAL_BIN:$PATH"
  info "Bazelisk installed to $LOCAL_BIN/bazel"
  info "Bazel version: $(bazel --version 2>/dev/null | head -1)"
fi

# ---------------------------------------------------------------------------
# 4. Run TensorFlow configure (or skip if SKIP_CONFIGURE=1)
# ---------------------------------------------------------------------------
TF_DIR="$REPO_ROOT/third_party/tensorflow"
[ -d "$TF_DIR" ] || die "TensorFlow submodule not found at $TF_DIR. Run: git submodule update --init --recursive"

if [ "$SKIP_CONFIGURE" = "1" ] && [ -f "$REPO_ROOT/.tf_configure.bazelrc" ]; then
  info "Skipping TensorFlow configure (SKIP_CONFIGURE=1, using existing .tf_configure.bazelrc)"
else
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
  (yes "" || true) | ./configure
  cp .tf_configure.bazelrc "$REPO_ROOT/"
  cd "$REPO_ROOT"

  info "TensorFlow configure complete."
fi

# ---------------------------------------------------------------------------
# 5. Build the AAR
# ---------------------------------------------------------------------------
info "Building tensorflow-lite.aar (ABIs: $FAT_APK_CPUS)..."

# On macOS, force Bazel to fully re-detect the Xcode/Apple toolchain.
if [ "$OS" = "Darwin" ]; then
  info "Expunging Bazel cache to re-detect Xcode toolchain..."
  bazel clean --expunge 2>/dev/null || true
fi

# Build repository cache flag if provided
REPO_CACHE_FLAG=""
if [ -n "${BAZEL_REPO_CACHE:-}" ]; then
  if [ -d "$BAZEL_REPO_CACHE" ]; then
    REPO_CACHE_FLAG="--repository_cache=$BAZEL_REPO_CACHE"
    info "Using repository cache: $BAZEL_REPO_CACHE"
  else
    warn "BAZEL_REPO_CACHE=$BAZEL_REPO_CACHE does not exist — ignoring."
  fi
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
  ${REPO_CACHE_FLAG:+"$REPO_CACHE_FLAG"} \
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
