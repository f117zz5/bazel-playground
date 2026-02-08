import yaml
import requests
import sys
import os

def get_config_path():
    """Locate config.yaml using Bazel runfiles environment variables."""
    # Bazel sets RUNFILES_DIR when running via bazel run
    runfiles_dir = os.getenv('RUNFILES_DIR')
    if runfiles_dir:
        # Try current workspace first
        config_path = os.path.join(runfiles_dir, "my_playground", "config.yaml")
        if os.path.exists(config_path):
            return config_path
        # Try external workspace
        config_path = os.path.join(runfiles_dir, "hermetic_toolchains~", "config.yaml")
        if os.path.exists(config_path):
            return config_path
    
    # Fallback for direct execution (without bazel run)
    # Check relative to script location
    script_dir = os.path.dirname(os.path.abspath(__file__))
    for candidate in ["config.yaml", "../config.yaml", "../../config.yaml"]:
        config_path = os.path.join(script_dir, candidate)
        if os.path.exists(config_path):
            return config_path
    
    return None

def get_latest_release(owner, repo):
    url = f"https://api.github.com/repos/{owner}/{repo}/releases/latest"
    try:
        response = requests.get(url)
        response.raise_for_status()
        data = response.json()
        return data.get("tag_name", "No tag found")
    except requests.exceptions.HTTPError as e:
        if response.status_code == 404:
            return "No release found"
        return f"Error: {e}"
    except Exception as e:
        return f"Error: {e}"

def main():
    config_path = get_config_path()
    
    if not config_path:
        print(f"Error: Could not find config.yaml in runfiles")
        sys.exit(1)

    with open(config_path, "r") as f:
        config = yaml.safe_load(f)

    print(f"{'Repository':<40} | {'Latest Release':<20}")
    print("-" * 63)

    for entry in config.get("repositories", []):
        owner = entry.get("owner")
        repo = entry.get("repo")
        if owner and repo:
            full_name = f"{owner}/{repo}"
            version = get_latest_release(owner, repo)
            print(f"{full_name:<40} | {version:<20}")

if __name__ == "__main__":
    main()