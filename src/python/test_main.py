import pytest
from unittest.mock import patch, MagicMock
from src.python.main import get_latest_release

def test_get_latest_release_success():
    with patch('requests.get') as mock_get:
        # Setup mock response
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"tag_name": "v1.2.3"}
        mock_get.return_value = mock_response

        version = get_latest_release("owner", "repo")
        assert version == "v1.2.3"

def test_get_latest_release_404():
    import requests
    with patch('requests.get') as mock_get:
        mock_response = MagicMock()
        mock_response.status_code = 404
        # Mocking the exception that requests would raise
        mock_response.raise_for_status.side_effect = requests.exceptions.HTTPError("404 Client Error")
        mock_get.return_value = mock_response

        version = get_latest_release("owner", "repo")
        assert version == "No release found"

if __name__ == "__main__":
    import sys
    import pytest
    # Run pytest and exit with its return code
    sys.exit(pytest.main(sys.argv))
