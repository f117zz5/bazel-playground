"""Example Python program using the hermetic Python 3.11 toolchain."""

import sys
import platform


def main():
    print("Hello from hermetic Python!")
    print(f"  Python version : {sys.version}")
    print(f"  Platform       : {platform.platform()}")
    print(f"  Executable     : {sys.executable}")


if __name__ == "__main__":
    main()
