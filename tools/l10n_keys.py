#!/usr/bin/env python3
"""Lists every L["..."] key used in CraftWise (the English texts to translate, issue #13).

Usage: python3 tools/l10n_keys.py [locale]   -> a Locales/<locale>.lua template on stdout
"""
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent / "CraftWise"
keys = set()
for path in root.rglob("*.lua"):
    if "Locales" in path.parts or "Data" in path.parts:
        continue
    keys.update(re.findall(r'L\["((?:[^"\\]|\\.)*)"\]', path.read_text()))
locale = sys.argv[1] if len(sys.argv) > 1 else "deDE"
print(f'if GetLocale() ~= "{locale}" then\n\treturn\nend\nlocal L = select(2, ...).L\n')
for k in sorted(keys):
    print(f'L["{k}"] = "{k}"')
