#include "src/cpp/github_client.h"

#include <iostream>
#include <cpr/cpr.h>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

std::string GetLatestRelease(const std::string& owner, const std::string& repo) {
    std::string url = "https://api.github.com/repos/" + owner + "/" + repo + "/releases/latest";
    
    cpr::Response r = cpr::Get(cpr::Url{url},
                               cpr::Header{{"User-Agent", "bazel-cpp-example"}});

    if (r.status_code == 200) {
        try {
            json data = json::parse(r.text);
            if (data.contains("tag_name")) {
                return data["tag_name"];
            } else {
                return "No tag found";
            }
        } catch (const std::exception& e) {
            return std::string("JSON Parse Error: ") + e.what();
        }
    } else if (r.status_code == 404) {
        return "No release found";
    } else {
        return "Error: " + std::to_string(r.status_code) + " " + r.error.message;
    }
}
