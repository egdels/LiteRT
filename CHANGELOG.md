# Changelog

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
