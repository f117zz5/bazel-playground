"""
Public API for the hermetic_toolchains module.

This file provides constants and documentation for consumers
that depend on hermetic_toolchains via Bzlmod.

Consumer workspaces use these toolchains via --extra_toolchains in .bazelrc.
"""

# ---------------------------------------------------------------------------
# Toolchain labels
#
# Consumers select a toolchain in their .bazelrc like:
#
#   build:gcc12 --extra_toolchains=@hermetic_toolchains//toolchain:gcc_toolchain
#
# These constants are provided for programmatic use in Starlark macros.
# ---------------------------------------------------------------------------

GCC12_TOOLCHAIN = "@hermetic_toolchains//toolchain:gcc_toolchain"
GCC10_TOOLCHAIN = "@hermetic_toolchains//toolchain:gcc10_toolchain"

# Clang 17 is NOT registered by this module (toolchains_llvm restricts its
# extension to the root module only).  When a consumer sets up Clang in
# their own MODULE.bazel, the toolchain label is:
CLANG17_TOOLCHAIN = "@llvm_toolchain//:cc-toolchain-x86_64-linux"

# ---------------------------------------------------------------------------
# Toolchain metadata — for introspection / build dashboards
# ---------------------------------------------------------------------------

TOOLCHAIN_INFO = {
    "gcc12": {
        "label": GCC12_TOOLCHAIN,
        "compiler": "gcc",
        "version": "12.3.0",
        "glibc": "2.39",
        "source": "Bootlin stable-2024.02-1",
        "hermetic": "fully",
    },
    "gcc10": {
        "label": GCC10_TOOLCHAIN,
        "compiler": "gcc",
        "version": "10.3.0",
        "glibc": "2.34",
        "source": "Bootlin stable-2021.11-5",
        "hermetic": "fully",
    },
    "clang17": {
        "label": CLANG17_TOOLCHAIN,
        "compiler": "clang",
        "version": "17.0.6",
        "glibc": "2.34 (sysroot)",
        "stdlib": "builtin-libc++ (static)",
        "hermetic": "sandbox-hermetic",
    },
    "python": {
        "version": "3.11",
        "source": "Bundled with GCC 12 Bootlin toolchain (3.11.8)",
        "hermetic": "fully",
        "note": "Interpreter only — consumers manage their own pip packages",
    },
}
