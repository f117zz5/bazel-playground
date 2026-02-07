"""
Clang 17 toolchain configuration reference for consumer workspaces.

IMPORTANT: This file is for REFERENCE ONLY.  MODULE.bazel cannot load()
arbitrary .bzl files — it only supports Bzlmod directives (bazel_dep,
use_extension, etc.).

Because toolchains_llvm v1.2.0 restricts its module extension to the root
module only, consumer workspaces must COPY the code below into their own
MODULE.bazel.  See docs/integration_guide.md for full instructions and
examples/consumer/MODULE.bazel for a working example.

--- COPY THIS INTO YOUR MODULE.bazel ---

    bazel_dep(name = "toolchains_llvm", version = "1.2.0")

    # Sysroot archive (Bootlin GCC 10.3, glibc 2.34)
    http_archive = use_repo_rule("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
    http_archive(
        name = "clang_sysroot",
        build_file_content = \"\"\"
    package(default_visibility = ["//visibility:public"])
    filegroup(
        name = "sysroot_files",
        srcs = glob(["**/*"]),
    )
    \"\"\",
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

--- END ---
"""
