# Vendored Source Files

This document tracks all source files copied from the TensorFlow/LiteRT upstream
into `third_party/` or `tflite/` to work around Bazel visibility restrictions
between `//tflite/` and `@org_tensorflow//` packages.

All files retain their original Apache 2.0 copyright headers.

**Upstream base:** TensorFlow v2.18.0 (pinned in `third_party/tensorflow/`)

## Vendored Directories

| Local path | Upstream origin | Description |
|---|---|---|
| `third_party/allocation/` | `tensorflow/lite/allocation.{h,cc}`, `tensorflow/lite/mmap_allocation.{h,cc}`, etc. | `Allocation`, `MMAPAllocation`, `FileCopyAllocation`, `MemoryAllocation` classes |
| `third_party/string_utils/` | `tensorflow/lite/string_util.{h,cc}`, `tensorflow/lite/simple_dynamic_buffer.{h,cc}` | `SimpleDynamicBuffer`, `StringRef`, string tensor utilities |
| `third_party/metadata_util/` | `tensorflow/compiler/mlir/lite/utils/control_flow_graph_utils.{h,cc}` | Model control dependency serialization/deserialization |
| `third_party/model_builder_base/` | `tensorflow/compiler/mlir/lite/core/model_builder_base.{h,cc}` | `FlatBufferModel` base class and macros |
| `third_party/tsl_random/` | `xla/tsl/lib/random/philox_random.h`, `xla/tsl/lib/random/distribution_sampler.{h,cc}` | Philox RNG and distribution utilities |
| `third_party/cuda_stub/` | N/A (new) | No-op stubs for `cuda_library`, `if_cuda`, etc. — required by TF's `tensorflow.bzl` but unused for Android |

## Vendored Files in tflite/

| Local path | Upstream origin | Description |
|---|---|---|
| `tflite/core/c/c_api_types.h` | `tensorflow/lite/core/c/c_api_types.h` | `TfLiteType` enum, `TfLiteQuantizationParams`, `TfLiteDimensionType` |
| `tflite/core/c/builtin_op_data.h` | `tensorflow/lite/core/c/builtin_op_data.h` | Complete op parameter structs (661 lines) |
| `tflite/core/api/error_reporter.{h,cc}` | `tensorflow/lite/core/api/error_reporter.{h,cc}` | Full class implementation (not forwarding header) |
| `tflite/core/api/verifier.h` | `tensorflow/lite/core/api/verifier.h` | Self-contained verifier interface |
| `tflite/version.h` | `tensorflow/lite/version.h` | Hardcoded `"2.18.0"` instead of depending on `@org_tensorflow//tensorflow/core/public:version` |

## Upgrade Procedure

When upgrading the TensorFlow submodule:

1. Update `third_party/tensorflow/` to the new commit/tag
2. For each entry above, diff the local copy against the new upstream:
   ```bash
   diff third_party/allocation/allocation.h \
        third_party/tensorflow/tensorflow/lite/allocation.h
   ```
3. Apply upstream changes to the local copies
4. Update the version string in `tflite/version.h`
5. Run a full build to verify: `./ci/build-fdroid.sh`
6. Update this file with the new upstream base version
