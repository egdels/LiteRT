package(
    default_visibility = ["//visibility:public"],
    licenses = ["notice"],
)

cc_library(
    name = "model_builder_base",
    srcs = ["model_builder_base.cc"],
    hdrs = ["model_builder_base.h"],
    deps = [
        ":macros",
        "//third_party/allocation",
        "//tflite/core/api:error_reporter",
        "//tflite/core/api:verifier",
        "//tflite/schema:schema_fbs",
        "@com_google_absl//absl/strings",
        "@flatbuffers",
    ],
    alwayslink = 1,
)

cc_library(
    name = "macros",
    hdrs = ["macros.h"],
)
