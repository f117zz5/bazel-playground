"""
File to load the transitive dependencies of direct dependencies

This is separated from direct.bzl to avoid circular loading issues.
If a third party library depends on a package we also depend on, we load the 
package with our preferred version first.
"""

load("//third_party/bazel_skylib:transitive.bzl", "load_bazel_skylib_transitive_dependencies")
load("//third_party/rules_python:transitive.bzl", "load_rules_python_transitive_dependencies")


def load_transitive_dependencies():
    """Load the transitive dependencies of only our direct dependencies"""
    load_bazel_skylib_transitive_dependencies()
    load_rules_python_transitive_dependencies()
