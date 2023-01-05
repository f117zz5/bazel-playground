load("@rules_python//python:defs.bzl", "py_binary")
load("@my_pip_install//:requirements.bzl", "requirement")

py_binary(
    name = "main",
    srcs = ["main.py"],
    deps = [requirement("requests")]
)