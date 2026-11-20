#!/usr/bin/env python3
"""Generate web/public/data/vendornpcs.json: names and spots of the NPCs that sell recipes (#379).

The site's "where to learn" line names a vendor, its zone and map coordinates. The client's DB2 Creature table has no
names for these NPCs (checked: 0 of the vendor NPCs in CraftWise/Data/RecipeVendors.lua), so they come from Polestar's
bundled data, read from the installed add-ons at generation time only; none of Polestar's files is copied or committed:
  Polestar_QuestDB/Npcs.lua   NPC name and spawn clusters ("id<TAB>'name;map;frame;count;x;y;radius;..."), frame 1 = live
  Polestar_Codex/Zones1.lua   uiMapID -> zone name (client UiMap names)
  Polestar_Codex/Npcs*.lua    NPC names, for an NPC QuestDB has no record of
Only facts are taken (name, zone, map percent x and y), and only for the NPC IDs in RecipeVendors.lua. Where the
source has several spawn clusters for the NPC on its map, no coordinates are written (the zone still is). The licence
notices of both Polestar data folders are carried into the file's "about".

Usage: python3 tools/gen_vendor_npcs.py "<World of Warcraft>/_forever_/Interface/AddOns"
Run it after gen_recipe_vendors.py.
"""

import json
import re
import sys
from pathlib import Path

from gen_thresholds import DATA, ROOT

OUTPUT = ROOT / "web" / "public" / "data" / "vendornpcs.json"
NOTICE = (
    "Names, zones and coordinates are Polestar data (https://github.com/Polestar, GPL-3.0 code; its data notices follow), "
    "read from the installed Polestar_QuestDB and Polestar_Codex add-ons; facts only, nothing copied. Their upstream "
    "sources per LICENSE-DATA.txt: pfQuest (MIT, Copyright (c) 2017-2021 Eric Mauser (Shagu), "
    "https://github.com/shagu/pfQuest, revision 104f35678ca39ab1fb78b655f815cc7016f5e0c8); World of Warcraft Classic Era "
    "and Forever client tables via wago.tools (Blizzard Entertainment game client data, factual names and map geometry "
    "only); QuestieDB (Questie-Forever; no license file, CurseForge lists GPL-3.0, the maintainers ask that it be treated "
    "as all rights reserved, https://github.com/Questie/Questie/issues/4447; facts only, to be removed if they ask); "
    "Polestar recordings (original work, CC BY 4.0). Not verified in game by CraftWise."
)


def vendor_npcs():
    text = (DATA / "RecipeVendors.lua").read_text(encoding="utf-8")
    table = text.split("ns.RecipeVendors = {", 1)[-1].split("\n}", 1)[0]
    return {int(n) for n in re.findall(r"\{ (\d+), \d+(?:, \"\w\")? \}", table)}


def spawn(fields):
    """(zone map ID, x, y or None) of the first live (frame 1) map record in `fields` after the name."""
    i = 1
    while i + 2 < len(fields):
        try:
            map_id, frame, count = int(fields[i]), int(fields[i + 1]), int(fields[i + 2])
        except ValueError:
            return None
        if frame == 1:
            if count == 1 and i + 4 < len(fields):
                return map_id, float(fields[i + 3]), float(fields[i + 4])
            return map_id, None, None
        i += 3 + count * 3
    return None


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    addons = Path(sys.argv[1])
    wanted = vendor_npcs()
    zones = {}
    zone_text = (addons / "Polestar_Codex" / "Zones1.lua").read_text(encoding="utf-8")
    # The pack's strings hold the two characters backslash and n (t), not real line breaks.
    for line in re.search(r'C\.Register\("zone", "(.*?)"[,)]', zone_text, re.S)[1].split("\\n"):
        parts = line.split("\\t")
        if len(parts) >= 3 and parts[0].isdigit():
            zones[int(parts[0])] = parts[2]
    found = {}
    for line in (addons / "Polestar_QuestDB" / "Npcs.lua").read_text(encoding="utf-8").splitlines():
        head, _, rest = line.partition("\t")
        if head.isdigit() and int(head) in wanted and rest.startswith("'"):
            fields = rest[1:].rstrip(";").split(";")
            row = [fields[0]]
            where = spawn(fields)
            if where and where[0] in zones:
                row += [zones[where[0]]] + ([where[1], where[2]] if where[1] is not None else [])
            found[int(head)] = row
    for path in sorted((addons / "Polestar_Codex").glob("Npcs*.lua")):
        for blob in re.findall(r'C\.Register\("npc", "(.*?)"[,)]', path.read_text(encoding="utf-8"), re.S):
            for line in blob.split("\\n"):
                parts = line.split("\\t")
                if len(parts) >= 3 and parts[0].isdigit() and int(parts[0]) in wanted and int(parts[0]) not in found:
                    found[int(parts[0])] = [parts[2]]
    if not found:
        raise SystemExit("No vendor NPCs found; leaving existing output untouched")
    lines = ["{", f'\t"about": {json.dumps("Vendor NPCs of wow.velikopter.com (#379), written by tools/gen_vendor_npcs.py; do not edit. " + NOTICE)},', '\t"npcs": {']
    lines.append(",\n".join(f"\t\t{json.dumps(str(k))}: {json.dumps(found[k], ensure_ascii=False)}" for k in sorted(found)))
    lines += ["\t},", '\t"v": 1', "}"]
    OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"Wrote {OUTPUT.relative_to(ROOT)}: {len(found)}/{len(wanted)} NPCs, {sum(len(r) == 4 for r in found.values())} with coordinates")


if __name__ == "__main__":
    main()
