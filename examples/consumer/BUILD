load("@rules_python//python:defs.bzl", "py_binary")
load("@rules_cc//cc:defs.bzl", "cc_binary")

# Simple Python binary using the hermetic Python 3.11 interpreter.
# No pip packages needed for this hello-world.
py_binary(
    name = "hello",
    srcs = ["hello.py"],
)

# Example C++ binary — will be compiled with whichever toolchain
# the user selects via --config=gcc12 / gcc10 / clang17.
cc_binary(
    name = "hello_cc",
    srcs = ["hello.cc"],
)
