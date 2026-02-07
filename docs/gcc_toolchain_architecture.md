# GCC Toolchain Integration Architecture

## Table of Contents

- [Overview](#overview)
- [Architecture Layers](#architecture-layers)
  - [Layer 1 — Integration (MODULE.bazel)](#layer-1--integration-modulebazel)
  - [Layer 2 — Configuration (Starlark rules)](#layer-2--configuration-starlark-rules)
  - [Layer 3 — Patching (inject\_config.patch)](#layer-3--patching-inject_configpatch)
- [Data Flow Diagram](#data-flow-diagram)
- [File-by-File Reference](#file-by-file-reference)
- [Bugs, Root Causes, and Best Practices](#bugs-root-causes-and-best-practices)
- [Future: Separating the Toolchain into a Common Repository](#future-separating-the-toolchain-into-a-common-repository)

---

## Overview

This project integrates a **hermetic GCC 12.3 cross-toolchain** (Bootlin x86_64-glibc) into
Bazel via Bzlmod. "Hermetic" means the toolchain is downloaded as a tarball and used
in isolation — no system compiler is involved.

The integration is split into **three architectural layers**:

| Layer | Responsibility | Files |
|---|---|---|
| **Integration** | Downloads the tarball, wires repositories, registers the toolchain | `MODULE.bazel`, `toolchain/BUILD` |
| **Configuration** | Defines how Bazel invokes GCC: tool paths, sysroot, include dirs, flags | `toolchain/cc_toolchain_config.bzl`, `toolchain/gcc_toolchain_config.bzl`, `toolchain/BUILD.gcc` |
| **Patching** | Injects `cc_toolchain_config.bzl` into the downloaded archive (which ships no Bazel support) | `toolchain/inject_config.patch` |

---

## Architecture Layers

### Layer 1 — Integration (`MODULE.bazel` + `toolchain/BUILD`)

**Purpose:** Download the GCC tarball, create Bazel repositories, and register the toolchain
so Bazel's toolchain resolution can select it for C/C++ actions.

#### What happens step-by-step

1. **`http_archive`** downloads the Bootlin tarball, strips the top-level directory, applies the
   patch, and overlays `toolchain/BUILD.gcc` as the `BUILD` file:

   ```starlark
   # MODULE.bazel
   http_archive(
       name = "gcc_toolchain",
       build_file = "//toolchain:BUILD.gcc",
       patches = ["//toolchain:inject_config.patch"],
       patch_args = ["-p1"],
       url = "https://toolchains.bootlin.com/.../x86-64--glibc--stable-2024.02-1.tar.bz2",
       sha256 = "19c8e5bc1395636aef1ce82b1fa7a520f12c8b4ea1b66ac2c80ec30dcf32925e",
       strip_prefix = "x86-64--glibc--stable-2024.02-1",
   )
   ```

2. **`gcc_toolchain_config` repository rule** resolves the *absolute filesystem path* of the
   `@gcc_toolchain` repository at fetch time and writes it to a generated `defs.bzl`:

   ```starlark
   # MODULE.bazel
   gcc_toolchain_config = use_repo_rule("//toolchain:gcc_toolchain_config.bzl", "gcc_toolchain_config")
   gcc_toolchain_config(name = "gcc_toolchain_config")
   ```

3. **`register_toolchains`** tells Bazel about the toolchain so toolchain resolution can
   pick it for `@bazel_tools//tools/cpp:toolchain_type`:

   ```starlark
   register_toolchains("//toolchain:gcc_toolchain")
   ```

4. **`toolchain/BUILD`** is the *bridge* target — it declares a `toolchain()` rule that maps
   platform constraints (`x86_64` + `linux`) to the actual `cc_toolchain` target defined
   inside the downloaded archive (`@gcc_toolchain//:k8_toolchain`):

   ```starlark
   toolchain(
       name = "gcc_toolchain",
       exec_compatible_with  = ["@platforms//cpu:x86_64", "@platforms//os:linux"],
       target_compatible_with = ["@platforms//cpu:x86_64", "@platforms//os:linux"],
       toolchain      = "@gcc_toolchain//:k8_toolchain",
       toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
   )
   ```

---

### Layer 2 — Configuration (Starlark Rules)

**Purpose:** Tell Bazel *exactly* how to invoke GCC — where the binaries are, where headers
live, what flags to pass for compiling and linking.

This layer spans three files that work together:

#### 2a. `toolchain/gcc_toolchain_config.bzl` — Absolute Path Resolver

A **`repository_rule`** that runs at fetch time (before any build). It:

1. Resolves the real filesystem path of `@gcc_toolchain` via `rctx.path(Label(...)).dirname`.
2. Writes `GCC_TOOLCHAIN_ABSOLUTE_PATH` into a generated `defs.bzl`.

**Why this exists:** GCC internally resolves its built-in include directories to absolute
paths (e.g., `/home/user/.cache/bazel/.../external/.../lib/gcc/.../include`). Bazel's
`cxx_builtin_include_directories` must list the *same* absolute paths, otherwise you get
`undeclared inclusion` errors. Normal Starlark rules only see execution-root-relative paths.
This repository rule bridges that gap.

#### 2b. `toolchain/BUILD.gcc` — `cc_toolchain` + File Groups

This file is overlaid as the `BUILD` file inside the downloaded `@gcc_toolchain` repository.
It defines:

| Target | Purpose |
|---|---|
| `filegroup` targets | Declare which files from the tarball Bazel needs for compiling, linking, archiving, etc. |
| `cc_toolchain_config` | Instantiates the config rule with the resolved absolute path |
| `cc_toolchain` | The actual toolchain target that Bazel's toolchain resolution references |

Key line — loading the resolved absolute path:

```starlark
load("@gcc_toolchain_config//:defs.bzl", "GCC_TOOLCHAIN_ABSOLUTE_PATH")

cc_toolchain_config(
    name = "k8_toolchain_config",
    toolchain_path_prefix = GCC_TOOLCHAIN_ABSOLUTE_PATH,
)
```

#### 2c. `toolchain/cc_toolchain_config.bzl` — Compiler Configuration Rule

The core configuration. It defines a custom Starlark rule that returns
`CcToolchainConfigInfo` with:

| Configuration | Details |
|---|---|
| **Tool paths** | Maps logical tool names (`gcc`, `ld`, `ar`, …) to actual paths inside the tarball (`bin/x86_64-buildroot-linux-gnu-gcc`, etc.) |
| **Sysroot** | `<absolute_path>/x86_64-buildroot-linux-gnu/sysroot` — tells GCC where libc headers and libraries live |
| **`-B` flags** | Points GCC to `bin/` and `x86_64-buildroot-linux-gnu/bin/` so `collect2` can find the linker |
| **`-no-canonical-prefixes`** | Prevents GCC from resolving symlinks in paths, keeping paths predictable for Bazel's sandbox |
| **`cxx_builtin_include_directories`** | 7 absolute paths matching exactly what `gcc -v` reports — required for Bazel's strict header inclusion checking |
| **Compile features** | `--sysroot`, `-B`, `-no-canonical-prefixes` applied to all compile actions |
| **Link features** | Same flags plus `-lstdc++` and `-lm` for C++ standard library |

---

### Layer 3 — Patching (`inject_config.patch`)

**Purpose:** The Bootlin tarball is a plain GCC distribution — it ships no Bazel files.
The patch **injects** `cc_toolchain_config.bzl` directly into the tarball's root so that
`BUILD.gcc` can `load(":cc_toolchain_config.bzl", ...)`.

The patch uses `diff -Naur` format to create a brand new file (`/dev/null` → `cc_toolchain_config.bzl`).

**Why a patch and not just `build_file`?**

- `build_file` (or `build_file_content`) only replaces the `BUILD` file.
- The config rule is a `.bzl` file that needs to live *inside* the repository so it can be
  loaded by the `BUILD` file. Bazel's `http_archive` has no `extra_files` attribute.
- The only mechanism to add arbitrary files into an `http_archive` is `patches`.

---

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           MODULE.bazel                                  │
│                                                                         │
│  ┌──────────────┐    ┌──────────────────────┐    ┌───────────────────┐  │
│  │ http_archive │    │ gcc_toolchain_config  │    │register_toolchains│  │
│  │ (fetch GCC)  │    │ (repository_rule)     │    │                   │  │
│  └──────┬───────┘    └──────────┬───────────┘    └────────┬──────────┘  │
└─────────┼───────────────────────┼─────────────────────────┼─────────────┘
          │                       │                         │
          ▼                       ▼                         ▼
┌──────────────────┐  ┌────────────────────┐   ┌───────────────────────┐
│ @gcc_toolchain   │  │@gcc_toolchain_config│   │  //toolchain:BUILD   │
│ (external repo)  │  │ (external repo)     │   │  toolchain() rule    │
│                  │  │                     │   │  ┌─────────────────┐ │
│ ┌──────────────┐ │  │ defs.bzl:           │   │  │ gcc_toolchain   │ │
│ │ BUILD.gcc    │◄├──┤ GCC_TOOLCHAIN_      │   │  │ exec: x86_64   │ │
│ │              │ │  │ ABSOLUTE_PATH       │   │  │ target: x86_64 │ │
│ │ loads        │ │  │ = "/home/.../.cache │   │  │ ──────────►    │ │
│ │ ┌──────────┐ │ │  │   /bazel/.../       │   │  │ @gcc_toolchain │ │
│ │ │config.bzl│ │ │  │   gcc_toolchain"    │   │  │ //:k8_toolchain│ │
│ │ │(patched) │ │ │  │                     │   │  └─────────────────┘ │
│ │ └──────────┘ │ │  └─────────────────────┘   └───────────────────────┘
│ │              │ │
│ │ cc_toolchain │ │          ┌──────────────────────────┐
│ │ k8_toolchain │ │◄─────── │ inject_config.patch       │
│ │              │ │          │ adds cc_toolchain_config  │
│ │ filegroups   │ │          │ .bzl into the tarball     │
│ └──────────────┘ │          └──────────────────────────┘
│                  │
│ bin/x86_64-...-gcc│
│ lib/gcc/...       │
│ sysroot/...       │
└──────────────────┘
```

---

## File-by-File Reference

| File | Layer | Role |
|---|---|---|
| `MODULE.bazel` | Integration | Declares `http_archive`, `gcc_toolchain_config` repo rule, and `register_toolchains` |
| `toolchain/BUILD` | Integration | Declares the `toolchain()` bridge rule with platform constraints |
| `toolchain/gcc_toolchain_config.bzl` | Configuration | Repository rule that resolves absolute path at fetch time |
| `toolchain/BUILD.gcc` | Configuration | Overlaid BUILD for `@gcc_toolchain`: filegroups + `cc_toolchain` + `cc_toolchain_config` instantiation |
| `toolchain/cc_toolchain_config.bzl` | Configuration + Patching | The actual compiler config (tool paths, sysroot, flags, include dirs). Injected via patch. |
| `toolchain/inject_config.patch` | Patching | Patch that creates `cc_toolchain_config.bzl` inside the downloaded tarball |

---

## Bugs, Root Causes, and Best Practices

### Bug 1: "undeclared inclusion" errors

**Symptom:** Compilation fails with errors like:
```
error: undeclared inclusion(s) in rule '//src/cpp:github_client':
this rule is missing dependency declarations for the following files included by 'src/cpp/github_client.cc':
  '/home/user/.cache/bazel/.../_main~_repo_rules~gcc_toolchain/lib/gcc/.../include/stddef.h'
```

**Root Cause:** `cxx_builtin_include_directories` used *relative* paths (e.g.,
`external/gcc_toolchain/lib/gcc/.../include`) but GCC reports *absolute* paths internally.
Bazel compares the two and rejects any inclusion from a directory not in the allowed list.

**Fix:** Use absolute paths in `cxx_builtin_include_directories`. Since absolute paths aren't
available in normal Starlark rules, create a `repository_rule` (`gcc_toolchain_config`) that
resolves the path at fetch time and writes it to a `.bzl` file.

> **Best Practice:** Always use a `repository_rule` to resolve absolute paths for
> `cxx_builtin_include_directories` when integrating GCC-based toolchains. This is the same
> pattern used by `toolchains_llvm` in its `absolute_paths` mode.

---

### Bug 2: `collect2: fatal error: cannot find 'ld'`

**Symptom:** Linking fails because GCC's `collect2` wrapper cannot locate the linker.

**Root Cause:** The flag `-no-canonical-prefixes` prevents GCC from resolving its own
installation prefix via symlinks. Normally, GCC uses its own binary path to derive where
`ld`, `as`, etc. live. With `-no-canonical-prefixes`, it cannot, so `collect2` fails to
find the linker.

**Fix:** Add explicit `-B` flags pointing to *both*:
- `<toolchain_root>/bin` (main bin directory)
- `<toolchain_root>/x86_64-buildroot-linux-gnu/bin` (cross-tools directory with unprefixed `ld`)

> **Best Practice:** When using `-no-canonical-prefixes` (which you almost always should with
> Bazel for reproducible builds), always add `-B` flags for every directory that contains
> binaries GCC needs internally (`ld`, `as`, `collect2`, `lto-wrapper`).

---

### Bug 3: Sysroot path mismatch

**Symptom:** Compiler cannot find standard C library headers (`stdio.h`, `stdlib.h`, etc.)
or linker cannot find `crt1.o`, `crti.o`, `-lc`.

**Root Cause:** The sysroot was specified as a relative path in the compiler flags but as
an absolute path (or vice versa) in `builtin_sysroot`. GCC then searches the wrong
directory.

**Fix:** Use the same absolute path for `--sysroot=` in both compile and link flags, and
also for the `builtin_sysroot` parameter of `create_cc_toolchain_config_info`.

> **Best Practice:** Ensure `--sysroot=` in compile flags, `--sysroot=` in link flags, and
> `builtin_sysroot` in `create_cc_toolchain_config_info` all use the exact same value.
> Never mix relative and absolute paths.

---

### Bug 4: Missing `.bzl` file inside `http_archive`

**Symptom:** Build fails during loading phase:
```
ERROR: cannot load ':cc_toolchain_config.bzl': no such file
```

**Root Cause:** `build_file` only overlays the `BUILD` file into the repository. The
`cc_toolchain_config.bzl` file is a separate Starlark file that also needs to exist inside
the repository. There is no `extra_files` attribute on `http_archive`.

**Fix:** Use `patches` to inject the `.bzl` file into the archive via a `diff -Naur` patch
from `/dev/null`.

> **Best Practice:** When you need to add Starlark files (`.bzl`) to an `http_archive` that
> doesn't ship them, use `patches` with a unified diff from `/dev/null`. Structure the patch
> with `-p1` stripping so it's clean and reviewable.

---

### Bug 5: Incomplete `filegroup` declarations

**Symptom:** Compilation or linking fails with "file not found" errors for internal GCC
files (e.g., `crtbegin.o`, `libgcc.a`, `collect2`).

**Root Cause:** The `compiler_files` or `linker_files` filegroups didn't glob enough
directories. Bazel sandboxes the build, so only files declared in the filegroups are
available.

**Fix:** Ensure filegroups cover all directories GCC accesses:

| Filegroup | Must include |
|---|---|
| `compiler_files` | `bin/*`, `lib/gcc/**/*`, `libexec/**/*`, `include/**/*`, sysroot headers |
| `linker_files` | `bin/*`, `lib/gcc/**/*`, `libexec/**/*`, sysroot libs, `lib64/*` |
| `ar_files` | `bin/*ar` |

> **Best Practice:** When defining filegroups, use `gcc -v` and `strace` to discover
> exactly which files GCC accesses during compilation and linking. Over-globbing is safer
> than under-globbing (at the cost of slightly slower repository fetching).

---

### Summary of Best Practices

| # | Practice |
|---|---|
| 1 | Use a `repository_rule` to resolve absolute paths for `cxx_builtin_include_directories` |
| 2 | Always add `-B` flags when using `-no-canonical-prefixes` |
| 3 | Keep `--sysroot` consistent across compile flags, link flags, and `builtin_sysroot` |
| 4 | Inject `.bzl` files into `http_archive` using `patches`, not `build_file` |
| 5 | Use generous `glob()` patterns in filegroups; verify with `strace` or `gcc -v` |
| 6 | Pin the tarball with `sha256` for reproducibility and security |
| 7 | Use `strip_prefix` to flatten the tarball's directory structure |
| 8 | Match `toolchain_identifier` between `cc_toolchain` and `cc_toolchain_config` |
| 9 | List all 7+ include directories that `gcc -v -xc++ /dev/null -fsyntax-only` reports |
| 10 | Always specify both `exec_compatible_with` and `target_compatible_with` on the `toolchain()` rule |

---

## Future: Separating the Toolchain into a Common Repository

### Goal

Decouple the toolchain **implementation** (reusable across all projects) from the
**configuration/usage** (project-specific). This enables:

- A single source of truth for the toolchain definition.
- Multiple consuming repositories that share the same GCC integration.
- Independent versioning of toolchain vs. application code.

### Proposed Repository Structure

```
┌───────────────────────────────────────────────────────┐
│               common-toolchain repo                    │
│             (e.g., github.com/org/bazel-gcc-toolchain) │
│                                                        │
│  MODULE.bazel        ← declares this as a bazel_dep   │
│  toolchain/                                            │
│    BUILD             ← toolchain() bridge rules        │
│    BUILD.gcc         ← cc_toolchain + filegroups       │
│    cc_toolchain_config.bzl   ← compiler config rule    │
│    gcc_toolchain_config.bzl  ← absolute path resolver  │
│    inject_config.patch       ← patch for http_archive  │
│  extensions/                                           │
│    gcc.bzl           ← module extension for consumers  │
└───────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────┐
│               consumer repo A                          │
│                                                        │
│  MODULE.bazel                                          │
│    bazel_dep(name = "bazel_gcc_toolchain", ...)        │
│    gcc = use_extension("@bazel_gcc_toolchain//ext:...") │
│    gcc.configure(gcc_version = "12.3", arch = "x86_64")│
│                                                        │
│  src/                                                  │
│    cpp/                                                │
│      BUILD           ← cc_binary, cc_library, etc.     │
│      main.cc                                           │
└───────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────┐
│               consumer repo B                          │
│                 (same pattern)                         │
└───────────────────────────────────────────────────────┘
```

### Layer Separation

#### Common Toolchain Repository — **Implementation + Patching**

This repository owns:

1. **`cc_toolchain_config.bzl`** — The Starlark rule that configures GCC for Bazel.
2. **`gcc_toolchain_config.bzl`** — The `repository_rule` that resolves absolute paths.
3. **`BUILD.gcc`** — The overlay BUILD file for the downloaded tarball.
4. **`inject_config.patch`** — The patch that injects the config into the tarball.
5. **`BUILD`** (with `toolchain()` rule) — Platform constraint declarations.
6. **`extensions/gcc.bzl`** — A **module extension** that acts as the public API.

The module extension encapsulates all complexity:

```starlark
# extensions/gcc.bzl  (in common-toolchain repo)

_TOOLCHAINS = {
    "12.3-x86_64": struct(
        url = "https://toolchains.bootlin.com/.../x86-64--glibc--stable-2024.02-1.tar.bz2",
        sha256 = "19c8e5bc...",
        strip_prefix = "x86-64--glibc--stable-2024.02-1",
        prefix = "x86_64-buildroot-linux-gnu",
        gcc_version = "12.3.0",
    ),
    # Future: add more versions/architectures here
    # "13.2-aarch64": struct(...),
}

def _gcc_impl(module_ctx):
    for mod in module_ctx.modules:
        for cfg in mod.tags.configure:
            key = cfg.gcc_version + "-" + cfg.arch
            tc = _TOOLCHAINS[key]

            # 1. Download the tarball
            http_archive(
                name = "gcc_toolchain",
                url = tc.url,
                sha256 = tc.sha256,
                strip_prefix = tc.strip_prefix,
                build_file = "@bazel_gcc_toolchain//toolchain:BUILD.gcc",
                patches = ["@bazel_gcc_toolchain//toolchain:inject_config.patch"],
                patch_args = ["-p1"],
            )

            # 2. Resolve absolute path
            gcc_toolchain_config(name = "gcc_toolchain_config")

_configure = tag_class(attrs = {
    "gcc_version": attr.string(default = "12.3"),
    "arch": attr.string(default = "x86_64"),
})

gcc = module_extension(
    implementation = _gcc_impl,
    tag_classes = {"configure": _configure},
)
```

#### Consumer Repository — **Configuration + Usage**

Each consuming repository only needs:

```starlark
# MODULE.bazel (in consumer repo)

bazel_dep(name = "bazel_gcc_toolchain", version = "1.0.0")

gcc = use_extension("@bazel_gcc_toolchain//extensions:gcc.bzl", "gcc")
gcc.configure(
    gcc_version = "12.3",
    arch = "x86_64",
)
use_repo(gcc, "gcc_toolchain", "gcc_toolchain_config")

register_toolchains("@bazel_gcc_toolchain//toolchain:gcc_toolchain")
```

That's it. No toolchain files, no patches, no Starlark rules in the consumer.

### Step-by-Step Migration Plan

| Step | Action | Details |
|---|---|---|
| 1 | **Create the common repo** | `github.com/org/bazel-gcc-toolchain` with its own `MODULE.bazel` |
| 2 | **Move all `toolchain/` files** | Copy `BUILD`, `BUILD.gcc`, `cc_toolchain_config.bzl`, `gcc_toolchain_config.bzl`, `inject_config.patch` |
| 3 | **Create the module extension** | Write `extensions/gcc.bzl` with a `configure` tag class |
| 4 | **Publish the common repo** | Add to Bazel Central Registry (BCR) or use `git_override` / `archive_override` |
| 5 | **Update consumer repos** | Replace local toolchain files with `bazel_dep` + `use_extension` |
| 6 | **Remove local toolchain dir** | Delete `toolchain/` from each consumer repo |

### Advantages of This Separation

| Benefit | Explanation |
|---|---|
| **Single source of truth** | Toolchain bugs are fixed once, all consumers get the fix |
| **Version pinning** | Consumers pin the toolchain repo version in `MODULE.bazel` — reproducible builds |
| **Multi-architecture support** | The common repo can ship configs for x86_64, aarch64, RISC-V, etc. |
| **Independent release cycle** | Toolchain version upgrades don't require simultaneous changes in all consumer repos |
| **Simplified consumer BUILD files** | Consumers never touch toolchain internals — just `cc_binary`, `cc_library`, etc. |
| **Testing in isolation** | The toolchain repo can have its own CI with compilation smoke tests |

### Considerations and Gotchas

1. **BCR registration:** If you publish to the Bazel Central Registry, follow their
   [contribution guidelines](https://github.com/bazelbuild/bazel-central-registry).
   Alternatively, use `archive_override` or `git_override` for private toolchains.

2. **Patch maintenance:** When the patch (`inject_config.patch`) injects the full
   `cc_toolchain_config.bzl`, any change to the config requires regenerating the patch.
   Consider using a script or Makefile target:
   ```bash
   diff -Naur /dev/null toolchain/cc_toolchain_config.bzl > toolchain/inject_config.patch
   ```

3. **Absolute path resolver timing:** The `gcc_toolchain_config` repository rule has an
   implicit dependency on `@gcc_toolchain`. Bazel handles this correctly but the ordering
   matters — the `http_archive` must be declared *before* the `gcc_toolchain_config` rule.

4. **Testing the common repo:** Include a minimal `cc_binary` test target in the common
   repo that compiles a "Hello, World!" with the toolchain. Run it in CI to catch
   regressions early.

5. **Multi-architecture via tag classes:** The `configure` tag class can accept `arch`
   and `gcc_version` parameters. Map these to the correct Bootlin URL, `strip_prefix`,
   and `prefix` values in a dictionary. This scales cleanly to many targets.

---

## Quick Reference: Building with the Toolchain

```bash
# Build a C++ target (toolchain is auto-selected via register_toolchains)
bazel build //src/cpp:github_checker

# Explicitly select the toolchain (useful for debugging)
bazel build //src/cpp:github_checker \
  --extra_toolchains=//toolchain:gcc_toolchain

# Verify which toolchain Bazel selected
bazel cquery --output=starlark \
  --starlark:expr="providers(target)['CcToolchainInfo'].toolchain_id" \
  //src/cpp:github_checker

# Debug include path issues
bazel build //src/cpp:github_checker --sandbox_debug -s 2>&1 | grep -E '(-I|-isystem|sysroot)'
```
