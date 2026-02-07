#include <iostream>
#include <fstream>
#include <iomanip>
#include <filesystem>
#include "yaml-cpp/yaml.h"
#include "src/cpp/github_client.h"

namespace fs = std::filesystem;

int main() {
    std::string config_path = "config.yaml";
    
    // Simple check for config file existence in common locations
    if (!fs::exists(config_path)) {
        if (fs::exists("../config.yaml")) {
             config_path = "../config.yaml";
        } else {
            std::cerr << "Error: Could not find config.yaml" << std::endl;
            return 1;
        }
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
