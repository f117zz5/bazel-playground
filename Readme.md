# Tutorial steps

This is my personal bazel playground heavily inspired by this [Bazel Examples](https://github.com/bazelbuild/examples) and the tutorials listed under the Reference section.

## About this Python application

It is just a very simple python application, loading few modules and printing few strings. The purpose of this repository is to configure the Python environment and execution with Bazel. Run it with

```shell
bazel run :main
```

## generate the `requirements.txt` file

In order to generate the requirements.txt `pip-tools` tools shall be needed, if needed install them with:

```shell
pip install pip-tools
```

Define the python modules needed in `requirements.in` and let `pip-tools` generate the `requirements.txt` file:

```shell
pip-compile --resolver=backtracking requirements.in
```

## Investigating dependencies

Good starting point is the Bazel Documentation (here)[https://bazel.build/query/guide].

## References

* YouTube tutorial [here](https://www.youtube.com/watch?v=y9GpV_K17xo)
* Next to watch: third_party tutorial, link [here](https://www.youtube.com/watch?v=bhirT014eCE). Complete playlist [here](https://www.youtube.com/watch?v=y9GpV_K17xo&list=PLDgAeh9AGP98VZoFi39t0jXYqkHzcC01m).
* Another good tutorial [here](https://testdriven.io/blog/bazel-builds/).
