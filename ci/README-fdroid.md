# F-Droid Build Integration

This document explains how to build `tensorflow-lite.aar` from source in a way
that is compatible with F-Droid's build infrastructure.

## Build Modes

| Mode | Command | Network | Reproducible |
|------|---------|---------|-------------|
| Developer | `./ci/build-fdroid.sh` | Yes | No |
| F-Droid strict | `FDROID_BUILD=1 ./ci/build-fdroid.sh` | No | Yes |

### Developer mode (default)

Auto-detects SDK/NDK, downloads Bazelisk if needed, runs TF `./configure`.
Convenient but not reproducible.

### F-Droid strict mode (`FDROID_BUILD=1`)

- **No network access** — requires `BAZEL_REPO_CACHE`
- **No auto-detection** — fails if pinned SDK/NDK/build-tools versions are missing
- **No Bazelisk download** — requires `bazel` pre-installed
- **No `./configure`** — uses canonical `ci/tf_configure.bazelrc.fdroid`
- **Deterministic output** — `SOURCE_DATE_EPOCH=315532800` (1980-01-01), `--stamp=false`,
  `--workspace_status_command=/bin/true`, AAR timestamp normalization with `zip -X -0`
- **SHA256 checksum** printed for the output AAR

Required environment variables:
```bash
FDROID_BUILD=1
ANDROID_HOME=/path/to/sdk
ANDROID_NDK_HOME=/path/to/sdk/ndk/25.2.9519653
BAZEL_REPO_CACHE=/path/to/repo-cache
```

## Pinned Versions

All toolchain versions are pinned at the top of `ci/build-fdroid.sh`:

| Component    | Version             | Notes                                    |
|-------------|---------------------|------------------------------------------|
| Bazel       | 7.4.1               | Via `.bazelversion` in repo root         |
| Bazelisk    | 1.25.0              | SHA256-verified (developer mode only)    |
| Android SDK | API 35              | Platform `android-35`                    |
| Build-Tools | 35.0.1              |                                          |
| NDK         | r25b (25.2.9519653) | Bazel only supports NDK ≤25              |
| Python      | 3.12 (hermetic)     | Host Python only for configure           |
| JDK         | 17                  |                                          |

## Offline / Reproducible Builds with Repository Cache

Bazel downloads ~100 external dependencies at build time. For offline builds,
pre-populate a repository cache.

### Step 1: Generate the cache (one-time, with internet)

```bash
# Run a full build with explicit cache path
BAZEL_REPO_CACHE=/tmp/litert-repo-cache ./ci/build-fdroid.sh

# Archive the cache
tar czf bazel-repo-cache-v1.4.1.tar.gz -C /tmp litert-repo-cache
sha256sum bazel-repo-cache-v1.4.1.tar.gz > bazel-repo-cache-v1.4.1.tar.gz.sha256
```

### Step 2: Use the cache for offline builds

```bash
tar xzf bazel-repo-cache-v1.4.1.tar.gz -C /tmp
FDROID_BUILD=1 \
  ANDROID_HOME=$ANDROID_HOME \
  ANDROID_NDK_HOME=$ANDROID_HOME/ndk/25.2.9519653 \
  BAZEL_REPO_CACHE=/tmp/litert-repo-cache \
  ./ci/build-fdroid.sh
```

### Step 3: Publish the cache

Upload `bazel-repo-cache-v1.4.1.tar.gz` as a GitHub Release asset alongside
the source tag. Document its SHA256 checksum.

## Pinning Maven Dependencies

The WORKSPACE uses `maven_install` with a lock file for reproducibility:

```bash
# Generate/update the lock file (requires network)
bazel run @litert_maven//:pin

# Commit the result
git add maven_install.json
git commit -m "Pin maven_install.json"
```

**This must be done whenever Maven artifacts in WORKSPACE change.**
The lock file contains SHA256 checksums for all transitive Maven dependencies.

**Status:** `maven_install.json` must be generated and committed before the
first F-Droid build. Without it, `rules_jvm_external` will fail.

## TensorFlow Configure

The `./configure` step probes the host environment and is **non-deterministic**.

For F-Droid builds, a canonical `ci/tf_configure.bazelrc.fdroid` is shipped in
the repo. When `FDROID_BUILD=1`, it is used automatically — `./configure` is
never run.

The `tf_configure.bazelrc.fdroid` contains hardcoded Debian paths
(`/usr/bin/python3`, `/usr/lib/python3/dist-packages`). This is acceptable
because F-Droid builds run on Debian and Bazel uses hermetic Python 3.12
regardless.

For developer builds, `./configure` runs by default. You can skip it with:
```bash
SKIP_CONFIGURE=1 ./ci/build-fdroid.sh
```

## Vendor SDKs

Vendor SDK workspace loads (Qualcomm QAIRT, MediaTek NeuroPilot, Google Tensor,
LiteRT GPU) are **disabled** in the WORKSPACE for F-Droid builds. They download
proprietary binaries without SHA256 verification and are not needed for the base
`tensorflow-lite.aar`.

To re-enable for development with vendor delegates, uncomment the corresponding
lines at the bottom of `WORKSPACE`.

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
    sudo:
      - apt-get update
      - apt-get install -y bazel python3 zip unzip
    srclibs:
      - LiteRT@v1.4.1-fdroid
    prebuild:
      - sdkmanager 'platforms;android-35' 'build-tools;35.0.1' 'ndk;25.2.9519653'
      # Download and verify repository cache
      - curl -fSL -o /tmp/repo-cache.tar.gz
        https://github.com/<org>/LiteRT-github/releases/download/v1.4.1-fdroid/bazel-repo-cache-v1.4.1.tar.gz
      - echo "<sha256>  /tmp/repo-cache.tar.gz" | sha256sum -c -
      - tar xzf /tmp/repo-cache.tar.gz -C /tmp
    build:
      - cd $$LiteRT$$
      - FDROID_BUILD=1
        ANDROID_HOME=$$SDK$$
        ANDROID_NDK_HOME=$$NDK$$/25.2.9519653
        BAZEL_REPO_CACHE=/tmp/litert-repo-cache
        ./ci/build-fdroid.sh
      - cp $$LiteRT$$/output/tensorflow-lite.aar $$out$$/app/libs/
    ndk: 25.2.9519653
```

**Key points for F-Droid acceptance:**
- `sudo:` installs Bazel (no Bazelisk download during build)
- `prebuild:` downloads the repo cache (allowed — prebuild has network)
- `build:` runs with `FDROID_BUILD=1` (no network, deterministic)
- All Maven deps are pinned via `maven_install.json`
- No proprietary dependencies (vendor SDKs disabled in WORKSPACE)
- `org_tensorflow` uses local source only (no remote URL fallback)

## Reproducibility Checklist

- [ ] `maven_install.json` committed and up-to-date
- [ ] `ci/tf_configure.bazelrc.fdroid` matches target build environment (Debian)
- [ ] Repository cache generated and published as release asset
- [ ] `FDROID_BUILD=1` build produces identical AAR SHA256 across runs
- [ ] Vendor SDK loads disabled in WORKSPACE
- [ ] `org_tensorflow` has no remote URL fallback (`urls = []`)

## CI Workflow Limitations

The GitHub Actions workflow (`.github/workflows/build-fdroid-aar.yml`) uses a
two-phase approach: Phase 1 fetches dependencies, Phase 2 builds with
`FDROID_BUILD=1`. However, `bazel clean` (without `--expunge`) between phases
does **not** fully clear external repos from the output base. This means Phase 2
does not truly validate that the repo cache alone is sufficient for a cold-start
build. True cold-start validation must be done on a clean VM.

## Known Limitations

- **XNNPACK disabled**: Due to API version mismatch with the pinned dependency.
  Performance regression for CPU inference. NNAPI delegate still available.

- **Multi-ABI builds**: Only `arm64-v8a` is fully tested. Set
  `FAT_APK_CPUS=arm64-v8a` if other ABIs cause issues.

- **Build duration**: 5–15 minutes from scratch. F-Droid VMs may need extended
  timeouts.

- **Vendored files**: ~20 files copied from TensorFlow upstream. See
  `VENDORED_FROM.md` for provenance tracking and upgrade procedure.

- **Bazel version coupling**: TensorFlow + Bazel compatibility is fragile.
  Upgrading TF likely requires a new Bazel version and re-vendoring.

- **SOURCE_DATE_EPOCH**: Set to `315532800` (1980-01-01T00:00:00Z) to avoid
  ZIP format issues with timestamps before 1980. F-Droid may override this.
