#ifndef SRC_CPP_GITHUB_CLIENT_H_
#define SRC_CPP_GITHUB_CLIENT_H_

#include <string>

// Fetches the latest release tag for a given GitHub repository.
// Returns "No tag found" if no release exists, or an error message on failure.
std::string GetLatestRelease(const std::string& owner, const std::string& repo);

#endif  // SRC_CPP_GITHUB_CLIENT_H_
