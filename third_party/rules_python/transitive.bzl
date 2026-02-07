"""
Transitive dependencies for rules_python

rules_python 0.24.0
"""

load("@rules_python//python:repositories.bzl", "py_repositories")

def load_rules_python_transitive_dependencies():
    """Load transitive dependencies for rules_python.
    """
    py_repositories()
