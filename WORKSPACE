"""
In this WORKSPACE:
 - load riles_python, then define the python version and pin the requirements
 - load the direct third_party dependencies
"""

workspace(name = "my_playground")

# load the direct third_party dependencies
load("//third_party:third_party.bzl", "load_third_party_libraries")
load_third_party_libraries()

# load the transitive third_party dependencies
load("//third_party:transitive_dependencies.bzl", "load_transitive_dependencies")
load_transitive_dependencies()

#-----------------------------
# set up python version and modules needed
load("@rules_python//python:repositories.bzl", "python_register_toolchains")

python_register_toolchains(
    name = "python3_9",
    python_version = "3.9",
)

load("@python3_9//:defs.bzl", "interpreter")

load("@rules_python//python:pip.bzl", "pip_parse")

pip_parse(
    name = "my_pip_install",
    requirements = "//:requirements_lock.txt", 
    python_interpreter_target = interpreter
)

# Load the starlark macro which will define your dependencies.
load("@my_pip_install//:requirements.bzl", "install_deps")
# Call it to define repos for your requirements.
install_deps()
#-----------------------------
