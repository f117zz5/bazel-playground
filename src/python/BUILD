load("@rules_python//python:defs.bzl", "py_binary", "py_library", "py_test")
load("@my_pip_install//:requirements.bzl", "requirement")

# Shared logic
py_library(
    name = "main_lib",
    srcs = ["main.py"],
    data = ["//:config.yaml"],
    deps = [
        requirement("requests"),
        requirement("pyyaml"),
    ],
    visibility = ["//visibility:public"],
)

# The executable
py_binary(
    name = "github_checker",
    srcs = ["main.py"],
    main = "main.py",
    deps = [":main_lib"],
)

# The test
py_test(
    name = "github_checker_test",
    srcs = ["test_main.py"],
    main = "test_main.py",
    deps = [
        ":main_lib",
        requirement("pytest"),
    ],
)