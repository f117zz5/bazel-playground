#include <iostream>

int main() {
    std::cout << "Hello from hermetic C++ toolchain!" << std::endl;
#if defined(__clang__)
    std::cout << "  Compiler: Clang " << __clang_major__ << "." << __clang_minor__ << std::endl;
#elif defined(__GNUC__)
    std::cout << "  Compiler: GCC " << __GNUC__ << "." << __GNUC_MINOR__ << std::endl;
#endif
    return 0;
}
