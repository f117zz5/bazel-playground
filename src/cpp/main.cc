#include <iostream>
#include <fstream>
#include <iomanip>
#include <filesystem>
#include "yaml-cpp/yaml.h"
#include "src/cpp/github_client.h"
#include "tools/cpp/runfiles/runfiles.h"

using bazel::tools::cpp::runfiles::Runfiles;
namespace fs = std::filesystem;

int main(int argc, char** argv) {
    // Initialize Bazel runfiles
    std::string error;
    std::unique_ptr<Runfiles> runfiles(Runfiles::Create(argv[0], &error));
    if (!runfiles) {
        std::cerr << "Error initializing runfiles: " << error << std::endl;
        return 1;
    }
    
    // Try to locate config.yaml in current workspace
    std::string config_path = runfiles->Rlocation("my_playground/config.yaml");
    
    // If not found, try in parent workspace (if running as external dependency)
    if (!fs::exists(config_path)) {
        config_path = runfiles->Rlocation("hermetic_toolchains~/config.yaml");
    }
    
    if (!fs::exists(config_path)) {
        std::cerr << "Error: Could not find config.yaml in runfiles" << std::endl;
        return 1;
    }

    try {
        YAML::Node config = YAML::LoadFile(config_path);

        std::cout << std::left << std::setw(40) << "Repository" 
                  << " | " << std::setw(20) << "Latest Release" << std::endl;
        std::cout << std::string(63, '-') << std::endl;

        if (config["repositories"]) {
            for (const auto& node : config["repositories"]) {
                std::string owner = node["owner"].as<std::string>();
                std::string repo = node["repo"].as<std::string>();
                
                std::string full_name = owner + "/" + repo;
                std::string version = GetLatestRelease(owner, repo);
                
                std::cout << std::left << std::setw(40) << full_name 
                          << " | " << std::setw(20) << version << std::endl;
            }
        }
    } catch (const std::exception& e) {
        std::cerr << "Error reading config or executing: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
