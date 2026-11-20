#!/usr/bin/env python3
"""Generate web/public/data/itemnames.json: item names for the site's crafting data (#379).

The site showed "Item 8385" for a recipe item no AH scan had named. This writes the client's own name for every item
in web/public/data/recipes.json (recipe items, products, reagents) from this build's DB2 ItemSparse (Display_lang) via
wago.tools, the same pinned client as the other Data/ files. Items ItemSparse has no row for are left out: the site
then shows what it did before (an AH name, the recipe's name, else "Item <id>"). Names from AH uploads still win.

Usage: python3 tools/gen_item_names.py [--refresh | --offline]
Run it after tools/gen_site_recipes.lua (it reads the item IDs from recipes.json). Downloads are cached in tools/.cache/.
"""

import argparse
import json
import sys
import urllib.error

from gen_thresholds import BUILD, PRODUCT, ROOT, SOURCE_DATE, db2

RECIPES = ROOT / "web" / "public" / "data" / "recipes.json"
OUTPUT = ROOT / "web" / "public" / "data" / "itemnames.json"


def item_ids(recipes):
    """Every item ID recipes.json mentions: recipe items, products, reagents."""
    ids = {int(i) for i in recipes["teach"]}
    for row in recipes["spells"].values():
        if row[1]:
            ids.add(row[1])
        ids.update(row[3::2])
    return ids


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--refresh", action="store_true", help="redownload the pinned sources")
    mode.add_argument("--offline", action="store_true", help="use cached sources only")
    args = parser.parse_args()
    recipes = json.loads(RECIPES.read_text(encoding="utf-8"))
    wanted = item_ids(recipes)
    rows = db2("ItemSparse", ("ID", "Display_lang"), refresh=args.refresh, offline=args.offline)
    names = {int(r["ID"]): r["Display_lang"] for r in rows if r["Display_lang"] and int(r["ID"]) in wanted}
    if not names:
        raise ValueError("No item names found; leaving existing generated output untouched")
    out = {
        "about": "Item names of wow.velikopter.com's crafting data (#379), written by tools/gen_item_names.py; do not edit. "
        f"Source: Forever client DB2 ItemSparse Display_lang, {PRODUCT} {BUILD}, {SOURCE_DATE}, via wago.tools, "
        f"https://wago.tools/db2/ItemSparse/csv?build={BUILD}. Only items in recipes.json; items the table has no row for "
        "are absent. Licence: GPL-3.0 (CraftWise).",
        "v": 1,
        "names": {str(k): names[k] for k in sorted(names)},
    }
    lines = ["{", f'\t"about": {json.dumps(out["about"], ensure_ascii=False)},', '\t"names": {']
    lines += [",\n".join(f"\t\t{json.dumps(k)}: {json.dumps(v, ensure_ascii=False)}" for k, v in out["names"].items())]
    lines += ["\t},", '\t"v": 1', "}"]
    OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"Wrote {OUTPUT.relative_to(ROOT)}: {len(names)}/{len(wanted)} item names")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, urllib.error.URLError) as error:
        sys.exit(f"error: {error}")
