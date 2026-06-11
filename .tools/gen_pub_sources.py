#!/usr/bin/env python3
"""
Generates flatpak manifest sources for all hosted pub packages in pubspec.lock.

Usage:
    pip install pyyaml          # one-time
    cd /path/to/absorb
    python3 .tools/gen_pub_sources.py > packaging/pub-sources.yml

Then paste the contents of pub-sources.yml into the sources: block of the
absorb module in packaging/io.github.rafa.absorb.yml (keep the existing
`type: dir` entry — add these after it).

Re-run whenever pubspec.lock changes.
"""

import hashlib
import sys
import urllib.request
import concurrent.futures

try:
    import yaml
except ImportError:
    sys.exit("pyyaml not found — run: pip install pyyaml")

ARCHIVE_URL = "https://storage.googleapis.com/pub-packages/packages/{name}-{version}.tar.gz"
WORKERS = 20


def fetch(name: str, version: str) -> dict:
    url = ARCHIVE_URL.format(name=name, version=version)
    req = urllib.request.Request(url, headers={"User-Agent": "gen-pub-sources/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = resp.read()
    return {
        "type": "archive",
        "url": url,
        "sha256": hashlib.sha256(data).hexdigest(),
        "dest": f"pub-cache/hosted/pub.dev/{name}-{version}",
        "strip-components": 1,
    }


def main() -> None:
    lockfile = sys.argv[1] if len(sys.argv) > 1 else "pubspec.lock"

    with open(lockfile) as f:
        lock = yaml.safe_load(f)

    hosted = [
        (name, pkg["version"])
        for name, pkg in lock["packages"].items()
        if pkg.get("source") == "hosted"
    ]

    print(f"Fetching {len(hosted)} packages...", file=sys.stderr)

    sources, errors = [], []
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futures = {pool.submit(fetch, n, v): (n, v) for n, v in hosted}
        for i, future in enumerate(concurrent.futures.as_completed(futures), 1):
            name, version = futures[future]
            try:
                sources.append(future.result())
                print(f"  [{i}/{len(hosted)}] {name}-{version}", file=sys.stderr)
            except (urllib.error.URLError, OSError) as exc:
                errors.append((name, version, exc))
                print(f"  [{i}/{len(hosted)}] FAIL {name}-{version}: {exc}", file=sys.stderr)

    if errors:
        sys.exit(f"\n{len(errors)} package(s) failed — fix errors above and retry.")

    sources.sort(key=lambda s: s["dest"])
    print(yaml.dump(sources, default_flow_style=False, allow_unicode=True, sort_keys=False))
    print(f"\nDone. {len(sources)} sources written.", file=sys.stderr)


if __name__ == "__main__":
    main()
