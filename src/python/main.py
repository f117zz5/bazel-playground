import yaml
import requests
import sys
import os

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
    config_path = "config.yaml"
    
    if not os.path.exists(config_path):
        config_path = "../config.yaml"

    if not os.path.exists(config_path):
        print(f"Error: Could not find {config_path}")
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