#!/usr/bin/env python3
"""Generate recipe skill-up thresholds and required skills for one pinned Forever client (stdlib only).

Adapted from SkillUp Forever's tools/gen_thresholds.py (https://github.com/cjber/skillup-forever, commit 593e0e9),
GPL-3.0-or-later, by cjber. CraftWise is GPL-3.0; see LICENSE.

Changes from upstream:
- Writes CraftWise/Data/Thresholds.lua: yellow and grey in ns.Thresholds, MinSkillLineRank above 1 in ns.RequiredSkills.
- Upstream reconciles orange against a Classic Era build and derives green. CraftWise's data policy has no Classic
  datasets, so neither is produced and only this build's own DB2 is read.

Usage: python3 tools/gen_thresholds.py [--refresh | --offline], then gen_recipes.py and gen_vendor.py. Downloads are
cached in tools/.cache/.
"""

import argparse
import sys
import urllib.error
from collections import Counter, defaultdict
from pathlib import Path

from forever_tools import wago

USER_AGENT = "CraftWise-data-gen/1.0"
BUILD = "1.60.1.70938"
# wago.tools lists the live client under this product.
PRODUCT = "wowf"
# Date this source snapshot was selected, not the date of each regeneration.
SOURCE_DATE = "2026-11-14"
UPSTREAM = "https://github.com/cjber/skillup-forever"
# SpellEffect.Effect codes the generators read.
DUMMY = 3
TELEPORT_UNITS = 5
CREATE_ITEM = 24
OPEN_LOCK = 33
LEARN_SPELL = 36
TRANS_DOOR = 50  # summons an object: a campfire
ENCHANT_ITEM = 53  # a permanent enchant
# ItemSparse.Flags_0 bit the client sets on an item it no longer drops or sells ("Deprecated Recipe: ...",
# "Pattern: ... OLD").
ITEM_DEPRECATED = 0x10
ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "tools" / ".cache"
DATA = ROOT / "CraftWise" / "Data"
OUTPUT = DATA / "Thresholds.lua"
REQUIRED_SKILLS = {
    129: "First Aid",
    164: "Blacksmithing",
    165: "Leatherworking",
    171: "Alchemy",
    185: "Cooking",
    186: "Mining",
    197: "Tailoring",
    202: "Engineering",
    333: "Enchanting",
}
# Fishing is category 9 with CanLink=0; unlike racials/riding, it is a profession.
SECONDARY_SKILLS = {356}


def download(url, filename, refresh=False, offline=False):
    data = wago.fetch(url, CACHE / filename, user_agent=USER_AGENT, refresh=refresh, offline=offline)
    return data.decode("utf-8-sig")


def db2(name, columns, refresh=False, offline=False, build=BUILD):
    return wago.db2_rows(name, build, CACHE, user_agent=USER_AGENT, refresh=refresh, offline=offline, required=columns)


def write_lua(path, content):
    """LF on every platform, so a regeneration is byte-stable."""
    path.write_text(content, encoding="utf-8", newline="\n")


def professions(skill_rows):
    """Discover primary professions, linked secondaries, and their child lines."""
    skills = {int(row["ID"]): row for row in skill_rows}
    selected = set(REQUIRED_SKILLS)
    excluded = {}
    for sid, row in skills.items():
        if "[DNT]" in row["DisplayName_lang"] or row["DisplayName_lang"].startswith("Test "):
            excluded[sid] = row["DisplayName_lang"]
        elif (
            int(row["CategoryID"]) == 11
            or sid in SECONDARY_SKILLS
            or (int(row["CategoryID"]) == 9 and row["CanLink"] == "1")
        ):
            selected.add(sid)
    while True:
        children = {
            sid for sid, row in skills.items() if int(row["ParentSkillLineID"]) in selected and sid not in excluded
        }
        if children <= selected:
            break
        selected.update(children)
    return skills, selected, excluded


def spell_effects(rows):
    effects = defaultdict(set)
    for row in rows:
        if int(row["DifficultyID"]) != 0:
            continue
        spell, effect = int(row["SpellID"]), int(row["Effect"])
        effects[spell].add(effect)
    return effects


# Recipes the game no longer lets anyone learn or make, left out of every Data/ file. ItemSparse is partial (about
# 40% of Item rows have no ItemSparse row, the Arcanist set and many live patterns among them), so a missing row
# alone does not mean an item is gone; an item that leaves ItemSparse between pinned builds does. Each entry names
# the build that retired it, and check_retired fails the run if a later build brings back an item that teaches or
# makes it, so it gets reviewed rather than staying hidden.
RETIRED = {
    # Forever 70425 took every Tinkerbox schematic, the Tinkerbox (238737) and the three Tinkerbox kits out of
    # ItemSparse, all of which 70374 had.
    1226206: "Tinkerbox, retired in 1.60.1.70425",
    1226207: "Tinkerbox: Teleport, retired in 1.60.1.70425",
    1226208: "Tinkerbox: Nitro Boosts, retired in 1.60.1.70425",
    1226209: "Tinkerbox: Magnetic Displacement, retired in 1.60.1.70425",
    1226210: "Tinker: Teleport, retired in 1.60.1.70425",
    1226211: "Tinker: Nitro Boosts, retired in 1.60.1.70425",
    1226212: "Tinker: Magnetic Displacement, retired in 1.60.1.70425",
}


def check_retired(retired, spells, effect_rows, sparse_ids, item_effect_rows, effect_link_rows, reagent_rows):
    """Fail when a RETIRED recipe can be learned or made again in this build, or is no longer a recipe in it.

    It can be learned or made when an item that teaches it (directly, or through a LEARN_SPELL teaching spell) is
    in ItemSparse and not deprecated, or the item it makes is, or for a recipe that makes no item, every one of its
    reagents. `sparse_ids` holds the ItemSparse items, deprecated ones left out by the caller.
    """
    gone = sorted(set(retired) - spells)
    if gone:
        raise ValueError(f"RETIRED recipes are no longer in SkillLineAbility; remove them: {gone}")
    learns = defaultdict(set)
    outputs = defaultdict(set)
    for row in effect_rows:
        if int(row["DifficultyID"]) != 0:
            continue
        effect, spell = int(row["Effect"]), int(row["SpellID"])
        if effect == LEARN_SPELL:
            learns[int(row["EffectTriggerSpell"])].add(spell)
        elif effect == CREATE_ITEM and spell in retired and int(row["EffectItemType"]) > 0:
            outputs[spell].add(int(row["EffectItemType"]))
    effects_of = defaultdict(set)
    for row in item_effect_rows:
        effects_of[int(row["SpellID"])].add(int(row["ID"]))
    items_of = defaultdict(set)
    for row in effect_link_rows:
        items_of[int(row["ItemEffectID"])].add(int(row["ItemID"]))
    reagents = {
        int(row["SpellID"]): {int(row[f"Reagent_{i}"] or 0) for i in range(8)} - {0}
        for row in reagent_rows
        if int(row["SpellID"]) in retired
    }
    back = []
    for spell in sorted(retired):
        teachers = {
            item
            for teaching in {spell} | learns.get(spell, set())
            for effect in effects_of.get(teaching, ())
            for item in items_of.get(effect, ())
        }
        made, needs = outputs.get(spell), reagents.get(spell)
        if made:
            craftable = bool(made & sparse_ids)
        else:
            craftable = bool(needs) and needs <= sparse_ids
        if teachers & sparse_ids or craftable:
            back.append(f"{spell} ({retired[spell]})")
    if back:
        raise ValueError(f"RETIRED recipes can be learned or made again; review and remove them: {', '.join(back)}")


def generate(ability_rows, skills, selected, names, effects, retired=None):
    """[spell] = (yellow, grey, required skill), straight from SkillLineAbility; prints coverage per profession."""
    retired = retired or set()
    stats = {sid: Counter() for sid in selected}
    candidates = defaultdict(list)
    for row in ability_rows:
        sid = int(row["SkillLine"])
        if sid not in selected:
            continue
        counts = stats[sid]
        counts["rows"] += 1
        try:
            spell = int(row["Spell"])
            required = int(row["MinSkillLineRank"])
            yellow = int(row["TrivialSkillLineRankLow"])
            grey = int(row["TrivialSkillLineRankHigh"])
            if spell <= 0 or min(required, yellow, grey) < 0:
                raise ValueError
        except (ValueError, TypeError):
            counts["skip:missing/invalid data"] += 1
            continue
        if grey <= yellow:
            counts["skip:grey<=yellow"] += 1
            continue
        # Mining's open-lock gathering abilities have thresholds but are not
        # crafting recipes. Do not emit them as smelting recipes.
        if effects.get(spell) == {OPEN_LOCK}:
            counts["skip:gathering ability"] += 1
            continue
        if spell in retired:
            counts["skip:retired"] += 1
            continue
        candidates[spell].append((sid, (yellow, grey, required)))

    emitted = {}
    for spell, rows in sorted(candidates.items()):
        if len({t for _, t in rows}) != 1:
            for sid, _ in rows:
                stats[sid]["skip:conflicting recipe rows"] += 1
            continue
        seen = set()
        for sid, _ in sorted(rows):
            if sid in seen:
                stats[sid]["skip:duplicate recipe row"] += 1
                continue
            seen.add(sid)
            stats[sid]["emitted"] += 1
            if not names.get(spell):
                stats[sid]["missing spell name"] += 1
        emitted[spell] = rows[0][1]

    for sid in sorted(selected):
        counts = stats[sid]
        name = skills[sid]["DisplayName_lang"] if sid in skills else REQUIRED_SKILLS[sid]
        skipped = sum(value for key, value in counts.items() if key.startswith("skip:"))
        reasons = ", ".join(f"{key[5:]}={value}" for key, value in sorted(counts.items()) if key.startswith("skip:"))
        line = f"{name} ({sid}): {counts['emitted']} emitted / {skipped} skipped"
        if reasons:
            line += f" ({reasons})"
        if not counts["rows"]:
            line += "; no SkillLineAbility rows"
        if sid not in skills:
            line += "; MISSING SkillLine"
        print(line)
        if counts["missing spell name"]:
            print(f"  Missing SpellName: {counts['missing spell name']} (comments only)")
    return emitted


def render(emitted):
    lines = [
        "-- Generated by tools/gen_thresholds.py; do not edit.",
        "-- Yellow and grey skill-up thresholds and the required skill, per recipe spell ID (issues #15, #23).",
        "-- Source: Forever client DB2 SkillLineAbility (TrivialSkillLineRankLow = yellow, TrivialSkillLineRankHigh = grey,",
        f"-- MinSkillLineRank = required skill), {PRODUCT} {BUILD}, {SOURCE_DATE}, via wago.tools,",
        f"-- https://wago.tools/db2/SkillLineAbility/csv?build={BUILD}. Generator adapted from SkillUp Forever's",
        f"-- tools/gen_thresholds.py ({UPSTREAM}, GPL-3.0-or-later).",
        "-- Orange and green are left out: upstream reconciles orange against Classic data and green is derived,",
        "-- neither is this client's data.",
        "-- Recipes with grey <= yellow in DB2 are absent (unknown). Recipes the game retired (RETIRED in the generator)",
        "-- are left out.",
        "local _, ns = ...",
        "-- stylua: ignore",
        "ns.Thresholds = {",
    ]
    for spell, (yellow, grey, _) in sorted(emitted.items()):
        lines.append(f"\t[{spell}] = {{ {yellow}, {grey} }},")
    lines.extend(
        [
            "}",
            "",
            "-- RequiredSkills: the raw client MinSkillLineRank where it is above 1. Nearly every recipe has the",
            "-- client's placeholder 1, so those are left out: absent means the client gives no requirement, not that",
            "-- the recipe is learnable at 1. A value can sit above yellow or be left over from before Forever moved",
            "-- a recipe's range, so it is what the client says, not a verified learn requirement.",
            "-- stylua: ignore",
            "ns.RequiredSkills = {",
        ]
    )
    for spell, (_, _, required) in sorted(emitted.items()):
        if required > 1:
            lines.append(f"\t[{spell}] = {required},")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--refresh", action="store_true", help="redownload the pinned sources")
    mode.add_argument("--offline", action="store_true", help="use cached sources only")
    args = parser.parse_args()
    options = {"refresh": args.refresh, "offline": args.offline}
    ability_rows = db2(
        "SkillLineAbility",
        (
            "Spell",
            "SkillLine",
            "MinSkillLineRank",
            "TrivialSkillLineRankHigh",
            "TrivialSkillLineRankLow",
        ),
        **options,
    )
    skill_rows = db2(
        "SkillLine",
        (
            "ID",
            "DisplayName_lang",
            "CategoryID",
            "CanLink",
            "ParentSkillLineID",
        ),
        **options,
    )
    name_rows = db2("SpellName", ("ID", "Name_lang"), **options)
    effect_rows = db2(
        "SpellEffect",
        ("SpellID", "Effect", "DifficultyID", "EffectItemType", "EffectTriggerSpell"),
        **options,
    )
    spells = {int(row["Spell"]) for row in ability_rows}
    sparse_rows = db2("ItemSparse", ("ID", "Flags_0"), **options)
    check_retired(
        RETIRED,
        spells,
        effect_rows,
        {int(row["ID"]) for row in sparse_rows if not int(row.get("Flags_0") or 0) & ITEM_DEPRECATED},
        db2("ItemEffect", ("ID", "SpellID"), **options),
        db2("ItemXItemEffect", ("ItemID", "ItemEffectID"), **options),
        db2("SpellReagents", ("SpellID", *(f"Reagent_{i}" for i in range(8))), **options),
    )
    skills, selected, excluded = professions(skill_rows)
    names = {int(row["ID"]): row["Name_lang"] for row in name_rows}
    emitted = generate(ability_rows, skills, selected, names, spell_effects(effect_rows), set(RETIRED))
    if not emitted:
        raise ValueError("No usable recipes; leaving existing generated output untouched")
    for sid, name in sorted(excluded.items()):
        print(f"Excluded test skill line: {name} ({sid})")
    missing = [str(sid) for sid in sorted(REQUIRED_SKILLS) if sid not in skills]
    print("Missing required skill lines: " + (", ".join(missing) or "none"))
    write_lua(OUTPUT, render(emitted))
    print(f"Wrote {len(emitted)} unique recipe spell IDs to {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, urllib.error.URLError) as error:
        sys.exit(f"error: {error}")
