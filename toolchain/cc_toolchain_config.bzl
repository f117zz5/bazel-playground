load("@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl", "tool_path", "feature", "flag_group", "flag_set")

# All C/C++ compile action names
_ALL_COMPILE_ACTIONS = [
    "c-compile",
    "c++-compile",
    "c++-header-parsing",
    "c++-module-compile",
    "assemble",
    "preprocess-assemble",
]

_ALL_LINK_ACTIONS = [
    "c++-link-executable",
    "c++-link-dynamic-library",
    "c++-link-nodeps-dynamic-library",
]

def _impl(ctx):
    toolchain_identifier = "x86_64-toolchain"
    host_system_name = "local"
    target_system_name = "local"
    target_cpu = "k8"
    target_libc = "glibc"
    compiler = "gcc"
    abi_version = "unknown"
    abi_libc_version = "unknown"

    # Prefix for the binaries in the downloaded tarball
    prefix = "bin/x86_64-buildroot-linux-gnu-"

    tool_paths = [
        tool_path(name = "gcc", path = prefix + "gcc"),
        tool_path(name = "ld", path = prefix + "ld"),
        tool_path(name = "ar", path = prefix + "ar"),
        tool_path(name = "cpp", path = prefix + "cpp"),
        tool_path(name = "gcov", path = prefix + "gcov"),
        tool_path(name = "nm", path = prefix + "nm"),
        tool_path(name = "objdump", path = prefix + "objdump"),
        tool_path(name = "strip", path = prefix + "strip"),
    ]

    # The sysroot inside the downloaded toolchain tarball
    sysroot_subdir = "x86_64-buildroot-linux-gnu/sysroot"

    # The absolute path prefix for the toolchain repository, resolved at
    # repository-fetch time by the gcc_toolchain_config repository rule.
    # GCC resolves its built-in include paths to absolute filesystem paths,
    # so cxx_builtin_include_directories must also use absolute paths.
    toolchain_path_prefix = ctx.attr.toolchain_path_prefix

    # Sysroot: use the absolute path for both compiler flags and builtin_sysroot.
    # This ensures consistency when GCC resolves paths.
    sysroot = toolchain_path_prefix + "/" + sysroot_subdir

    # Bin directory: -B flag tells GCC where to find its internal tools (ld, as, etc.)
    # This is needed because -no-canonical-prefixes prevents GCC from resolving
    # its own installation prefix, so collect2 cannot find 'ld' otherwise.
    bin_dir = toolchain_path_prefix + "/bin"

    # The libexec directory contains collect2/lto-wrapper; -B also helps there.
    libexec_gcc_dir = toolchain_path_prefix + "/libexec/gcc/x86_64-buildroot-linux-gnu/12.3.0"

    # The cross-tools directory (contains the prefixed ld that collect2 needs)
    cross_bin_dir = toolchain_path_prefix + "/x86_64-buildroot-linux-gnu/bin"

    # Built-in include directories — MUST use absolute paths to match what
    # GCC reports during compilation. GCC always resolves its own built-in
    # include directories to absolute paths regardless of -no-canonical-prefixes
    # (that flag only affects paths derived from the input file, not built-in dirs).
    cxx_builtin_include_directories = [
        toolchain_path_prefix + "/" + sysroot_subdir + "/usr/include",
        toolchain_path_prefix + "/include/c++/12.3.0",
        toolchain_path_prefix + "/include/c++/12.3.0/x86_64-buildroot-linux-gnu",
        toolchain_path_prefix + "/lib/gcc/x86_64-buildroot-linux-gnu/12.3.0/include",
        toolchain_path_prefix + "/lib/gcc/x86_64-buildroot-linux-gnu/12.3.0/include-fixed",
        toolchain_path_prefix + "/x86_64-buildroot-linux-gnu/include/c++/12.3.0",
        toolchain_path_prefix + "/x86_64-buildroot-linux-gnu/include/c++/12.3.0/x86_64-buildroot-linux-gnu",
    ]

    features = [
        feature(
            name = "default_compile_flags",
            enabled = True,
            flag_sets = [
                flag_set(
                    actions = _ALL_COMPILE_ACTIONS,
                    flag_groups = [
                        flag_group(
                            flags = [
                                "-no-canonical-prefixes",
                                "--sysroot=" + sysroot,
                                "-B" + bin_dir,
                                "-B" + cross_bin_dir,
                            ],
                        ),
                    ],
                ),
            ],
        ),
        feature(
            name = "default_linker_flags",
            enabled = True,
            flag_sets = [
                flag_set(
                    actions = _ALL_LINK_ACTIONS,
                    flag_groups = [
                        flag_group(
                            flags = [
                                "-no-canonical-prefixes",
                                "--sysroot=" + sysroot,
                                "-B" + bin_dir,
                                "-B" + cross_bin_dir,
                                "-lstdc++",
                                "-lm",
                            ],
                        ),
                    ],
                ),
            ],
        ),
    ]

    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        features = features,
        toolchain_identifier = toolchain_identifier,
        host_system_name = host_system_name,
        target_system_name = target_system_name,
        target_cpu = target_cpu,
        target_libc = target_libc,
        compiler = compiler,
        abi_version = abi_version,
        abi_libc_version = abi_libc_version,
        tool_paths = tool_paths,
        cxx_builtin_include_directories = cxx_builtin_include_directories,
        builtin_sysroot = sysroot,
    )

cc_toolchain_config = rule(
    implementation = _impl,
    attrs = {
        "toolchain_path_prefix": attr.string(mandatory = True),
    },
    provides = [CcToolchainConfigInfo],
)
