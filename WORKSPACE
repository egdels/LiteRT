# buildifier: disable=load-on-top

workspace(name = "litert")

# buildifier: disable=load-on-top

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "rules_shell",
    sha256 = "bc61ef94facc78e20a645726f64756e5e285a045037c7a61f65af2941f4c25e1",
    strip_prefix = "rules_shell-0.4.1",
    url = "https://github.com/bazelbuild/rules_shell/releases/download/v0.4.1/rules_shell-v0.4.1.tar.gz",
)

load("@rules_shell//shell:repositories.bzl", "rules_shell_dependencies", "rules_shell_toolchains")

rules_shell_dependencies()

rules_shell_toolchains()

# Java rules
http_archive(
    name = "rules_java",
    sha256 = "c73336802d0b4882e40770666ad055212df4ea62cfa6edf9cb0f9d29828a0934",
    url = "https://github.com/bazelbuild/rules_java/releases/download/5.3.5/rules_java-5.3.5.tar.gz",
)

# Load the custom repository rule to select either a local TensorFlow source or a remote http_archive.
load("//litert:tensorflow_source_rules.bzl", "tensorflow_source_repo")

tensorflow_source_repo(
    name = "org_tensorflow",
    # Remote fallback intentionally removed for F-Droid builds.
    # Always use USE_LOCAL_TF=true with TF_LOCAL_SOURCE_PATH.
    sha256 = "",
    strip_prefix = "",
    urls = [],
)

# Initialize the TensorFlow repository and all dependencies.
#
# The cascade of load() statements and tf_workspace?() calls works around the
# restriction that load() statements need to be at the top of .bzl files.
# E.g. we can not retrieve a new repository with http_archive and then load()
# a macro from that repository in the same file.
load("@org_tensorflow//tensorflow:workspace3.bzl", "tf_workspace3")

tf_workspace3()

# Initialize hermetic Python
load("@local_xla//third_party/py:python_init_rules.bzl", "python_init_rules")

python_init_rules()

load("@local_xla//third_party/py:python_init_repositories.bzl", "python_init_repositories")

python_init_repositories(
    default_python_version = "system",
    local_wheel_dist_folder = "dist",
    local_wheel_inclusion_list = [
        "tensorflow*",
        "tf_nightly*",
    ],
    local_wheel_workspaces = ["@org_tensorflow//:WORKSPACE"],
    requirements = {
        "3.9": "@org_tensorflow//:requirements_lock_3_9.txt",
        "3.10": "@org_tensorflow//:requirements_lock_3_10.txt",
        "3.11": "@org_tensorflow//:requirements_lock_3_11.txt",
        "3.12": "@org_tensorflow//:requirements_lock_3_12.txt",
    },
)

load("@local_xla//third_party/py:python_init_toolchains.bzl", "python_init_toolchains")

python_init_toolchains()

load("@local_xla//third_party/py:python_init_pip.bzl", "python_init_pip")

python_init_pip()

load("@pypi//:requirements.bzl", "install_deps")

install_deps()
# End hermetic Python initialization

load("@org_tensorflow//tensorflow:workspace2.bzl", "tf_workspace2")

tf_workspace2()

load("@org_tensorflow//tensorflow:workspace1.bzl", "tf_workspace1")

tf_workspace1()

load("@org_tensorflow//tensorflow:workspace0.bzl", "tf_workspace0")

tf_workspace0()

# Stub CUDA/NCCL repositories for non-CUDA builds (e.g. Android).
new_local_repository(
    name = "local_config_cuda",
    build_file_content = "# empty",
    path = "third_party/cuda_stub",
)

new_local_repository(
    name = "local_config_nccl",
    build_file_content = "# empty",
    path = "third_party/cuda_stub",
)

# ---------------------------------------------------------------------------
# REMOVED for F-Droid: the following are NOT needed by //tflite/java:tensorflow-lite
# and are disabled to reduce the external dependency surface.
# ---------------------------------------------------------------------------

# tqdm — only used by litert/ targets, not tflite/
# load("//third_party/tqdm:workspace.bzl", tqdm = "repo")
# tqdm()

# litert_maven — only used by litert/kotlin/, not tflite/
# Also requires maven_install.json which does not exist.
# load("@rules_jvm_external//:defs.bzl", "maven_install")
# maven_install(
#     name = "litert_maven",
#     artifacts = [...],
#     maven_install_json = "//:maven_install.json",
#     repositories = [...],
# )

# Kotlin rules — only used by litert/kotlin/, not tflite/
# http_archive(
#     name = "rules_kotlin",
#     sha256 = "e1448a56b2462407b2688dea86df5c375b36a0991bd478c2ddd94c97168125e2",
#     url = "https://github.com/bazelbuild/rules_kotlin/releases/download/v2.1.3/rules_kotlin-v2.1.3.tar.gz",
# )
# load("@rules_kotlin//kotlin:repositories.bzl", "kotlin_repositories")
# kotlin_repositories()
# load("@rules_kotlin//kotlin:core.bzl", "kt_register_toolchains")
# kt_register_toolchains()

# stblib — only used by litert/ targets, not tflite/
# load("//third_party/stblib:workspace.bzl", stblib = "repo")
# stblib()

# VENDOR SDKS ######################################################################################
# NOTE: Vendor SDK loads (Qualcomm QAIRT, MediaTek NeuroPilot, Google Tensor,
# LiteRT GPU) are disabled for F-Droid builds. They download proprietary
# binaries without SHA256 verification and are not needed for the base
# tensorflow-lite.aar build.
#
# To re-enable for development with vendor delegates, uncomment below:
#
# load("//third_party/qairt:workspace.bzl", "qairt")
# qairt()
#
# load("//third_party/neuro_pilot:workspace.bzl", "neuro_pilot")
# neuro_pilot()
#
# load("//third_party/google_tensor:workspace.bzl", "google_tensor")
# google_tensor()
#
# load("//third_party/litert_gpu:workspace.bzl", "litert_gpu")
# litert_gpu()
