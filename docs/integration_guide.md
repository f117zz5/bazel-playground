# Integrating hermetic_toolchains into your Bazel project

## Overview

The `hermetic_toolchains` Bzlmod module provides four hermetic toolchains
that any Bazel workspace can depend on:

| Toolchain | Compiler | glibc | Hermetic | Registration |
|-----------|----------|-------|----------|--------------|
| **GCC 12.3** | gcc 12.3.0 | 2.39 | ✅ Fully | Automatic |
| **GCC 10.3** | gcc 10.3.0 | 2.34 | ✅ Fully | Automatic |
| **Clang 17** | clang 17.0.6 | 2.34 (sysroot) | ⚠️ Sandbox | Manual (see below) |
| **Python 3.11** | cpython 3.11.8 | — | ✅ Fully | Automatic |

> **⚠️ Clang 17 note:** Due to a `toolchains_llvm` limitation, the LLVM
> extension can only be configured by the **root module**.  This means
> consumers must set up Clang 17 themselves in their `MODULE.bazel`.
> GCC and Python work transitively with no extra setup.

## Quick Start

### 1. Add the dependency

In your project's `MODULE.bazel`:

```python
bazel_dep(name = "hermetic_toolchains", version = "1.0.0")
```

For local development (pointing to a local checkout):

```python
local_path_override(
    module_name = "hermetic_toolchains",
    path = "/path/to/hermetic_toolchains",
)
```

For a git-based dependency:

```python
git_override(
    module_name = "hermetic_toolchains",
    remote = "https://github.com/your-org/hermetic_toolchains.git",
    commit = "<commit-sha>",
)
```

### 2. Set up Clang 17 (required if you want Clang)

Because `toolchains_llvm` v1.2.0 restricts its `llvm` extension to
the root module only, you must add the following to **your** `MODULE.bazel`:

```python
# --- Clang 17 setup (must be in the root module) ---
bazel_dep(name = "toolchains_llvm", version = "1.2.0")

# Sysroot archive — same Bootlin GCC 10.3 used by hermetic_toolchains
http_archive = use_repo_rule("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
http_archive(
    name = "clang_sysroot",
    build_file_content = """
package(default_visibility = ["//visibility:public"])
filegroup(
    name = "sysroot_files",
    srcs = glob(["**/*"]),
)
""",
    sha256 = "6fe812add925493ea0841365f1fb7ca17fd9224bab61a731063f7f12f3a621b0",
    strip_prefix = "x86-64--glibc--stable-2021.11-5/x86_64-buildroot-linux-gnu/sysroot",
    url = "https://toolchains.bootlin.com/downloads/releases/toolchains/x86-64/tarballs/x86-64--glibc--stable-2021.11-5.tar.bz2",
)

llvm = use_extension("@toolchains_llvm//toolchain/extensions:llvm.bzl", "llvm")
llvm.toolchain(
    name = "llvm_toolchain",
    llvm_version = "17.0.6",
    stdlib = {"linux-x86_64": "builtin-libc++"},
    link_flags = {
        "linux-x86_64": [
            "--target=x86_64-unknown-linux-gnu",
            "-lm", "-no-canonical-prefixes", "-fuse-ld=lld",
            "-Wl,--build-id=md5", "-Wl,--hash-style=gnu",
            "-Wl,-z,relro,-z,now",
            "-l:libc++.a", "-l:libc++abi.a",
            "-Wl,--dynamic-linker=external/_main~_repo_rules~clang_sysroot/lib/ld-linux-x86-64.so.2",
            "-Wl,-rpath,external/_main~_repo_rules~clang_sysroot/lib",
            "-Wl,-rpath,external/_main~_repo_rules~clang_sysroot/usr/lib",
            "-Wl,-rpath,external/_main~_repo_rules~clang_sysroot/lib64",
        ],
    },
)
llvm.sysroot(
    name = "llvm_toolchain",
    targets = ["linux-x86_64"],
    label = "@clang_sysroot//:sysroot_files",
)
use_repo(llvm, "llvm_toolchain")
register_toolchains("@llvm_toolchain//:all")
```

> **Why can't this be automatic?**  The `toolchains_llvm` extension
> iterates over all modules that use it and calls
> `fail("Only the root module can use the 'llvm' extension")` for any
> non-root module.  This is a design choice by `toolchains_llvm` to
> prevent conflicting LLVM configurations from transitive dependencies.

### 3. Configure your `.bazelrc`

```bash
# Enable Bzlmod
common --enable_bzlmod

# Force C++17 (if using cpr or modern C++ libraries)
build --cxxopt=-std=c++17

# --- Select a C/C++ toolchain ---
# GCC 12.3 (fully hermetic, glibc 2.39)
build:gcc12 --extra_toolchains=@hermetic_toolchains//toolchain:gcc_toolchain

# GCC 10.3 (fully hermetic, glibc 2.34)
build:gcc10 --extra_toolchains=@hermetic_toolchains//toolchain:gcc10_toolchain

# Clang 17 (sandbox-hermetic, static libc++)
build:clang17 --extra_toolchains=@llvm_toolchain//:cc-toolchain-x86_64-linux
```

### 4. Set up Python (your own pip packages)

The Python 3.11 interpreter is provided automatically by `hermetic_toolchains`.
You only need to configure your own pip packages:

```python
# In your MODULE.bazel
bazel_dep(name = "rules_python", version = "0.24.0")

pip = use_extension("@rules_python//python/extensions:pip.bzl", "pip")
pip.parse(
    hub_name = "my_pip_deps",
    python_version = "3.11",
    requirements_lock = "//:requirements_lock.txt",
)
use_repo(pip, "my_pip_deps")
```

Then in your BUILD files:

```python
load("@rules_python//python:defs.bzl", "py_binary")
load("@my_pip_deps//:requirements.bzl", "requirement")

py_binary(
    name = "my_app",
    srcs = ["main.py"],
    deps = [
        requirement("requests"),
    ],
)
```

### 5. Build with a specific toolchain

```bash
# Build C++ with GCC 12 (hermetic)
bazel build --config=gcc12 //...

# Build C++ with GCC 10 (hermetic)
bazel build --config=gcc10 //...

# Build C++ with Clang 17 (hermetic)
bazel build --config=clang17 //...

# Build/run Python (automatically uses hermetic Python 3.11)
bazel run //:my_python_app
```

## What You Get

### C/C++ Toolchains

The two GCC toolchains are **automatically registered** when you
depend on `hermetic_toolchains`.  The toolchains are ordered by registration
priority (GCC 12 → GCC 10), but you can override the selection
with `--extra_toolchains` in `.bazelrc`.

Clang 17 requires **manual setup** in the consumer's `MODULE.bazel`
(see Quick Start step 2 above) due to the `toolchains_llvm` root-only
restriction.

**Key properties:**
- GCC toolchains bundle their own glibc, dynamic linker, and libstdc++
- Clang bundles static libc++ and uses a Bootlin sysroot during builds
- All toolchains target `x86_64` Linux
- No system compiler or headers are used

### Python Toolchain

The Python 3.11.8 interpreter is bundled inside the GCC 12 Bootlin
distribution.  `hermetic_toolchains` registers it as the Python toolchain
so your `py_binary` and `py_test` targets use it automatically.

**What is NOT provided:**
- pip packages — you must define your own `requirements.in` /
  `requirements_lock.txt` and call `pip.parse()` in your `MODULE.bazel`

This design lets each consumer workspace pin its own package versions
without conflicts.

## Architecture

```
hermetic_toolchains/
├── MODULE.bazel              ← Module definition + toolchain setup
├── toolchain/
│   ├── BUILD                 ← toolchain() registrations (GCC 12, GCC 10)
│   ├── BUILD.gcc             ← cc_toolchain for GCC 12 http_archive
│   ├── BUILD.gcc10           ← cc_toolchain for GCC 10 http_archive
│   ├── BUILD.clang_sysroot   ← filegroup for Clang sysroot
│   ├── cc_toolchain_config.bzl  ← GCC cc_toolchain_config rule
│   ├── gcc_toolchain_config.bzl ← Repository rule for absolute paths
│   ├── inject_config.patch   ← Patch injecting .bzl into GCC tarballs
│   └── defs.bzl              ← Public API (toolchain labels, metadata)
└── examples/
    └── consumer/             ← Example consumer workspace
        ├── MODULE.bazel
        ├── .bazelrc
        ├── BUILD
        ├── hello.py
        └── hello.cc
```

### How Transitive Dependencies Work

When a consumer adds `bazel_dep(name = "hermetic_toolchains", ...)`,
Bzlmod automatically pulls in the transitive dependencies:

- `bazel_skylib` 1.6.1
- `rules_python` 0.24.0
- `toolchains_llvm` 1.2.0
- `platforms` 0.0.10

The GCC archives and Clang sysroot are fetched on demand when a build
actually needs them (lazy fetching).

### How Toolchain Registration Works

`hermetic_toolchains` calls `register_toolchains()` in its `MODULE.bazel`.
In Bzlmod, toolchains registered by dependencies have **lower priority**
than those registered by the root module.  This means:

1. If the consumer does NOT register any C++ toolchains, Bazel picks
   from the hermetic ones (GCC 12 first, by registration order).
2. If the consumer uses `--extra_toolchains=...`, that toolchain gets
   **highest priority** and is selected.
3. The consumer can override with its own toolchains if needed.

## Example Consumer

See [examples/consumer/](../examples/consumer/) for a complete working
example.  To try it:

```bash
cd examples/consumer

# Build with GCC 12
bazel build --config=gcc12 //:hello_cc

# Build with Clang 17
bazel build --config=clang17 //:hello_cc

# Run Python
bazel run //:hello
```

## Publishing to a Registry

To make `hermetic_toolchains` available without `local_path_override`,
you can:

### Option A: Bazel Central Registry (BCR)

Submit a PR to https://github.com/bazelbuild/bazel-central-registry
following their contribution guidelines.

### Option B: Private Registry

Host your own [Bazel registry](https://bazel.build/external/registry)
and add it to consumer `.bazelrc`:

```bash
common --registry=https://your-registry.example.com
common --registry=https://bcr.bazel.build
```

### Option C: git_override / archive_override

Use directly without a registry:

```python
# In consumer MODULE.bazel
bazel_dep(name = "hermetic_toolchains", version = "1.0.0")

git_override(
    module_name = "hermetic_toolchains",
    remote = "https://github.com/your-org/hermetic_toolchains.git",
    commit = "abc123...",
)
```

## Troubleshooting

### "No matching toolchains found"

Make sure you're targeting `x86_64` Linux.  These toolchains only
support `@platforms//cpu:x86_64` + `@platforms//os:linux`.

### Clang sysroot paths in binary

Clang uses relative sysroot paths that work in Bazel's sandbox but
not for standalone execution.  Use `bazel run` instead of running
the binary directly.  See the hermetic verification docs for details.

### Python version mismatch

Ensure your `pip.parse()` uses `python_version = "3.11"` to match
the interpreter provided by `hermetic_toolchains`.
