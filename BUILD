load("@rules_python//python:defs.bzl", "py_binary")
load("@my_pip_install//:requirements.bzl", "requirement")

py_binary(
    name = "main",
    srcs = ["main.py"],
    deps = [
        requirement("attrs"),
        #requirement("pytest"),
        requirement("certifi"),
        requirement("charset-normalizer"),
        requirement("idna"),
        requirement("iniconfig"),
        requirement("packaging"),
        requirement("pluggy"),
        requirement("py"),
        requirement("pytest"),
        requirement("requests"),
        requirement("tomli"),
        requirement("urllib3"),
        ],
)