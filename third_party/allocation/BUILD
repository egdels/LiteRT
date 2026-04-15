package(default_visibility = ["//visibility:public"])

cc_library(
    name = "allocation",
    srcs = [
        "allocation.cc",
    ] + select({
        "//tflite:tflite_mmap_disabled": [
            "mmap_allocation_disabled.cc",
        ],
        "//conditions:default": [
            "mmap_allocation.cc",
        ],
    }),
    hdrs = ["allocation.h"],
    deps = [
        "//tflite/core/api:error_reporter",
    ],
)
