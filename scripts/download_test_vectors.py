#!/usr/bin/env python3
"""Download Seriot JSONTestSuite test vectors."""
import os
import urllib.request
import json

VECTORS_DIR = "tests/fixtures/test_vectors"
BASE_URL = "https://raw.githubusercontent.com/nst/JSONTestSuite/master/test_parsing"
INDEX_URL = "https://api.github.com/repos/nst/JSONTestSuite/contents/test_parsing"


def main():
    os.makedirs(VECTORS_DIR, exist_ok=True)
    print("Fetching file list from GitHub API...")
    req = urllib.request.Request(INDEX_URL)
    req.add_header("Accept", "application/vnd.github.v3+json")
    with urllib.request.urlopen(req) as resp:
        files = json.loads(resp.read())

    count = 0
    for entry in files:
        name = entry["name"]
        if not name.endswith(".json"):
            continue
        if not (name.startswith("y_") or name.startswith("n_")):
            continue
        path = os.path.join(VECTORS_DIR, name)
        if os.path.exists(path):
            continue
        url = entry["download_url"]
        urllib.request.urlretrieve(url, path)
        count += 1

    total = len([f for f in os.listdir(VECTORS_DIR) if f.endswith(".json")])
    print(f"Downloaded {count} new files. Total: {total} vectors.")


if __name__ == "__main__":
    main()
