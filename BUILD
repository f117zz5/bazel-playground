load("@rules_python//python:defs.bzl", "py_binary")
load("@my_pip_install//:requirements.bzl", "requirement")
load("@rules_python//python:pip.bzl", "compile_pip_requirements")


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

exports_files([
    "requirements.in",
    "requirements_lock.txt",
])

compile_pip_requirements(
    name = "requirements",
    extra_args = ["--allow-unsafe"],
    requirements_in = "requirements.in",
    requirements_txt = "requirements_lock.txt",
)