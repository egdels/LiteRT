# F-Droid Build Integration

This document explains how to build `tensorflow-lite.aar` from source in a way
that is compatible with F-Droid's build infrastructure.

## Quick Start

```bash
./ci/build-fdroid.sh
```

The AAR will be written to `output/tensorflow-lite.aar`.

## Pinned Versions

All toolchain versions are pinned at the top of `ci/build-fdroid.sh`:

| Component    | Version         | Notes                                    |
|-------------|-----------------|------------------------------------------|
| Bazel       | 7.4.1           | Via `.bazelversion` in repo root         |
| Bazelisk    | 1.25.0          | SHA256-verified download                 |
| Android SDK | API 35          | Platform `android-35`                    |
| Build-Tools | 35.0.1          |                                          |
| NDK         | r25b (25.2.9519653) | Bazel only supports NDK ≤25          |
| Python      | 3.12 (hermetic) | Bazel uses hermetic Python, host Python only for configure |
| JDK         | 17              |                                          |

## Offline / Reproducible Builds with Repository Cache

Bazel downloads ~100 external dependencies at build time. To make builds
offline-capable and reproducible, you can pre-populate a repository cache:

### Step 1: Generate the cache (one-time, with internet)

```bash
# Build once to populate Bazel's repository cache
./ci/build-fdroid.sh

# Find and archive the repository cache
REPO_CACHE="$(bazel info repository_cache)"
tar czf bazel-repo-cache-v1.4.1.tar.gz -C "$(dirname "$REPO_CACHE")" "$(basename "$REPO_CACHE")"
```

### Step 2: Use the cache for offline builds

```bash
# Extract the cache
mkdir -p /tmp/repo-cache
tar xzf bazel-repo-cache-v1.4.1.tar.gz -C /tmp/repo-cache

# Build with cache (no network needed)
BAZEL_REPO_CACHE=/tmp/repo-cache/repository_cache ./ci/build-fdroid.sh
```

### Step 3: Publish the cache

Upload `bazel-repo-cache-v1.4.1.tar.gz` as a GitHub Release asset alongside
the source tag. Document its SHA256 checksum.

## Skipping TensorFlow Configure

The `./configure` step in TensorFlow generates `.tf_configure.bazelrc` based on
the current system. For reproducible builds, you can:

1. Run configure once on a reference system
2. Commit the resulting `.tf_configure.bazelrc` to the repo
3. Set `SKIP_CONFIGURE=1` when building

```bash
SKIP_CONFIGURE=1 ./ci/build-fdroid.sh
```

## F-Droid Metadata (fdroiddata)

### srclib registration (`srclibs/LiteRT.yml`)

```yaml
RepoType: git
Repo: https://github.com/<org>/LiteRT-github.git
```

### App build recipe (e.g. `metadata/com.example.fairscan.yml`)

```yaml
Builds:
  - versionName: '1.0.0'
    versionCode: 100
    commit: v1.0.0
    subdir: app
    submodules: true
    srclibs:
      - LiteRT@v1.4.1-patch
    prebuild:
      # Install required SDK components
      - sdkmanager 'platforms;android-35' 'build-tools;35.0.1' 'ndk;25.2.9519653'
    build:
      # Build the AAR from source
      - cd $$LiteRT$$
      - ANDROID_HOME=$$SDK$$ ANDROID_NDK_HOME=$$NDK$$ ./ci/build-fdroid.sh
      - cp output/tensorflow-lite.aar $$out$$/app/libs/
    ndk: 25.2.9519653
```

### With pre-populated repository cache

```yaml
Builds:
  - versionName: '1.0.0'
    versionCode: 100
    commit: v1.0.0
    subdir: app
    submodules: true
    srclibs:
      - LiteRT@v1.4.1-patch
    prebuild:
      - sdkmanager 'platforms;android-35' 'build-tools;35.0.1' 'ndk;25.2.9519653'
      # Download and verify repository cache
      - curl -fSL -o /tmp/repo-cache.tar.gz https://github.com/<org>/LiteRT-github/releases/download/v1.4.1-patch/bazel-repo-cache-v1.4.1.tar.gz
      - echo "<sha256>  /tmp/repo-cache.tar.gz" | sha256sum -c -
      - mkdir -p /tmp/repo-cache && tar xzf /tmp/repo-cache.tar.gz -C /tmp/repo-cache
    build:
      - cd $$LiteRT$$
      - ANDROID_HOME=$$SDK$$ ANDROID_NDK_HOME=$$NDK$$ BAZEL_REPO_CACHE=/tmp/repo-cache/repository_cache ./ci/build-fdroid.sh
      - cp output/tensorflow-lite.aar $$out$$/app/libs/
    ndk: 25.2.9519653
```

## Known Limitations

- **Multi-ABI builds**: Only `arm64-v8a` is fully tested. The `armeabi-v7a` ABI
  may fail due to `@platforms//cpu:` config_setting mismatches with Bazel's
  legacy Android toolchain resolution. Set `FAT_APK_CPUS=arm64-v8a` if you
  encounter issues.

- **Build duration**: A full Bazel build from scratch takes 5–15 minutes
  depending on the machine. F-Droid build VMs may have timeouts.

- **Upstream fragility**: This build relies on ~20 patched source files and 5
  locally vendored libraries from TensorFlow. Upgrading the TF submodule
  requires re-validating all patches.
