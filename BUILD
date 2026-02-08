load("@rules_python//python:pip.bzl", "compile_pip_requirements")

exports_files(
    ["config.yaml"],
    visibility = ["//visibility:public"],
)

compile_pip_requirements(
    name = "requirements",
    # extra_args passes pip-compie options, use "-U" ti update for example
    extra_args = ["--allow-unsafe", "-U"],
    requirements_in = "requirements.in",
    requirements_txt = "requirements_lock.txt",
)