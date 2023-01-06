
load("//third_party:third_party.bzl", "load_third_party_libraries")

load_third_party_libraries()



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
