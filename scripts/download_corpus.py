#!/usr/bin/env python3
"""Download benchmark corpus files."""
import os
import urllib.request

CORPUS_DIR = "tests/fixtures/corpus"
FILES = {
    "twitter.json": "https://raw.githubusercontent.com/simdjson/simdjson/master/jsonexamples/twitter.json",
    "canada.json": "https://raw.githubusercontent.com/miloyip/nativejson-benchmark/master/data/canada.json",
}


def main():
    os.makedirs(CORPUS_DIR, exist_ok=True)
    for name, url in FILES.items():
        path = os.path.join(CORPUS_DIR, name)
        if os.path.exists(path):
            print(f"  SKIP {name} (already exists)")
            continue
        print(f"  DOWNLOAD {name}...")
        urllib.request.urlretrieve(url, path)
        size = os.path.getsize(path)
        print(f"  OK {name} ({size:,} bytes)")


if __name__ == "__main__":
    main()
