load("@rules_python//python:defs.bzl", "py_binary")
load("@rules_cc//cc:defs.bzl", "cc_binary")

genrule(
        name = "github_checker_wrapper",
        outs = ["github_checker_wrapper.sh"],
        cmd = """
cat > $@ <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# --- Bazel runfiles setup ---
if [[ -n \"$${RUNFILES_DIR:-}\" ]]; then
    RUNFILES=\"$$RUNFILES_DIR\"
else
    RUNFILES=\"$$0.runfiles\"
fi

BIN=\"$$RUNFILES/hermetic_toolchains~/src/python/github_checker\"
CFG=\"$$RUNFILES/hermetic_toolchains~/config.yaml\"

cd \"$$(dirname \"$$CFG\")\"
exec \"$$BIN\" \"$$@\"
EOF
chmod +x $@
""",
)

# Simple Python binary using the hermetic Python 3.11 interpreter.
# No pip packages needed for this hello-world.
py_binary(
    name = "hello",
    srcs = ["hello.py"],
)

# Example C++ binary — will be compiled with whichever toolchain
# the user selects via --config=gcc12 / gcc10 / clang17.
cc_binary(
    name = "hello_cc",
    srcs = ["hello.cc"],
)

sh_binary(
    name = "github_checker",
    srcs = [":github_checker_wrapper"],
    data = [
        "@hermetic_toolchains//:config.yaml",
        "@hermetic_toolchains//src/python:github_checker",
    ],
)
