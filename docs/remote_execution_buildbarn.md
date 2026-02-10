# Using the Hermetic GCC 10 Toolchain with Remote Execution on BuildBarn

## Table of Contents

- [Overview](#overview)
- [How the Current Toolchain Works Locally](#how-the-current-toolchain-works-locally)
- [The Core Problem: Absolute Paths](#the-core-problem-absolute-paths)
- [BuildBarn Architecture Overview](#buildbarn-architecture-overview)
- [What Needs to Change](#what-needs-to-change)
  - [1. Eliminate Absolute Paths from Toolchain Configuration](#1-eliminate-absolute-paths-from-toolchain-configuration)
  - [2. Define a Remote Execution Platform](#2-define-a-remote-execution-platform)
  - [3. Configure the Toolchain for Remote Platform Matching](#3-configure-the-toolchain-for-remote-platform-matching)
  - [4. Create a `.bazelrc` Remote Execution Config](#4-create-a-bazelrc-remote-execution-config)
  - [5. Configure the BuildBarn Worker to Match the Platform](#5-configure-the-buildbarn-worker-to-match-the-platform)
  - [6. Handle Dynamic Linker and RPATH for Remote Workers](#6-handle-dynamic-linker-and-rpath-for-remote-workers)
  - [7. Static Linking Alternative (Simpler Approach)](#7-static-linking-alternative-simpler-approach)
- [Detailed Implementation Steps](#detailed-implementation-steps)
  - [Step 1: Refactor `cc_toolchain_config.bzl` to Use Execution-Root-Relative Paths](#step-1-refactor-cc_toolchain_configbzl-to-use-execution-root-relative-paths)
  - [Step 2: Define Execution Platform with `exec_properties`](#step-2-define-execution-platform-with-exec_properties)
  - [Step 3: Update Toolchain Registration for Remote Compatibility](#step-3-update-toolchain-registration-for-remote-compatibility)
  - [Step 4: Configure `.bazelrc` for BuildBarn](#step-4-configure-bazelrc-for-buildbarn)
  - [Step 5: Configure BuildBarn Worker Platform Properties](#step-5-configure-buildbarn-worker-platform-properties)
  - [Step 6: Verify with Docker Sandbox](#step-6-verify-with-docker-sandbox)
- [Approach Comparison: Two Strategies](#approach-comparison-two-strategies)
  - [Strategy A — Ship Toolchain as Input (Recommended)](#strategy-a--ship-toolchain-as-input-recommended)
  - [Strategy B — Pre-install Toolchain in Worker Container](#strategy-b--pre-install-toolchain-in-worker-container)
- [Testing and Verification](#testing-and-verification)
- [Troubleshooting](#troubleshooting)
- [References](#references)

---

## Overview

The GCC 10.3 hermetic toolchain is currently configured for **local execution only**.
It works by resolving the **absolute filesystem path** of the downloaded Bootlin
tarball at repository-fetch time (via the `gcc_toolchain_config` repository rule)
and embedding that absolute path into the `cc_toolchain_config`. This is fundamental
to making `cxx_builtin_include_directories` match what GCC reports during compilation.

**Remote execution on BuildBarn** requires that build actions run on separate worker
machines. The absolute paths embedded in the current toolchain configuration will
not exist on remote workers, causing actions to fail. This document describes what
needs to change to make the hermetic GCC 10 toolchain work with BuildBarn remote
execution.

---

## How the Current Toolchain Works Locally

The current setup uses a three-layer architecture (see `docs/gcc_toolchain_architecture.md`):

1. **`MODULE.bazel`** downloads the Bootlin GCC 10.3 tarball via `http_archive` into
   `@gcc10_toolchain` and uses `gcc_toolchain_config` repository rule to resolve
   the absolute path at fetch time.

2. **`gcc_toolchain_config.bzl`** (repository rule) writes the absolute path as
   `GCC_TOOLCHAIN_ABSOLUTE_PATH` into a generated `defs.bzl`.

3. **`cc_toolchain_config.bzl`** uses this absolute path for:
   - `cxx_builtin_include_directories` (7 absolute paths)
   - `builtin_sysroot` (absolute path to the sysroot)
   - `-B` flags (pointing to `bin/` and cross-tools directories)
   - `--dynamic-linker` (absolute path to the toolchain's `ld-linux-x86-64.so.2`)
   - `-rpath` entries (absolute paths to the toolchain's lib directories)

**Example absolute path:**
```
/home/user/.cache/bazel/_bazel_user/HASH/external/_main~_repo_rules~gcc10_toolchain
```

This path is unique to each developer's machine and will not exist on BuildBarn workers.

---

## The Core Problem: Absolute Paths

Remote execution sends **actions** (command + input files) to workers. The worker
reconstructs the input tree under a working directory. Within this working
directory, Bazel repositories appear at predictable execution-root-relative paths:

```
<exec_root>/external/_main~_repo_rules~gcc10_toolchain/...
```

However, the **absolute prefix** (e.g., `/home/user/.cache/bazel/...`) is different
on every machine, and on a BuildBarn worker, the execution root is typically
under a path like:

```
/worker/build/<operation-hash>/
```

All the absolute paths currently hardcoded in the toolchain config would be
**wrong** on the worker. Specifically:

| Component | Current (absolute) | Needed for RBE (relative to exec root) |
|-----------|-------------------|----------------------------------------|
| `cxx_builtin_include_directories` | `/home/user/.cache/bazel/.../gcc10_toolchain/...` | `external/_main~_repo_rules~gcc10_toolchain/...` |
| `builtin_sysroot` | Absolute path | Relative to exec root |
| `-B` flags | Absolute paths | Relative to exec root |
| `--dynamic-linker` | Absolute path | Relative to exec root or use `$ORIGIN` |
| `-rpath` | Absolute paths | Relative or `$ORIGIN`-based |

---

## BuildBarn Architecture Overview

BuildBarn's remote execution consists of:

| Component | Role |
|-----------|------|
| **`bb-storage`** (frontend) | Receives gRPC requests from Bazel, manages CAS and Action Cache |
| **`bb-scheduler`** | Queues actions and matches them to workers based on platform properties |
| **`bb-worker`** | Downloads input files, creates execution directory, delegates to runner |
| **`bb-runner`** | Executes the actual command inside the build directory |

**Platform matching** is critical: Bazel sends `exec_properties` with each action
(e.g., `OSFamily=linux`, `container-image=docker://...`). The scheduler matches
these properties against the workers' declared platform properties. Workers only
receive actions whose platform properties they declare support for.

The worker image determines what software is available on the execution
environment. The default `bb-deployments` setup uses
`ghcr.io/catthehacker/ubuntu:act-22.04` as the runner image.

---

## What Needs to Change

### 1. Eliminate Absolute Paths from Toolchain Configuration

The `cc_toolchain_config.bzl` currently receives `toolchain_path_prefix` as an
absolute path (from `GCC_TOOLCHAIN_ABSOLUTE_PATH`). For remote execution, this
must be changed to use **execution-root-relative paths**.

**Key insight:** When Bazel sends an action to a remote worker, the toolchain
files declared in `cc_toolchain.all_files`, `compiler_files`, `linker_files`,
etc. are included as inputs. They appear in the worker's input tree at their
execution-root-relative paths (e.g., `external/_main~_repo_rules~gcc10_toolchain/bin/...`).

**For `cxx_builtin_include_directories`:** Bazel has special support: if a path
starts with `%package(...)%`, it is resolved relative to the package. But more
practically, for remote execution, these paths need to either:
- Use the `%sysroot%` prefix (which Bazel resolves relative to `builtin_sysroot`)
- Match what the compiler reports in its `-v` output on the remote worker

**Challenge:** GCC always reports its built-in include directories as absolute
paths when you run `gcc -v`. If the exec root path is different on the remote
worker (it will be), these won't match. Solutions include:
- Using `-nostdinc` and passing include paths explicitly via `-isystem` flags
- Using `-no-canonical-prefixes` and configuring relative sysroot paths
- Ensuring `cxx_builtin_include_directories` lists paths relative to the
  remote worker's exec root

### 2. Define a Remote Execution Platform

Create a `platform()` target with `exec_properties` that tells BuildBarn which
worker to run actions on. This is how Bazel communicates container image
requirements and OS family to the scheduler.

```starlark
platform(
    name = "buildbarn_remote_platform",
    constraint_values = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
        ":buildbarn-worker",  # custom constraint for remote workers
    ],
    exec_properties = {
        "OSFamily": "linux",
        "container-image": "docker://<your-worker-image>@sha256:<digest>",
    },
)
```

The `exec_properties` values must **exactly match** what the BuildBarn worker
declares in its configuration (see Step 5).

### 3. Configure the Toolchain for Remote Platform Matching

The `toolchain()` target in `toolchain/BUILD` needs `exec_compatible_with`
constraints that match the remote platform. This tells Bazel to use the GCC 10
toolchain when building actions that target the remote platform.

```starlark
toolchain(
    name = "gcc10_remote_toolchain",
    exec_compatible_with = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
        ":buildbarn-worker",  # must match the platform constraint
    ],
    target_compatible_with = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
    ],
    toolchain = "@gcc10_toolchain//:k8_toolchain",
    toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
)
```

### 4. Create a `.bazelrc` Remote Execution Config

Add a `--config=remote-gcc10` configuration block:

```bash
# BuildBarn remote execution base
build:remote-exec --remote_executor=grpc://<buildbarn-frontend>:8980
build:remote-exec --remote_instance_name=fuse
build:remote-exec --jobs=64
build:remote-exec --remote_download_toplevel
build:remote-exec --incompatible_strict_action_env
build:remote-exec --dynamic_mode=off

# Remote execution with GCC 10 toolchain
build:remote-gcc10 --config=remote-exec
build:remote-gcc10 --extra_execution_platforms=//toolchain:buildbarn_remote_platform
build:remote-gcc10 --extra_toolchains=//toolchain:gcc10_remote_toolchain
```

### 5. Configure the BuildBarn Worker to Match the Platform

In the BuildBarn worker Jsonnet configuration, the `platform.properties` must
match the `exec_properties` declared in the Bazel platform:

```jsonnet
runners: [{
  endpoint: { address: 'unix:///worker/runner' },
  concurrency: 8,
  instanceNamePrefix: 'fuse',
  platform: {
    properties: [
      { name: 'OSFamily', value: 'linux' },
      { name: 'container-image', value: 'docker://<your-worker-image>@sha256:<digest>' },
    ],
  },
}]
```

**Critical:** The `container-image` value in the worker config must be
**byte-identical** to what's in the Bazel platform's `exec_properties`.

### 6. Handle Dynamic Linker and RPATH for Remote Workers

The current toolchain configuration embeds absolute paths for:
- `--dynamic-linker=<absolute-path>/sysroot/lib/ld-linux-x86-64.so.2`
- `-rpath,<absolute-path>/sysroot/lib`

For remote execution, these must be changed:

**Option A: Use `$ORIGIN`-relative RPATH** (recommended for produced binaries):
```
-Wl,-rpath,$ORIGIN/../lib
```
This makes the binary find libraries relative to its own location.

**Option B: Use exec-root-relative paths for compilation actions:**
The dynamic linker path can be set relative to the execution root since the
toolchain files are shipped as action inputs. However, the resulting binary
will only run correctly on a machine with the same path layout.

**Option C: Static linking** (simplest for remote execution):
```
-static
-static-libstdc++
-static-libgcc
```
This eliminates runtime library dependencies entirely. Binaries are larger
but fully portable.

### 7. Static Linking Alternative (Simpler Approach)

The simplest way to avoid all dynamic linker/RPATH issues for remote execution
is to use **static linking**. This means the produced binaries don't need any
runtime libraries from the toolchain:

```bash
build:remote-gcc10 --linkopt=-static
```

This is the recommended starting point for remote execution with hermetic GCC
toolchains because it eliminates the entire category of runtime path problems.

---

## Detailed Implementation Steps

### Step 1: Refactor `cc_toolchain_config.bzl` to Use Execution-Root-Relative Paths

The `cc_toolchain_config.bzl` must support **two modes**:

1. **Local mode** (current): Uses absolute paths from `GCC_TOOLCHAIN_ABSOLUTE_PATH`
2. **Remote mode** (new): Uses execution-root-relative paths

**Approach:** Add a `use_absolute_paths` attribute to the `cc_toolchain_config` rule.
When `False`, compute all paths relative to the execution root:

```starlark
# For remote execution, the toolchain path is relative to the exec root
# e.g., "external/_main~_repo_rules~gcc10_toolchain"
toolchain_path_prefix = "external/_main~_repo_rules~gcc10_toolchain"
```

**For `cxx_builtin_include_directories`:** The challenge is that GCC will
report absolute paths when invoked. Bazel uses these to validate that included
headers are declared. For remote execution, consider:

1. Disabling strict header checking with `--features=-layering_check` or
   `--sandbox_debug` (not recommended for production)
2. Using `--copt=-w` to suppress warnings
3. Constructing the correct paths matching the remote execution root

**The most robust solution** is to use `--features=no_legacy_features` and
construct the include directories to match the exec root on the remote worker.
Since BuildBarn workers use a deterministic exec root structure, the relative
path `external/_main~_repo_rules~gcc10_toolchain/...` will be correct.

### Step 2: Define Execution Platform with `exec_properties`

Create a BUILD file (or extend `toolchain/BUILD`) with:

```starlark
# Custom constraint to distinguish remote BuildBarn workers
constraint_setting(name = "execution-environment")

constraint_value(
    name = "buildbarn-worker",
    constraint_setting = ":execution-environment",
)

platform(
    name = "buildbarn_gcc10_platform",
    constraint_values = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
        ":buildbarn-worker",
    ],
    exec_properties = {
        "OSFamily": "linux",
        # Use a minimal container — the toolchain is shipped as inputs
        "container-image": "docker://ghcr.io/catthehacker/ubuntu:act-22.04@sha256:<digest>",
    },
)
```

### Step 3: Update Toolchain Registration for Remote Compatibility

Register a separate toolchain target for remote execution:

```starlark
toolchain(
    name = "gcc10_remote_toolchain",
    exec_compatible_with = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
        ":buildbarn-worker",
    ],
    target_compatible_with = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
    ],
    toolchain = "@gcc10_toolchain//:k8_toolchain_remote",  # remote variant
    toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
)
```

This requires a corresponding `k8_toolchain_remote` target in `BUILD.gcc10`
that uses the remote-mode `cc_toolchain_config`.

### Step 4: Configure `.bazelrc` for BuildBarn

```bash
# ---- BuildBarn Remote Execution ----
build:remote-exec --remote_executor=grpc://localhost:8980
build:remote-exec --remote_instance_name=fuse
build:remote-exec --jobs=64
build:remote-exec --remote_download_toplevel
build:remote-exec --incompatible_strict_action_env
# Dynamic linking is problematic with remote execution
build:remote-exec --dynamic_mode=off

# Remote GCC 10 config
build:remote-gcc10 --config=remote-exec
build:remote-gcc10 --extra_execution_platforms=//toolchain:buildbarn_gcc10_platform
build:remote-gcc10 --extra_toolchains=//toolchain:gcc10_remote_toolchain
# Optional: force static linking to avoid RPATH issues
build:remote-gcc10 --linkopt=-static
```

### Step 5: Configure BuildBarn Worker Platform Properties

In your BuildBarn deployment's worker Jsonnet configuration:

```jsonnet
{
  // ... storage, scheduler, etc.
  buildDirectories: [{
    virtual: {
      // ... FUSE or hardlinking config
    },
    runners: [{
      endpoint: { address: 'unix:///worker/runner' },
      concurrency: 8,
      instanceNamePrefix: 'fuse',
      platform: {
        properties: [
          { name: 'OSFamily', value: 'linux' },
          {
            name: 'container-image',
            value: 'docker://ghcr.io/catthehacker/ubuntu:act-22.04@sha256:<digest>',
          },
        ],
      },
    }],
  }],
}
```

**Worker container requirements:**
- The container needs no special pre-installed compilers — the GCC toolchain
  is shipped as action inputs by Bazel
- The container should have basic OS utilities (`/bin/sh`, etc.)
- The container must match the `container-image` value in `exec_properties` exactly

### Step 6: Verify with Docker Sandbox

Before deploying to BuildBarn, test locally using Bazel's Docker sandbox:

```bash
# Test that the build works in a container environment
bazel build \
  --config=remote-gcc10 \
  --spawn_strategy=docker \
  --experimental_docker_image=ghcr.io/catthehacker/ubuntu:act-22.04 \
  --experimental_enable_docker_sandbox \
  //src/cpp:main
```

This simulates remote execution locally and catches most issues before
deploying to actual BuildBarn workers.

---

## Approach Comparison: Two Strategies

### Strategy A — Ship Toolchain as Input (Recommended)

**How it works:** The GCC toolchain tarball (downloaded by `http_archive`) is
declared as an input to every compile/link action via the `cc_toolchain`
filegroups (`all_files`, `compiler_files`, `linker_files`). Bazel uploads these
files to the CAS (Content Addressable Storage) and they are materialized on
the worker before action execution.

**Advantages:**
- ✅ Truly hermetic — workers need no pre-installed compilers
- ✅ Toolchain version is controlled entirely by Bazel — change the version
  in `MODULE.bazel` and all workers automatically use it
- ✅ No need to build/maintain custom worker container images
- ✅ Multiple toolchain versions can coexist

**Disadvantages:**
- ❌ First action is slower (toolchain files need to be uploaded to CAS)
- ❌ Requires refactoring `cc_toolchain_config.bzl` to avoid absolute paths
- ❌ The Bootlin tarball is ~1.5 GB — significant CAS storage requirement
- ❌ `cxx_builtin_include_directories` must match remote exec root paths

**Required changes:**
1. Refactor `cc_toolchain_config.bzl` to support relative paths
2. May need to remove `gcc_toolchain_config` repository rule for remote mode
   (or compute the exec-root-relative path instead)
3. Use static linking or `$ORIGIN`-relative RPATH
4. Define remote platform and toolchain targets
5. Update `.bazelrc`

### Strategy B — Pre-install Toolchain in Worker Container

**How it works:** Build a custom Docker image that has the Bootlin GCC 10.3
toolchain pre-installed at a fixed, known path (e.g., `/opt/gcc10`). The
`cc_toolchain_config` uses this fixed absolute path.

**Advantages:**
- ✅ Minimal changes to existing toolchain configuration
- ✅ Absolute paths work because the toolchain is at the same path on every worker
- ✅ Faster action execution — no toolchain upload needed
- ✅ `cxx_builtin_include_directories` can use the fixed absolute paths

**Disadvantages:**
- ❌ Not truly hermetic from Bazel's perspective — workers have hidden state
- ❌ Toolchain updates require rebuilding and redeploying worker images
- ❌ Must keep the container image path in sync between Bazel config and
  BuildBarn deployment
- ❌ Lost benefit: Bazel doesn't track the toolchain as a build input,
  so changing toolchain version may not invalidate the cache properly

**Required changes:**
1. Build a Dockerfile that installs the Bootlin tarball at `/opt/gcc10`
2. Update `cc_toolchain_config.bzl` to use `/opt/gcc10` as the prefix
   (or keep the existing resolver but ensure the path matches)
3. Push the image to a container registry
4. Configure BuildBarn workers and Bazel platform to use this image
5. Update `.bazelrc`

**Example Dockerfile:**
```dockerfile
FROM ghcr.io/catthehacker/ubuntu:act-22.04
RUN apt-get update && apt-get install -y wget bzip2
RUN wget -qO- https://toolchains.bootlin.com/downloads/releases/toolchains/x86-64/tarballs/x86-64--glibc--stable-2021.11-5.tar.bz2 \
    | tar xj -C /opt \
    && mv /opt/x86-64--glibc--stable-2021.11-5 /opt/gcc10
```

---

## Testing and Verification

### 1. Validate Toolchain Isolation

After implementing the changes, verify that no host tools leak into the build:

```bash
# Build with strict sandboxing locally first
bazel build --config=gcc10 --sandbox_debug //src/cpp:main 2>&1 | grep "undeclared inclusion"
```

### 2. Test Remote Execution

```bash
# Build against BuildBarn
bazel build --config=remote-gcc10 //src/cpp:main
```

Expected output should show `remote` in the process summary:
```
INFO: XX processes: Y internal, Z remote.
```

### 3. Verify Binary Hermeticity

If dynamically linked, verify the produced binary uses correct library paths:

```bash
readelf -l bazel-bin/src/cpp/main | grep interpreter
ldd bazel-bin/src/cpp/main
readelf -d bazel-bin/src/cpp/main | grep RPATH
```

If statically linked, verify no dynamic dependencies:

```bash
file bazel-bin/src/cpp/main
# Expected: "statically linked"
ldd bazel-bin/src/cpp/main
# Expected: "not a dynamic executable"
```

### 4. Verify Cache Sharing

Clean and rebuild to confirm CAS caching works:

```bash
bazel clean
bazel build --config=remote-gcc10 //src/cpp:main
```

Expected: most actions should show as cached (not re-executed).

---

## Troubleshooting

### "undeclared inclusion" Errors

**Cause:** `cxx_builtin_include_directories` paths don't match what GCC reports
on the remote worker.

**Fix:** Ensure the paths in `cxx_builtin_include_directories` match the exact
exec-root-relative path where the toolchain files are materialized on the worker.
Use `bazel build --sandbox_debug` to see the actual paths.

### "No toolchain found" Errors

**Cause:** Platform constraints don't match between the `toolchain()` target's
`exec_compatible_with` and the remote platform's `constraint_values`.

**Fix:** Ensure the custom constraint (e.g., `:buildbarn-worker`) is present in
both the `platform()` and `toolchain()` declarations.

### Actions Failing with "file not found" for GCC Binaries

**Cause:** The toolchain files aren't being included as action inputs.

**Fix:** Verify that `cc_toolchain.all_files`, `compiler_files`, and
`linker_files` filegroups capture all necessary files from the tarball.
Use `bazel aquery` to inspect what inputs are sent with compile actions:

```bash
bazel aquery --config=remote-gcc10 'mnemonic("CppCompile", //src/cpp:main)'
```

### Platform Properties Mismatch

**Cause:** The `exec_properties` in the Bazel platform don't exactly match the
BuildBarn worker's `platform.properties`.

**Fix:** Ensure byte-identical values. Even a trailing space or different
hash format will cause a mismatch. The BuildBarn scheduler logs will show
unmatched platform properties.

### Remote Actions Timeout or Hang

**Cause:** CAS upload of the full toolchain (~1.5 GB) takes too long.

**Fix:**
- Increase `--remote_timeout` (default is 60s)
- Use BuildBarn's CAS deduplication (sharded storage)
- Consider Strategy B (pre-installed toolchain) for large toolchains
- Use `--remote_download_minimal` to reduce download overhead

---

## References

- [Bazel Remote Execution Overview](https://bazel.build/remote/rbe)
- [Adapting Bazel Rules for Remote Execution](https://bazel.build/remote/rules)
- [Bazel Platforms Documentation](https://bazel.build/extending/platforms)
- [Bazel Toolchains Documentation](https://bazel.build/extending/toolchains)
- [Troubleshooting Bazel Remote Execution with Docker Sandbox](https://bazel.build/remote/sandbox)
- [BuildBarn Deployments Repository](https://github.com/buildbarn/bb-deployments)
- [BuildBarn Remote Execution Repository](https://github.com/buildbarn/bb-remote-execution)
- [bb-deployments Docker Compose Setup](https://github.com/buildbarn/bb-deployments/tree/main/docker-compose)
- [bb-deployments Remote Toolchain Example](https://github.com/buildbarn/bb-deployments/blob/main/tools/remote-toolchains/BUILD.bazel)
- [Remote APIs gRPC Protocol (REAPI)](https://github.com/bazelbuild/remote-apis)
- Project-internal docs:
  - [docs/gcc_toolchain_architecture.md](gcc_toolchain_architecture.md) — How the hermetic GCC toolchain is structured
  - [docs/hermetic_toolchain_verification.md](hermetic_toolchain_verification.md) — Verification that the toolchain is hermetic locally
  - [docs/integration_guide.md](integration_guide.md) — How consumers integrate the toolchains
