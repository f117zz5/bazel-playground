"""
Transitive dependencies for buildtools
"""

load("//third_party/bazel_skylib:transitive.bzl", "load_bazel_skylib_transitive_dependencies")
load("//third_party/rules_go:transitive.bzl", "load_rules_go_transitive_dependencies")
load("@build_bazel_rules_nodejs//:index.bzl", "node_repositories", "npm_install")

def load_buildtools_transitive_dependencies():
    # buildtools depends on rules_go and skylib, we need to load its transitive dependencies
    # before loading the transitive dependencies of buildtools
    load_bazel_skylib_transitive_dependencies()
    load_rules_go_transitive_dependencies()
