# Python Hermetic Setup Verification

## Overview

This project uses a **fully hermetic Python setup** where both the Python interpreter and all dependencies are bundled and managed by Bazel. This ensures reproducible builds across different machines and eliminates dependencies on system Python installations.

## Hermetic Components

### 1. Python Interpreter: HERMETIC ✅

**Bundled Python 3.11.8** from the Bootlin GCC toolchain

- **Location**: `external/_main~_repo_rules~gcc_toolchain/bin/python3.11`
- **Version**: Python 3.11.8
- **Source**: Bundled with the Bootlin GCC stable-2024.02-1 toolchain
- **System Python**: 3.10.12 (NOT USED)

The Bootlin GCC toolchain (originally downloaded for hermetic C++ builds) includes a complete Python 3.11.8 distribution, which `rules_python` automatically detects and uses.

#### Verification

```bash
# Check dependencies
$ bazel cquery 'deps(//src/python:github_checker)' --output=files 2>/dev/null | grep python3 | head -3
external/_main~_repo_rules~gcc_toolchain/bin/python3
external/_main~_repo_rules~gcc_toolchain/bin/python3.11
external/_main~_repo_rules~gcc_toolchain/bin/python3-config

# Verify bundled Python version
$ ~/.cache/bazel/_bazel_iangelov/*/external/_main~_repo_rules~gcc_toolchain/bin/python3.11 --version
Python 3.11.8

# Compare with system Python (not used)
$ python3 --version
Python 3.10.12
```

### 2. Python Packages: HERMETIC ✅

**All pip dependencies downloaded by Bazel** into isolated external repositories

- **Configuration**: `pip.parse()` in [MODULE.bazel](../MODULE.bazel)
- **Lock File**: [requirements_lock.txt](../requirements_lock.txt)
- **Package Storage**: `~/.cache/bazel/.../external/my_pip_install_*`

Each Python package is downloaded as a separate external repository:

```
my_pip_install_requests/        # requests 2.28.0
my_pip_install_pytest/          # pytest 7.1.0
my_pip_install_pyyaml/          # PyYAML 6.0.1
my_pip_install_attrs/           # attrs (transitive)
my_pip_install_certifi/         # certifi (transitive)
my_pip_install_charset_normalizer/  # charset-normalizer (transitive)
my_pip_install_idna/            # idna (transitive)
... and all other transitive dependencies
```

#### Package Structure

Each package repository contains:
```
my_pip_install_requests/
├── BUILD.bazel              # Bazel build rules
├── requests-2.28.0-py3-none-any.whl  # Wheel file
├── site-packages/           # Extracted package
└── WORKSPACE                # External repo marker
```

#### Verification

```bash
# List all pip-managed packages
$ ls -d ~/.cache/bazel/_bazel_iangelov/*/external/my_pip_install_* 2>/dev/null | wc -l
# Shows 14+ package repositories (direct + transitive dependencies)

# Check requests package
$ ls ~/.cache/bazel/_bazel_iangelov/*/external/my_pip_install_requests/
BUILD.bazel  requests-2.28.0-py3-none-any.whl  site-packages  WORKSPACE
```

## Configuration

### MODULE.bazel

The hermetic Python setup is configured in [MODULE.bazel](../MODULE.bazel):

```python
# Configure Python toolchain
python = use_extension("@rules_python//python/extensions:python.bzl", "python")
python.toolchain(
    python_version = "3.11",
)

# Configure pip dependencies
pip = use_extension("@rules_python//python/extensions:pip.bzl", "pip")
pip.parse(
    hub_name = "my_pip_install",
    python_version = "3.11",
    requirements_lock = "//:requirements_lock.txt",
)
use_repo(pip, "my_pip_install")
```

### requirements.in

User-defined dependencies with minimal version constraints:

```
requests==2.28.0
pytest==7.1.0
PyYAML==6.0.1
```

### requirements_lock.txt

Generated lock file with exact versions and transitive dependencies:

```bash
# Generate/update lock file
$ bazel run //:requirements.update
```

The lock file includes:
- All direct dependencies
- All transitive dependencies
- Exact versions with SHA256 hashes
- Platform-specific packages

### BUILD Files

Python targets reference dependencies via the `requirement()` macro:

```python
load("@rules_python//python:defs.bzl", "py_binary", "py_test")
load("@my_pip_install//:requirements.bzl", "requirement")

py_binary(
    name = "github_checker",
    srcs = ["main.py"],
    deps = [
        requirement("requests"),
        requirement("pyyaml"),
    ],
)

py_test(
    name = "github_checker_test",
    srcs = ["test_main.py"],
    deps = [
        requirement("pytest"),
    ],
)
```

## Benefits of Hermetic Python

### ✅ Reproducibility

**Identical builds across environments:**
- CI/CD servers produce the same binaries as local development
- No "works on my machine" issues
- Build outputs are deterministic

### ✅ Isolation

**No interference with system Python:**
- System Python: 3.10.12 → Not used
- Project Python: 3.11.8 → Bundled
- No conflicts with system-installed packages
- No PATH manipulation needed

### ✅ Version Control

**Exact dependency versions:**
- Lock file ensures exact versions (`requests==2.28.0`, not `>=2.28.0`)
- Transitive dependencies pinned (e.g., `certifi==2026.1.4`)
- SHA256 hashes verify package integrity
- Easy to audit and review dependency changes

### ✅ Portability

**Works on any Linux system:**
- No need to install Python 3.11 on host
- No need to create virtual environments
- No pip install commands required
- Bazel downloads everything automatically

## Comparison: System vs Hermetic

| Aspect | System Python | Hermetic Python (This Project) |
|--------|---------------|-------------------------------|
| **Interpreter** | `/usr/bin/python3` (3.10.12) | `external/.../gcc_toolchain/bin/python3.11` (3.11.8) |
| **Packages** | `/usr/lib/python3.10/` + `~/.local/` | `external/my_pip_install_*/` |
| **Setup** | `apt install python3-*` | Automatic via Bazel |
| **Reproducibility** | ❌ Varies by system | ✅ Identical everywhere |
| **Isolation** | ❌ Shared with system | ✅ Completely isolated |
| **CI/CD** | ⚠️ Manual setup | ✅ Automatic |

## How It Works

### Dependency Resolution Flow

```
1. User edits requirements.in
   └─→ Lists: requests==2.28.0, pytest==7.1.0, PyYAML==6.0.1

2. Run: bazel run //:requirements.update
   └─→ pip-compile resolves transitive dependencies
   └─→ Generates requirements_lock.txt with 14+ packages

3. Bazel build/run
   └─→ pip.parse() reads requirements_lock.txt
   └─→ Downloads each package as external repository
   └─→ Creates my_pip_install_<package> for each dependency

4. py_binary/py_test
   └─→ requirement("package") references external repo
   └─→ Bazel includes package in PYTHONPATH
   └─→ Python imports work transparently
```

### Runtime Behavior

When you run `bazel run //src/python:github_checker`:

1. **Bazel sets up environment:**
   - `PYTHON`: Points to bundled `python3.11` (3.11.8)
   - `PYTHONPATH`: Points to hermetic package directories
   - `PYTHONSAFEPATH`: Prevents system module imports

2. **Python executes with hermetic setup:**
   - Uses Python 3.11.8 (not system 3.10.12)
   - Imports only from Bazel-managed packages
   - System Python and packages are invisible

3. **Clean execution:**
   - No dependency on system Python installation
   - No virtual environment activation needed
   - Reproducible across all machines

## Verification Commands

### Check Python Interpreter

```bash
# What Python does the binary depend on?
bazel cquery 'deps(//src/python:github_checker)' --output=files | grep python3 | head -3

# Verify bundled Python version
~/.cache/bazel/_bazel_*/*/external/_main~_repo_rules~gcc_toolchain/bin/python3.11 --version

# Compare with system
python3 --version
```

### Check Package Installation

```bash
# List all pip-managed packages
ls -d ~/.cache/bazel/_bazel_*/*/external/my_pip_install_* | wc -l

# Inspect specific package
ls ~/.cache/bazel/_bazel_*/*/external/my_pip_install_requests/

# Check package version
cat requirements_lock.txt | grep "^requests=="
```

### Test Hermetic Execution

```bash
# Run Python binary
bazel run //src/python:github_checker

# Run Python tests
bazel test //src/python:github_checker_test

# Both use hermetic Python 3.11.8, not system Python 3.10.12
```

## Unexpected Discovery

**Python 3.11.8 comes from the GCC toolchain!**

The Bootlin GCC toolchain (downloaded for hermetic C++ compilation) includes a complete Python 3.11.8 distribution as part of its build environment. `rules_python` automatically detects and uses this bundled Python instead of downloading a separate Python interpreter.

This is a fortunate side effect that provides:
- ✅ Free hermetic Python (no extra downloads)
- ✅ Consistent Python version across C++ and Python builds
- ✅ Single toolchain source (Bootlin) for both languages

## Adding New Dependencies

### Process

1. **Edit requirements.in:**
   ```bash
   echo "numpy==1.24.0" >> requirements.in
   ```

2. **Regenerate lock file:**
   ```bash
   bazel run //:requirements.update
   ```
   This runs `pip-compile` to:
   - Resolve transitive dependencies
   - Download packages
   - Generate updated `requirements_lock.txt`

3. **Update BUILD file:**
   ```python
   py_binary(
       name = "my_target",
       deps = [
           requirement("numpy"),  # Add new dependency
       ],
   )
   ```

4. **Build/Run:**
   ```bash
   bazel run //src/python:my_target
   ```
   Bazel automatically downloads `numpy` and its dependencies.

## References

- **rules_python Documentation**: [https://github.com/bazelbuild/rules_python](https://github.com/bazelbuild/rules_python)
- **pip.parse() API**: [https://rules-python.readthedocs.io/en/latest/pypi-dependencies.html](https://rules-python.readthedocs.io/en/latest/pypi-dependencies.html)
- **Bootlin Toolchains**: [https://toolchains.bootlin.com/](https://toolchains.bootlin.com/)
- **Bazel Python Extension**: [MODULE.bazel](../MODULE.bazel)

## Summary

✅ **Python Interpreter**: Fully hermetic (Python 3.11.8 from GCC toolchain)  
✅ **Python Packages**: Fully hermetic (all packages downloaded by Bazel)  
✅ **Reproducibility**: Guaranteed identical builds  
✅ **Isolation**: No system Python interference  
✅ **Portability**: Works on any Linux system  

**Result**: A completely hermetic Python environment that requires zero system dependencies! 🎯
