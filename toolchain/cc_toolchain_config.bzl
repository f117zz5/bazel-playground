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
    toolchain_path_prefix = ctx.attr.toolchain_path_prefix
    gcc_version = ctx.attr.gcc_version
    binary_prefix = ctx.attr.binary_prefix
    toolchain_identifier = ctx.attr.toolchain_identifier

    host_system_name = "local"
    target_system_name = "local"
    target_cpu = "k8"
    target_libc = "glibc"
    compiler = "gcc"
    abi_version = "unknown"
    abi_libc_version = "unknown"

    # Prefix for the binaries in the downloaded tarball
    prefix = "bin/" + binary_prefix

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

    # The sysroot inside the downloaded toolchain tarball.
    # Derive the target triple from the binary_prefix (strip trailing dash).
    target_triple = binary_prefix.rstrip("-")
    sysroot_subdir = target_triple + "/sysroot"

    # Sysroot: use the absolute path for both compiler flags and builtin_sysroot.
    # This ensures consistency when GCC resolves paths.
    sysroot = toolchain_path_prefix + "/" + sysroot_subdir

    # Bin directory: -B flag tells GCC where to find its internal tools (ld, as, etc.)
    # This is needed because -no-canonical-prefixes prevents GCC from resolving
    # its own installation prefix, so collect2 cannot find 'ld' otherwise.
    bin_dir = toolchain_path_prefix + "/bin"

    # The libexec directory contains collect2/lto-wrapper; -B also helps there.
    libexec_gcc_dir = toolchain_path_prefix + "/libexec/gcc/" + target_triple + "/" + gcc_version

    # The cross-tools directory (contains the prefixed ld that collect2 needs)
    cross_bin_dir = toolchain_path_prefix + "/" + target_triple + "/bin"

    # Built-in include directories — MUST use absolute paths to match what
    # GCC reports during compilation. GCC always resolves its own built-in
    # include directories to absolute paths regardless of -no-canonical-prefixes
    # (that flag only affects paths derived from the input file, not built-in dirs).
    cxx_builtin_include_directories = [
        toolchain_path_prefix + "/" + sysroot_subdir + "/usr/include",
        toolchain_path_prefix + "/include/c++/" + gcc_version,
        toolchain_path_prefix + "/include/c++/" + gcc_version + "/" + target_triple,
        toolchain_path_prefix + "/lib/gcc/" + target_triple + "/" + gcc_version + "/include",
        toolchain_path_prefix + "/lib/gcc/" + target_triple + "/" + gcc_version + "/include-fixed",
        toolchain_path_prefix + "/" + target_triple + "/include/c++/" + gcc_version,
        toolchain_path_prefix + "/" + target_triple + "/include/c++/" + gcc_version + "/" + target_triple,
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
        "gcc_version": attr.string(mandatory = True),
        "binary_prefix": attr.string(mandatory = True),
        "toolchain_identifier": attr.string(default = "x86_64-toolchain"),
    },
    provides = [CcToolchainConfigInfo],
)
