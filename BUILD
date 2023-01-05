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
        requirement("exceptiongroup"),
        requirement("idna"),
        requirement("iniconfig"),
        requirement("packaging"),
        requirement("pluggy"),
        requirement("pytest"),
        requirement("requests"),
        requirement("tomli"),
        requirement("urllib3"),
        ],
)