"""
Transitive dependencies to bazel_gazelle

Instructions in 
https://github.com/bazelbuild/bazel-gazelle#running-gazelle-with-bazel
"""

load("@bazel_gazelle//:deps.bzl", "gazelle_dependencies", "go_repository")

def load_bazel_gazelle_transitive_dependencies():
    gazelle_dependencies()
    go_repository()
