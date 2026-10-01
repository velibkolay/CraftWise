#!/usr/bin/env python3
"""Prints the CHANGELOG.md section for a version (release notes), or "Unreleased" if missing."""
import re
import sys
from pathlib import Path

version = sys.argv[1] if len(sys.argv) > 1 else "Unreleased"
text = (Path(__file__).resolve().parent.parent / "CHANGELOG.md").read_text()
sections = re.split(r"(?m)^## ", text)
for wanted in (version, "Unreleased"):
    for s in sections[1:]:
        title, _, body = s.partition("\n")
        if title.strip().lstrip("v").startswith(wanted):
            print(body.strip())
            sys.exit(0)
print(f"CraftWise {version}")
