#!/usr/bin/env bash
# ============================================================================
# build-fdroid.sh — Build tensorflow-lite.aar from source (F-Droid compatible)
#
# This script builds the LiteRT Android AAR without Docker, suitable for:
#   - F-Droid build VMs (Debian/Linux x86_64)  — use FDROID_BUILD=1
#   - Local development (macOS, Linux)          — use FDROID_BUILD=0 (default)
#   - GitHub Actions (via build-fdroid-aar.yml)
#
# Modes:
#   FDROID_BUILD=0 (default) — developer mode with auto-detection, Bazelisk
#                               download, and TF configure.
#   FDROID_BUILD=1           — strict mode: no network, no auto-detection,
#                               no downloads, deterministic output.
#
# F-Droid strict mode requires:
#   - Bazel pre-installed (exact version from .bazelversion)
#   - ANDROID_HOME, ANDROID_NDK_HOME set to exact pinned versions
#   - BAZEL_REPO_CACHE pointing to a pre-populated repository cache
#   - Canonical .tf_configure.bazelrc (shipped in ci/)
#
# Prerequisites:
#   - Java JDK 17
#   - Android SDK with platform android-35 and build-tools 35.0.1
#   - Android NDK r25b (version 25.2.9519653) — Bazel only supports NDK ≤25
#   - Python 3.9–3.12
#   - Internet access (unless FDROID_BUILD=1 with BAZEL_REPO_CACHE)
#
# Environment variables (all optional unless FDROID_BUILD=1):
#   FDROID_BUILD              — Set to 1 for strict reproducible mode
#   ANDROID_HOME              — Path to Android SDK (auto-detected in dev mode)
#   ANDROID_NDK_HOME          — Path to Android NDK (auto-detected in dev mode)
#   ANDROID_SDK_API_LEVEL     — SDK API level (default: 35)
#   ANDROID_NDK_API_LEVEL     — NDK minimum API level (default: 21)
#   ANDROID_BUILD_TOOLS_VERSION — Build tools version (default: 35.0.1)
#   OUTPUT_DIR                — Where to copy the AAR (default: ./output)
#   BAZELISK_VERSION          — Bazelisk version to install (default: 1.25.0)
#   FAT_APK_CPUS              — Comma-separated ABIs (default: arm64-v8a)
#   BAZEL_REPO_CACHE          — Path to pre-populated Bazel repository cache
#                               (required in FDROID_BUILD=1; see ci/README-fdroid.md)
#   SKIP_CONFIGURE            — Set to 1 to skip TF configure (forced in FDROID_BUILD=1)
#
# Generating the repository cache (run once with network access):
#   bazel fetch //tflite/java:tensorflow-lite \
#     --config=android --cpu=armeabi-v7a --fat_apk_cpu=arm64-v8a \
#     --repository_cache=/path/to/cache
#   # Then archive /path/to/cache for offline use.
#
# F-Droid metadata example (fdroiddata):
#   build:
#     sudo:
#       - apt-get install -y bazel=7.4.1 python3
#     srclibs:
#       - LiteRT@v1.4.1-fdroid
#     prebuild:
#       - sdkmanager 'platforms;android-35' 'build-tools;35.0.1' 'ndk;25.2.9519653'
#     build:
#       - cd $$LiteRT$$
#       - FDROID_BUILD=1 ANDROID_HOME=$$SDK$$ ANDROID_NDK_HOME=$$NDK$$/25.2.9519653
#         BAZEL_REPO_CACHE=$$LiteRT$$/bazel-repo-cache
#         ./ci/build-fdroid.sh
#       - cp $$LiteRT$$/output/tensorflow-lite.aar app/libs/
#     ndk: 25.2.9519653
#
# Usage:
#   ./ci/build-fdroid.sh                    # developer mode
#   FDROID_BUILD=1 ./ci/build-fdroid.sh     # strict F-Droid mode
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

# Bazelisk SHA256 checksums (v1.25.0) — only used in developer mode
declare -A BAZELISK_SHA256=(
  ["linux-amd64"]="fd8fdff418a1758887520fa42da7e6ae39aefc788cf5e7f7bb8db6934d279fc4"
  ["linux-arm64"]="4c8d966e40ac2c4efcc7f1a5a5cceef2c0a2f16b957e791fa7a867cce31e8fcb"
  ["darwin-amd64"]="0af019eeb642fa70744419d02aa32df55e6e7a084105d49fb26801a660aa56d3"
  ["darwin-arm64"]="b13dd89c6ecd90944ca3539f5a2c715a18f69b7458878c471a902a8e482ceb4b"
)

# ---------------------------------------------------------------------------
# Mode selection
# ---------------------------------------------------------------------------
FDROID_BUILD="${FDROID_BUILD:-0}"
if [ "$FDROID_BUILD" = "1" ]; then
  info "=== F-DROID STRICT BUILD MODE ==="
  info "No network access, no auto-detection, deterministic output."
fi

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
FAT_APK_CPUS="${FAT_APK_CPUS:-arm64-v8a,armeabi-v7a,x86_64,x86}"
SKIP_CONFIGURE="${SKIP_CONFIGURE:-0}"

# ---------------------------------------------------------------------------
# Reproducibility: SOURCE_DATE_EPOCH
# ---------------------------------------------------------------------------
# Pin to a fixed epoch for deterministic timestamps in ZIP/AAR files.
# Use 1980-01-01 (not 0/1970) because ZIP format requires timestamps >= 1980.
# F-Droid sets this automatically, but we enforce it here as well.
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-315532800}"
if [ "$FDROID_BUILD" = "1" ]; then
  info "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH"
fi

# ---------------------------------------------------------------------------
# F-Droid strict mode: enforce constraints
# ---------------------------------------------------------------------------
if [ "$FDROID_BUILD" = "1" ]; then
  SKIP_CONFIGURE=1

  [ -n "${ANDROID_HOME:-}" ] || die "FDROID_BUILD=1 requires ANDROID_HOME to be set."
  [ -n "${ANDROID_NDK_HOME:-}" ] || die "FDROID_BUILD=1 requires ANDROID_NDK_HOME to be set."
  [ -n "${BAZEL_REPO_CACHE:-}" ] || die "FDROID_BUILD=1 requires BAZEL_REPO_CACHE to be set."
  [ -d "${BAZEL_REPO_CACHE}" ] || die "BAZEL_REPO_CACHE does not exist: $BAZEL_REPO_CACHE"

  # Enforce pinned versions — no fallbacks
  [ "$ANDROID_SDK_API_LEVEL" = "$PINNED_SDK_API_LEVEL" ] || die "FDROID_BUILD=1 requires ANDROID_SDK_API_LEVEL=$PINNED_SDK_API_LEVEL (got $ANDROID_SDK_API_LEVEL)"
  [ "$ANDROID_BUILD_TOOLS_VERSION" = "$PINNED_BUILD_TOOLS" ] || die "FDROID_BUILD=1 requires ANDROID_BUILD_TOOLS_VERSION=$PINNED_BUILD_TOOLS (got $ANDROID_BUILD_TOOLS_VERSION)"

  # Validate exact paths exist
  [ -d "$ANDROID_HOME/platforms/android-$PINNED_SDK_API_LEVEL" ] || die "SDK platform android-$PINNED_SDK_API_LEVEL not found in $ANDROID_HOME"
  [ -d "$ANDROID_HOME/build-tools/$PINNED_BUILD_TOOLS" ] || die "Build-tools $PINNED_BUILD_TOOLS not found in $ANDROID_HOME"
  [ -d "$ANDROID_NDK_HOME" ] || die "ANDROID_NDK_HOME does not exist: $ANDROID_NDK_HOME"

  # Verify NDK is r25
  _ndk_major="$(grep 'Pkg.Revision' "$ANDROID_NDK_HOME/source.properties" 2>/dev/null | grep -o '[0-9]\+' | head -1 || echo 0)"
  [ "$_ndk_major" = "25" ] || die "FDROID_BUILD=1 requires NDK r25 (got r$_ndk_major at $ANDROID_NDK_HOME)"

  command -v bazel >/dev/null 2>&1 || die "FDROID_BUILD=1 requires bazel to be pre-installed (no Bazelisk download)."
fi

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

# --- Android SDK (developer mode: auto-detect; strict mode: already validated) ---
if [ "$FDROID_BUILD" != "1" ]; then
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
  [ -d "$ANDROID_HOME" ] || die "Android SDK directory does not exist: $ANDROID_HOME"

  # Auto-detect SDK platform (developer convenience only)
  if [ ! -d "$ANDROID_HOME/platforms/android-$ANDROID_SDK_API_LEVEL" ]; then
    warn "SDK platform android-$ANDROID_SDK_API_LEVEL not found."
    _detected="$(ls "$ANDROID_HOME/platforms/" 2>/dev/null | grep -o '[0-9]\+' | sort -n | tail -1 || true)"
    if [ -n "$_detected" ]; then
      warn "Using detected platform android-$_detected instead."
      ANDROID_SDK_API_LEVEL="$_detected"
    else
      die "No Android platforms found. Install: sdkmanager 'platforms;android-$PINNED_SDK_API_LEVEL'"
    fi
  fi

  # Auto-detect build-tools (developer convenience only)
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

  # Auto-detect NDK r25 (developer convenience only)
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
fi

export ANDROID_HOME
export ANDROID_SDK_API_LEVEL
export ANDROID_BUILD_TOOLS_VERSION
export ANDROID_NDK_HOME

info "Android SDK: $ANDROID_HOME"
info "Android SDK API level: $ANDROID_SDK_API_LEVEL"
info "Android build-tools: $ANDROID_BUILD_TOOLS_VERSION"
info "Android NDK: $ANDROID_NDK_HOME"
[ -d "$ANDROID_NDK_HOME" ] || die "Android NDK directory does not exist: $ANDROID_NDK_HOME"

# ---------------------------------------------------------------------------
# 3. Install Bazel (via Bazelisk) — developer mode only
# ---------------------------------------------------------------------------
export USE_BAZEL_VERSION="$(cat "$REPO_ROOT/.bazelversion" 2>/dev/null || echo '7.4.1')"
info "Bazel version pinned to: $USE_BAZEL_VERSION"

if command -v bazel >/dev/null 2>&1; then
  # Use startup args (e.g. --output_user_root) even for --version,
  # because Bazel creates its output base on ANY invocation.
  if [ -n "${BAZEL_STARTUP_ARGS:-}" ]; then
    read -ra _STARTUP_CHECK <<< "$BAZEL_STARTUP_ARGS"
    info "Bazel found: $(bazel "${_STARTUP_CHECK[@]}" --version 2>/dev/null | head -1)"
  else
    info "Bazel found: $(bazel --version 2>/dev/null | head -1)"
  fi
elif [ "$FDROID_BUILD" = "1" ]; then
  die "FDROID_BUILD=1 requires bazel to be pre-installed."
else
  info "Bazel not found — installing Bazelisk v${BAZELISK_VERSION} (developer mode)..."
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
# 4. TensorFlow configure
# ---------------------------------------------------------------------------
TF_DIR="$REPO_ROOT/third_party/tensorflow"
[ -d "$TF_DIR" ] || die "TensorFlow submodule not found at $TF_DIR. Run: git submodule update --init --recursive"

if [ "$SKIP_CONFIGURE" = "1" ]; then
  # Use canonical F-Droid bazelrc if available, otherwise existing one
  if [ "$FDROID_BUILD" = "1" ] && [ -f "$SCRIPT_DIR/tf_configure.bazelrc.fdroid" ]; then
    info "Using canonical F-Droid .tf_configure.bazelrc"
    cp "$SCRIPT_DIR/tf_configure.bazelrc.fdroid" "$REPO_ROOT/.tf_configure.bazelrc"
  elif [ -f "$REPO_ROOT/.tf_configure.bazelrc" ]; then
    info "Skipping TensorFlow configure (SKIP_CONFIGURE=1, using existing .tf_configure.bazelrc)"
  else
    die "SKIP_CONFIGURE=1 but no .tf_configure.bazelrc found. Run configure first or use FDROID_BUILD=1."
  fi
else
  info "Running TensorFlow configure (developer mode)..."

  export TF_SET_ANDROID_WORKSPACE=1
  export ANDROID_SDK_HOME="$ANDROID_HOME"
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
# 5. Patch XNNPACK version for API compatibility
# ---------------------------------------------------------------------------
# The xnnpack_delegate.cc in tflite/ requires a newer XNNPACK than what the
# TF submodule pins. Patch workspace2.bzl at build time to avoid modifying
# the submodule (which would break CI checkout).
# Patch all workspace files that pin XNNPACK to ensure the correct version
# is used regardless of which file Bazel loads first.
XNNPACK_PATCH_FILES=(
  "$TF_DIR/third_party/xla/third_party/tsl/workspace2.bzl"
  "$TF_DIR/tensorflow/workspace2.bzl"
)
XNNPACK_PATCHED=0
for XNNPACK_BZL in "${XNNPACK_PATCH_FILES[@]}"; do
  if [ -f "$XNNPACK_BZL" ]; then
    info "Patching XNNPACK version in $XNNPACK_BZL..."
    sed -i.bak \
      -e 's|a50369c0fdd15f0f35b1a91c964644327a88d480|e757940dbdcf465fd9eb7901ce73f4ff21387663|g' \
      -e 's|ca3a5316b8161214f8f22a578fb638f1fccd0585eee40301363ffd026310379a|eb01826f3820284b89076e94e4458a7326dc6986bdaf5cdc61bb2f26db12aab1|g' \
      -e 's|9ddeb74f9f6866174d61888947e4aa9ffe963b1b|e757940dbdcf465fd9eb7901ce73f4ff21387663|g' \
      -e 's|0e5d5c16686beff813e3946b26ca412f28acaf611228d20728ffb6479264fe19|eb01826f3820284b89076e94e4458a7326dc6986bdaf5cdc61bb2f26db12aab1|g' \
      -e 's|b8374f80e42010941bda6c85b0e3f1a1bd77a1e0|c2ba5c50bb58d1397b693740cf75fad836a0d1bf|g' \
      -e 's|b96413b10dd8edaa4f6c0a60c6cf5ef55eebeef78164d5d69294c8173457f0ec|516ba8d05c30e016d7fd7af6a7fc74308273883f857faf92bc9bb630ab6dba2c|g' \
      -e 's|4fe0e1e183925bf8cfa6aae24237e724a96479b8|c2ba5c50bb58d1397b693740cf75fad836a0d1bf|g' \
      -e 's|a4cf06de57bfdf8d7b537c61f1c3071bce74e57524fe053e0bbd2332feca7f95|516ba8d05c30e016d7fd7af6a7fc74308273883f857faf92bc9bb630ab6dba2c|g' \
      -e 's|5e63739504f0f8e18e941bd63b2d6d42536c7d90|33ed0be77d7767d0e2010e2c3cf972ef36c7c307|g' \
      -e 's|18eca9bc8d9c4ce5496d0d2be9f456d55cbbb5f0639a551ce9c8bac2e84d85fe|b7be544ab78e16f5a89a7184c60e234fab7bbd84148da6f7a36b5a2e9759446c|g' \
      -e 's|3c8b1533ac03dd6531ab6e7b9245d488f13a82a5|33ed0be77d7767d0e2010e2c3cf972ef36c7c307|g' \
      -e 's|5d7f00693e97bd7525753de94be63f99b0490ae6855df168f5a6b2cfc452e49e|b7be544ab78e16f5a89a7184c60e234fab7bbd84148da6f7a36b5a2e9759446c|g' \
      -e 's|cddf991af5de49fd34949fa39690e4e906e04074|45bf06030727ce049793ce6749e943cc2ea896fe|g' \
      -e 's|88233e427be6579560073267575f00f3b5fc370a31a43bbdd87a1810bd4bf1b6|919683ceeedd6dd9db26c341eef448f9096616dfc4e9270e0209e481921e78e4|g' \
      -e 's|gitlab.arm.com/kleidi/kleidiai/-/archive|github.com/ARM-software/kleidiai/archive|g' \
      "$XNNPACK_BZL"
    rm -f "${XNNPACK_BZL}.bak"
    XNNPACK_PATCHED=$((XNNPACK_PATCHED + 1))
  fi
done
if [ "$XNNPACK_PATCHED" -gt 0 ]; then
  info "XNNPACK + pthreadpool + cpuinfo + KleidiAI patched in $XNNPACK_PATCHED file(s)."
else
  warn "No workspace2.bzl files found — skipping XNNPACK patch."
fi

# ---------------------------------------------------------------------------
# 6. Build the AAR
# ---------------------------------------------------------------------------
info "Building tensorflow-lite.aar (ABIs: $FAT_APK_CPUS)..."

# On macOS, force Bazel to fully re-detect the Xcode/Apple toolchain.
if [ "$OS" = "Darwin" ] && [ "$FDROID_BUILD" != "1" ]; then
  info "Expunging Bazel cache to re-detect Xcode toolchain..."
  bazel clean --expunge 2>/dev/null || true
fi

# Build flags
BAZEL_FLAGS=(
  -c opt
  --cxxopt=--std=c++17
  --config=android
  --cpu=armeabi-v7a
  --fat_apk_cpu="$FAT_APK_CPUS"
  --define=android_dexmerger_tool=d8_dexmerger
  --define=android_incremental_dexing_tool=d8_dexbuilder
  --repo_env=HERMETIC_PYTHON_VERSION=3.12
)

# Reproducibility flags
BAZEL_FLAGS+=(
  --stamp=false
  --workspace_status_command=/bin/true
)

# Repository cache (required in strict mode, optional in dev mode)
if [ -n "${BAZEL_REPO_CACHE:-}" ]; then
  if [ -d "$BAZEL_REPO_CACHE" ]; then
    BAZEL_FLAGS+=("--repository_cache=$BAZEL_REPO_CACHE")
    info "Using repository cache: $BAZEL_REPO_CACHE"
  elif [ "$FDROID_BUILD" = "1" ]; then
    die "BAZEL_REPO_CACHE=$BAZEL_REPO_CACHE does not exist."
  else
    warn "BAZEL_REPO_CACHE=$BAZEL_REPO_CACHE does not exist — ignoring."
  fi
fi

# Allow extra Bazel build args (e.g. --batch for network-isolated environments)
if [ -n "${BAZEL_EXTRA_ARGS:-}" ]; then
  read -ra _EXTRA <<< "$BAZEL_EXTRA_ARGS"
  BAZEL_FLAGS+=("${_EXTRA[@]}")
fi

# Startup flags (must come before the 'build' command)
BAZEL_STARTUP_FLAGS=()
if [ -n "${BAZEL_STARTUP_ARGS:-}" ]; then
  read -ra _STARTUP <<< "$BAZEL_STARTUP_ARGS"
  BAZEL_STARTUP_FLAGS+=("${_STARTUP[@]}")
fi

if [ ${#BAZEL_STARTUP_FLAGS[@]} -gt 0 ]; then
  bazel "${BAZEL_STARTUP_FLAGS[@]}" build "${BAZEL_FLAGS[@]}" //tflite/java:tensorflow-lite
else
  bazel build "${BAZEL_FLAGS[@]}" //tflite/java:tensorflow-lite
fi

# ---------------------------------------------------------------------------
# 7. Normalize AAR for reproducibility
# ---------------------------------------------------------------------------
AAR_PATH="$REPO_ROOT/bazel-bin/tflite/java/tensorflow-lite.aar"
[ -f "$AAR_PATH" ] || die "AAR not found at expected path: $AAR_PATH"

mkdir -p "$OUTPUT_DIR"

if [ "$FDROID_BUILD" = "1" ]; then
  info "Normalizing AAR timestamps for reproducibility..."
  _REPACK_DIR="$(mktemp -d)"
  trap 'rm -rf "$_REPACK_DIR"' EXIT
  cd "$_REPACK_DIR"
  unzip -q -o "$AAR_PATH"
  # Set all timestamps to SOURCE_DATE_EPOCH
  _TOUCH_DATE="$(TZ=UTC date -d "@$SOURCE_DATE_EPOCH" '+%Y%m%d%H%M.%S' 2>/dev/null || TZ=UTC date -r "$SOURCE_DATE_EPOCH" '+%Y%m%d%H%M.%S' 2>/dev/null || echo '197001010000.00')"
  find . -exec touch -t "$_TOUCH_DATE" {} +
  # Repack with deterministic ordering and no extra metadata
  # Use -0 (store) to eliminate zlib version differences across systems
  find . -type f | LC_ALL=C sort | TZ=UTC zip -X -0 -q "$OUTPUT_DIR/tensorflow-lite.aar" -@
  cd "$REPO_ROOT"
  info "AAR normalized with SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH"
else
  cp "$AAR_PATH" "$OUTPUT_DIR/tensorflow-lite.aar"
fi

# ---------------------------------------------------------------------------
# 8. Output checksum
# ---------------------------------------------------------------------------
if command -v sha256sum >/dev/null 2>&1; then
  AAR_SHA="$(sha256sum "$OUTPUT_DIR/tensorflow-lite.aar" | cut -d' ' -f1)"
else
  AAR_SHA="$(shasum -a 256 "$OUTPUT_DIR/tensorflow-lite.aar" | cut -d' ' -f1)"
fi

info "============================================"
info "Build successful!"
info "AAR:    $OUTPUT_DIR/tensorflow-lite.aar"
info "SHA256: $AAR_SHA"
info "============================================"
