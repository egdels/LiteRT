# F-Droid Compatible Build

This project builds `tensorflow-lite.aar` from source without proprietary
dependencies (Google Play Services, ai-delivery).

## Strategy

The AAR is published to **Maven Central** as `de.schliweb:tensorflow-lite-fdroid`.
Apps consume it as a normal Gradle dependency — no Bazel, no custom build
infrastructure needed on F-Droid's side.

```kotlin
dependencies {
    implementation("de.schliweb:tensorflow-lite-fdroid:1.4.1-fdroid")
}
```

## Build Modes

| Mode | Command | Network | Purpose |
|------|---------|---------|---------|
| Developer | `./ci/build-fdroid.sh` | Yes | Local development, auto-detects SDK/NDK |
| Strict | `FDROID_BUILD=1 ./ci/build-fdroid.sh` | No | CI / reproducible builds |

### Strict mode (`FDROID_BUILD=1`)

- No network access — all dependencies must be pre-fetched
- No auto-detection — fails if pinned SDK/NDK versions are missing
- No Bazelisk download — requires `bazel` pre-installed
- No `./configure` — uses canonical `ci/tf_configure.bazelrc.fdroid`
- Timestamp normalization (`SOURCE_DATE_EPOCH`, `--stamp=false`, `zip -X -0`)

## Pinned Versions

| Component   | Version             |
|-------------|---------------------|
| Bazel       | 7.4.1               |
| Android SDK | API 35              |
| Build-Tools | 35.0.1              |
| NDK         | r25b (25.2.9519653) |

## Publishing

The AAR is automatically published to Maven Central via GitHub Actions when a
version tag is pushed. See `.github/workflows/publish-maven-central.yml` and
`publish/build.gradle.kts` for details.
