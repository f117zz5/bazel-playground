# Tutorial steps

This is my personal bazel playground heavily inspired by this [Bazel Examples](https://github.com/bazelbuild/examples) and the tutorials listed under the Reference section.

## About this Python application

It is just a very simple python application, loading few modules and printing few strings. The purpose of this repository is to configure the Python environment and execution with Bazel. Run it with

```shell
bazel run :main
```

## generate the `requirements_lock.txt` file

In order to generate the requirements_lock.txt add the following code to the BUILD file on top level:

```python
load("@rules_python//python:pip.bzl", "compile_pip_requirements")

compile_pip_requirements(
    name = "requirements",
    extra_args = ["--allow-unsafe"],
    requirements_in = "requirements.in",
    requirements_txt = "requirements_lock.txt",
)
```

This will add new runnable bazel targets:

```shell
bazelisk query //...
Starting local Bazel server and connecting to it...
//:requirements
//:requirements.update
//:requirements_test
//src:main
Loading: 9 packages loaded
```

Create an empty `requirements_lock.txt` file:

```shell
touch requirements_lock.txt
```

Define the python modules needed in `requirements.in` and run `//:requirements.update` to generate the `requirements_lock.txt` file:

```shell
bazelisk run //:requirements.update
```

## Investigating dependencies

Good starting point is the Bazel Documentation [here](https://bazel.build/query/guide).

The `bazel sync` seems to be interesting when it comes up to resolving dependencies, here a [Bazel Blog article on sync][1].

```shell
bazelisk sync --only=rules_python --experimental_repository_resolved_file=resolved.bzl
```

## Tutorials

* YouTube tutorial [here](https://www.youtube.com/watch?v=y9GpV_K17xo)
* Next to watch: third_party tutorial, link [here](https://www.youtube.com/watch?v=bhirT014eCE). Complete playlist [here](https://www.youtube.com/watch?v=y9GpV_K17xo&list=PLDgAeh9AGP98VZoFi39t0jXYqkHzcC01m).
* Another good tutorial [here](https://testdriven.io/blog/bazel-builds/).

## References

* [Bazel Blog article on sync][1]

[1]: https://blog.bazel.build/2018/07/09/bazel-sync-and-resolved-file.html
