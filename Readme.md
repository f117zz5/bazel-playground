# Tutorial steps

## Setup the bazel project

Create a WORKSPACE file

```shell
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "rules_python",
    sha256 = "497ca47374f48c8b067d786b512ac10a276211810f4a580178ee9b9ad139323a",
    strip_prefix = "rules_python-0.16.1",
    url = "https://github.com/bazelbuild/rules_python/archive/refs/tags/0.16.1.tar.gz",
)

load("@rules_python//python:repositories.bzl", "python_register_toolchains")

python_register_toolchains(
    name = "python3_9",
    python_version = "3.9",
)
```

Run it with

```shell
bazel run :main
```

## References

* YouTube tutorial [here](https://www.youtube.com/watch?v=y9GpV_K17xo)
* Next to watch: third_party tutorial, link [here](https://www.youtube.com/watch?v=bhirT014eCE). Complete playlist [here](https://www.youtube.com/watch?v=y9GpV_K17xo&list=PLDgAeh9AGP98VZoFi39t0jXYqkHzcC01m).
* Another good tutorial [here](https://testdriven.io/blog/bazel-builds/).
