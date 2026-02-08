load("@rules_cc//cc:defs.bzl", "cc_binary", "cc_library", "cc_test")

cc_library(
    name = "github_client",
    srcs = ["github_client.cc"],
    hdrs = ["github_client.h"],
    deps = [
        "@cpr",
        "@nlohmann_json//:json",
    ],
    visibility = ["//visibility:public"],
)

cc_binary(
    name = "github_checker",
    srcs = ["main.cc"],
    data = ["//:config.yaml"],
    deps = [
        ":github_client",
        "@bazel_tools//tools/cpp/runfiles",
        "@yaml-cpp",
    ],
)

cc_test(
    name = "github_client_test",
    srcs = ["github_client_test.cc"],
    deps = [
        ":github_client",
        "@googletest//:gtest",
        "@googletest//:gtest_main",
    ],
)
