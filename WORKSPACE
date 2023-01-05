load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("//third_party:third_party.bzl", "load_third_party_libraries")

load_third_party_libraries()

http_archive(
    name = "rules_python",
    sha256 = "497ca47374f48c8b067d786b512ac10a276211810f4a580178ee9b9ad139323a",
    strip_prefix = "rules_python-0.16.1",
    url = "https://github.com/bazelbuild/rules_python/archive/refs/tags/0.16.1.tar.gz",
)

load("@rules_python//python:repositories.bzl", "python_register_toolchains")

python_register_toolchains(
    name = "python3_9",
    python_version = "3.9",
)

load("@python3_9//:defs.bzl", "interpreter")

load("@rules_python//python:pip.bzl", "pip_parse")

pip_parse(
    name = "my_pip_install",
    requirements = "//:requirements.txt", 
    python_interpreter_target = interpreter
)

# Load the starlark macro which will define your dependencies.
load("@my_pip_install//:requirements.bzl", "install_deps")
# Call it to define repos for your requirements.
install_deps()
