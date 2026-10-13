# ----------------------------------------------------------------------------
# Project : Firefox Network Log Recorder
# Author  : AMiran Kimadze (itsarmen)
# GitHub  : https://github.com/itsarmen
# Email   : amoswaper@gmail.com
# Web     : https://xrow.asia
# ----------------------------------------------------------------------------

"""Package the Firefox extension into a distributable .xpi (just a zip).

Usage (from repo root or extension/):
    python extension/build.py
    python extension/build.py --output dist

Output: extension/dist/network-log-recorder-<version>.xpi
Upload the .xpi to addons.mozilla.org for signing, or install unsigned via
about:config + xpinstall.signatures.required = false (dev only).
"""

from __future__ import annotations

import argparse
import json
import sys
import zipfile
from pathlib import Path

EXT_DIR = Path(__file__).resolve().parent

# Files shipped inside the .xpi (never the build script or its output).
PACKAGE_FILES = [
    "manifest.json",
    "background.js",
    "popup.html",
    "popup.css",
    "popup.js",
]


def load_manifest() -> dict:
    try:
        return json.loads((EXT_DIR / "manifest.json").read_text("utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        raise SystemExit(f"ERROR: bad manifest.json: {e}")


def collect_files(manifest: dict) -> list[Path]:
    paths = [EXT_DIR / f for f in PACKAGE_FILES]
    for group in ("icons",):
        icons = manifest.get(group)
        if isinstance(icons, dict):
            paths += [EXT_DIR / p for p in icons.values()]
        browser_action = manifest.get("browser_action", {})
        if isinstance(browser_action, dict):
            for p in browser_action.get("default_icon", {}).values():
                paths.append(EXT_DIR / p)
    seen, unique = set(), []
    for p in paths:
        if p not in seen:
            seen.add(p)
            unique.append(p)
    missing = [str(p) for p in unique if not p.is_file()]
    if missing:
        raise SystemExit("ERROR: files referenced but missing:\n  "
                         + "\n  ".join(missing))
    return unique


def main() -> int:
    ap = argparse.ArgumentParser(description="Package the extension (.xpi).")
    ap.add_argument("--output", default="dist",
                    help="output dir inside extension/ (default: dist)")
    args = ap.parse_args()

    manifest = load_manifest()
    version = manifest.get("version", "0.0.0")
    files = collect_files(manifest)

    out_dir = EXT_DIR / args.output
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"network-log-recorder-{version}.xpi"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for p in files:
            z.write(p, p.relative_to(EXT_DIR).as_posix())
    size_kb = out.stat().st_size // 1024
    print(f"Built {out} ({size_kb} KB):")
    for p in files:
        print(f"  {p.relative_to(EXT_DIR).as_posix()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
