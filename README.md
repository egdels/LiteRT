# LiteRT (Fork)

> **⚠️ Fork Notice:** This is a fork of [google-ai-edge/LiteRT](https://github.com/google-ai-edge/LiteRT) (version 1.4.1), maintained to enable **building the LiteRT Android AAR from source**. This is required for inclusion in [F-Droid](https://f-droid.org/), which mandates that all dependencies are built from FLOSS source code.
>
> The upstream LiteRT project publishes pre-built AARs to Maven Central, but those artifacts include build-time references to proprietary Google Play libraries (`com.google.android.play:ai-delivery`), which prevents F-Droid from accepting apps that depend on them.
>
> This fork contains CI workflow and build system patches (Dockerfile, WORKSPACE, Bazel BUILD files, visibility workarounds) to produce a functionally equivalent `tensorflow-lite.aar` entirely from source. See [CHANGELOG.md](./CHANGELOG.md) for a detailed list of changes.
>
> **No application logic has been modified.** The resulting AAR is functionally identical to the upstream release, minus the XNNPACK delegate (disabled due to API version mismatch with the pinned dependency).

## Usage

The F-Droid-compatible AAR is published to Maven Central:

```kotlin
// build.gradle.kts
dependencies {
    implementation("de.schliweb:tensorflow-lite-fdroid:1.4.1-fdroid")
}
```

> **Note:** This is NOT an official Google release. It is a patched fork built entirely from source without proprietary dependencies.

---

# LiteRT Next

LiteRT Next is a new set of APIs that improves upon LiteRT, particularly in
terms of hardware acceleration and performance for on-device ML and AI
applications. The APIs are an alpha release and available in Kotlin and C++.

The LiteRT Next CompiledModel API builds on the TensorFlow Lite Interpreter
API, and simplifies the model loading and execution process for on-device
machine learning. The new APIs provide a new streamlined way to use hardware
acceleration, removing the need to deal with model FlatBuffers, I/O buffer
interoperability, and delegates. The LiteRT Next APIs are not compatible with
the LiteRT APIs.

## Key features

LiteRT Next contains the following key benefits and features:

-   **New LiteRT API:** Streamline development with automated accelerator
    selection, true async execution, and efficient I/O buffer handling.

-   **Best-in-class GPU Performance:** Use state-of-the-art GPU acceleration for
    on-device ML. The new buffer interoperability enables zero-copy and
    minimizes latency across various GPU buffer types.

-   **Superior Generative AI inference:** Enable the simplest integration with
    the best performance for GenAI models.

-   **Unified NPU Acceleration:** Offer seamless access to NPUs from major
    chipset providers with a consistent developer experience. LiteRT NPU
    acceleration is available through an
    [Early Access Program](https://forms.gle/CoH4jpLwxiEYvDvF6).

## Key improvements

LiteRT Next (CompiledModel API) contains the following key improvements on
LiteRT (TFLite Interpreter API). For a comprehensive guide to setting up your
application with LiteRT Next, see the Get Started guide.

-   **Accelerator usage:** Running models on GPU with LiteRT requires explicit
    delegate creation, function calls, and graph modifications. With LiteRT
    Next, just specify the accelerator.
-   **Native hardware buffer interoperability:** LiteRT does not provide the
    option of buffers, and forces all data through CPU memory. With LiteRT Next,
    you can pass in Android Hardware Buffers (AHWB), OpenCL buffers, OpenGL
    buffers, or other specialized buffers.

-   **Async execution:** LiteRT Next comes with a redesigned async API,
    providing a true async mechanism based on sync fences. This enables faster
    overall execution times through the use of diverse hardware – like CPUs,
    GPUs, CPUs, and NPUs – for different tasks.

-   **Model loading:** LiteRT Next does not require a separate builder step when
    loading a model.

For more details, check our
[official documentation](https://ai.google.dev/edge/litert/next/overview).

## Build From Source

1.  Start a docker daemon

2.  Run [build_with_docker.sh](./build/build_with_docker.sh) under
    [build/](./build)

3.  For more information about how to use docker interactive shell/ building
    different targets. Please refer to [build/README.md](./build/README.md)
