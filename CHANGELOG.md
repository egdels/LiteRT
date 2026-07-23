# Changelog

## [Unreleased]

### Known Issues

- A compatibility issue has been reported for an ALBERT transformer model:
  inference completes, but sigmoid outputs saturate to `0.0` or `1.0`,
  while Google's official LiteRT runtime produces the expected probabilities.
- The issue reportedly also occurs with XNNPACK disabled.
- The cause has not yet been identified.
- Until this is resolved, the artifact must not be assumed to be a universal
  drop-in replacement for Google's official LiteRT binaries.

## [1.4.1-patch2] - 2026-04-23

### Changed

- **XNNPACK re-enabled**: Removed `--define=tflite_with_xnnpack=false`, `--define=tflite_kernel_use_xnnpack=false`, and `--copt=-DTF_LITE_DISABLE_X86_NEON` from `ci/build-fdroid.sh` and `.github/workflows/build-fdroid-aar.yml`. XNNPACK is now built with the default (enabled) configuration, matching the upstream Maven artifact. This fixes a SIGSEGV crash (`signal 11, SEGV_MAPERR, fault addr 0x8`) in `libtensorflowlite_jni.so` during inference on older ARM64 devices (e.g. Galaxy S7/S9, Android 12) reported in [FairScan#155](https://github.com/pynicolas/FairScan/issues/155).
- **XNNPACK version upgraded**: The pinned XNNPACK dependency is patched at build time (in `ci/build-fdroid.sh` and `.github/workflows/build-fdroid-aar.yml`) to `e757940dbdcf` in **both** `tsl/workspace2.bzl` and `tensorflow/workspace2.bzl` to match the API version expected by the `xnnpack_delegate.cc` in `tflite/delegates/xnnpack/`. Both files must be patched because Bazel uses whichever definition is loaded first. The old versions (`a50369c0fdd1` in TSL, `9ddeb74f9f68` in TF) lacked newer APIs (`xnn_binary_operator`, `xnn_reduce_operator`, `XNN_FLAG_SLOW_CONSISTENT_ARITHMETIC`, etc.) required by the delegate code. The TF submodule itself remains unmodified to avoid CI checkout failures.
- **pthreadpool version upgraded**: The pinned pthreadpool dependency is also patched at build time from `b8374f80e420` (TSL) / `4fe0e1e183925` (TF) to `c2ba5c50bb58` to match the version required by XNNPACK `e757940dbdcf`. The old pthreadpool lacked `*_dynamic_*` task types (`pthreadpool_task_1d_tile_1d_dynamic_with_id_t`, etc.) needed by the newer XNNPACK.
- **cpuinfo version upgraded**: The pinned cpuinfo dependency is also patched at build time from `5e63739504f0` (TSL) / `3c8b1533ac03` (TF) to `33ed0be77d77` to match the version required by XNNPACK `e757940dbdcf`. The old cpuinfo lacked newer CPU microarchitecture identifiers (`cpuinfo_uarch_cortex_x4`, `cpuinfo_uarch_oryon`) referenced by XNNPACK's hardware configuration code.
- **KleidiAI version upgraded**: The pinned KleidiAI dependency is patched at build time from `cddf991af5de` (TF) to `45bf06030727` to match the version required by XNNPACK `e757940dbdcf`. The URL is also changed from GitLab (`gitlab.arm.com/kleidi/kleidiai`) to GitHub (`github.com/ARM-software/kleidiai`). The old KleidiAI lacked ARM SME microkernel headers (`kai_rhs_imatmul_pack_kxn_qsi8cxp2vlx4sb_qs8cx_f32_i32_sme.h`) referenced by XNNPACK's `packing.cc`.

### Background

The upstream LiteRT repo has an inherent version mismatch: the `xnnpack_delegate.cc` in `tflite/delegates/xnnpack/` uses newer XNNPACK APIs (`xnn_binary_operator`, `xnn_reduce_operator`, etc.), but the XNNPACK version pinned via the TF submodule (`third_party/tensorflow/.../workspace2.bzl`) is older and lacks these APIs. This mismatch exists in the public repo but does not affect Google because:

1. **Google internally** builds the official Maven artifact with Blaze (not Bazel), which resolves a matching newer XNNPACK version.
2. **CMake users** use `tflite/tools/cmake/modules/xnnpack.cmake`, which pins its own XNNPACK version independently of the TF submodule.
3. **Bazel users** who disable XNNPACK (as the original fork did) never compile the delegate, so the mismatch is hidden.

Only Bazel builds with XNNPACK enabled — our case — hit the compile errors. The original fork author likely encountered these errors and disabled XNNPACK as a workaround, which inadvertently caused the SIGSEGV crash on older devices. See also [LiteRT#1972](https://github.com/google-ai-edge/LiteRT/issues/1972) and [LiteRT#3207](https://github.com/google-ai-edge/LiteRT/issues/3207) for related upstream reports about the outdated TF submodule.

### Notes

- The AAR size increases by ~10–20 MB due to XNNPACK native code for 4 ABIs — this is expected and matches the upstream artifact.
- The Bazel repository cache must be regenerated (happens automatically in Phase 1 of the GitHub Actions workflow).

---

## [1.4.1-patch] - 2026-04-15

### Overview

This release patches LiteRT v1.4.1 to enable building the `tensorflow-lite.aar` Android artifact from source using GitHub Actions. The primary motivation is F-Droid compatibility ([FairScan#155](https://github.com/pynicolas/FairScan/issues/155)), which requires all dependencies to be buildable from FLOSS source code without proprietary build-time dependencies.

### Added

- **CI/CD: GitHub Actions workflow** (`build-litert-aar.yml`) to build the LiteRT Android AAR from source inside a Docker container with Bazel, Android SDK, and NDK.
- **Dockerfile**: `ci/tflite-android.Dockerfile` updated to install Android SDK platform tools, build tools (35.0.1), and platform (android-35) via `sdkmanager`.
- **Stub CUDA/NCCL repositories** (`third_party/cuda_stub/`) providing no-op implementations of `cuda_library`, `if_cuda`, `if_cuda_is_configured`, `if_cuda_exec`, and `cuda_default_copts` — required by TensorFlow's `tensorflow.bzl` but unused for Android builds.
- **Local library copies** to resolve Bazel visibility restrictions between `//tflite/` and `@org_tensorflow//` packages:
  - `third_party/allocation/` — `Allocation`, `MMAPAllocation`, `FileCopyAllocation`, `MemoryAllocation` classes
  - `third_party/string_utils/` — `SimpleDynamicBuffer`, `StringRef`, string tensor utilities
  - `third_party/metadata_util/` — model control dependency serialization/deserialization
  - `third_party/model_builder_base/` — `FlatBufferModel` base class and macros
  - `third_party/tsl_random/` — Philox random number generator and distribution utilities
- **Self-contained type definitions** in `tflite/core/c/c_api_types.h`: `TfLiteType` enum (22 tensor types), `TfLiteQuantizationParams`, and `TfLiteDimensionType` — previously provided by a `tflite_types.h` header not present in the pinned TF submodule.
- **Self-contained error_reporter and verifier** in `tflite/core/api/` with full class implementations instead of forwarding headers to the TF submodule.
- **Headers-only XNNPACK plugin target** (`xnnpack_plugin_hdrs_only`) for the Java JNI layer, which uses `dlsym` for runtime delegate loading and only needs type declarations.

### Changed

- **WORKSPACE**: Removed `python_wheel_version_suffix_repository` (non-existent in pinned XLA), CUDA/NCCL hermetic initialization blocks, and added `new_local_repository` declarations for `local_config_cuda` and `local_config_nccl` stubs.
- **Build workflow** (`build-litert-aar.yml`):
  - Uses `ci/tflite-android.Dockerfile` as build context
  - Runs TensorFlow `configure` inside Docker before `bazel build`
  - Sets `TF_NEED_CLANG=0`, `USE_LOCAL_TF=true`, `TF_LOCAL_SOURCE_PATH` to use the pinned TF submodule
  - Uses `--config=android` (not `android_arm64`) to avoid missing platform BUILD files
  - Adds `--cpu=armeabi-v7a` to satisfy Android NDK toolchain requirements
  - Disables XNNPACK (`--define=tflite_with_xnnpack=false`, `--define=tflite_kernel_use_xnnpack=false`) due to API version mismatch with pinned XNNPACK
  - Copies AAR output with `sudo` to fix Docker root-ownership permissions before artifact upload
- **`tflite/core/c/builtin_op_data.h`**: Replaced minimal stub with the complete 661-line version from `tensorflow/lite/core/c/builtin_op_data.h` containing all op parameter structs.
- **`tflite/version.h`**: Hardcoded version string `"2.18.0"` instead of depending on `@org_tensorflow//tensorflow/core/public:version`.
- **Include path updates** across ~20 source files: replaced `tensorflow/compiler/mlir/lite/...` includes with local `tflite/` or `third_party/` paths to satisfy Bazel's strict dependency checking.
- **BUILD dependency declarations**: Added `//tflite/core/api:error_reporter` and `//third_party/allocation` deps to multiple targets (`mutable_op_resolver`, `c_api_experimental`, `nnapi_delegate`, `delegates/utils`, `core/subgraph`) for transitive header inclusions.
- **`tflite/BUILD`**: Updated deps for `allocation`, `string_util`, and `version` targets to use local copies instead of `@org_tensorflow` references.
- **`tflite/core/BUILD`**: Replaced all `@org_tensorflow//tensorflow/compiler/mlir/lite/core:model_builder_base` deps with `//third_party/model_builder_base`.
- **`tflite/kernels/BUILD`**: Updated TSL random deps from `@local_xla//xla/tsl/lib/random:*` to `//third_party/tsl_random:*`.

### Removed

- Removed PyPI release workflows (not needed for Android AAR builds).
- Removed references to non-existent TF submodule targets (`tflite_types.h`, `release_version`, `tensorflow/tools/toolchains/android`).
- Disabled newer StableHLO operators (`STABLEHLO_SHIFT_LEFT`, `STABLEHLO_CASE`, `STABLEHLO_CBRT`) and blockwise quantization support not present in the pinned TF submodule's schema.
- Removed `stablehlo_case.cc` from kernel sources (uses undefined `TfLiteStablehloCaseParams`).

### Notes

- All copied source files retain their original Apache 2.0 copyright headers from The TensorFlow Authors.
- The resulting AAR includes native libraries for x86, x86_64, arm64-v8a, and armeabi-v7a architectures.
- XNNPACK delegate is disabled; NNAPI delegate remains available for hardware acceleration on Android.
- The build targets `//tflite/java:tensorflow-lite` and produces `tensorflow-lite.aar`.
