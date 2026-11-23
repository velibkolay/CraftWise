#!/usr/bin/env python3
"""Generate bundled recipe facts for the pinned Forever client (stdlib only).

Adapted from SkillUp Forever's tools/gen_recipes.py (https://github.com/cjber/skillup-forever, commit 593e0e9),
GPL-3.0-or-later, by cjber. CraftWise is GPL-3.0; see LICENSE. Changes from upstream: output path and header, reads
CraftWise's two-value Thresholds.lua, and writes only the tables CraftWise uses (upstream's RecipeScrolls, RankBooks
and ItemGear are left out).

Usage: python3 tools/gen_recipes.py [--refresh | --offline], after gen_thresholds.py.
"""

import argparse
import math
import re
import sys
import urllib.error
from collections import Counter, defaultdict

from gen_thresholds import (
    BUILD,
    CREATE_ITEM,
    DATA,
    DUMMY,
    ENCHANT_ITEM,
    PRODUCT,
    ROOT,
    SOURCE_DATE,
    TELEPORT_UNITS,
    TRANS_DOOR,
    db2,
    professions,
    write_lua,
)

OUTPUT = DATA / "Recipes.lua"
THRESHOLDS = DATA / "Thresholds.lua"
THRESHOLD_ROW = re.compile(r"\s*\[(\d+)\] = \{ \d+, \d+ \},")
YIELD_MODIFIERS = (
    "EffectRealPointsPerLevel",
    "EffectPointsPerResource",
    "Coefficient",
    "ResourceCoefficient",
    "ScalingClass",
    "EffectTriggerSpell",
)


def threshold_ids():
    content = THRESHOLDS.read_text(encoding="utf-8")
    if f"{PRODUCT} {BUILD}," not in content:
        raise ValueError("Thresholds.lua build differs; run gen_thresholds.py first")
    table = content.split("ns.Thresholds = {", 1)[-1].split("\n}", 1)[0]
    ids = set()
    for line in table.splitlines():
        if not line.lstrip().startswith("["):
            continue
        match = THRESHOLD_ROW.fullmatch(line)
        if not match or int(match[1]) in ids:
            raise ValueError(f"Invalid/duplicate Thresholds.lua row: {line}")
        ids.add(int(match[1]))
    if not ids:
        raise ValueError("No recipe IDs in Thresholds.lua")
    return ids


def put_unique(table, key, value, label):
    if key in table and table[key] != value:
        raise ValueError(f"Conflicting {label} for {key}: {table[key]!r} / {value!r}")
    table[key] = value


# Every profession each recipe belongs to. A few recipes are taught by two
# professions; they keep a trainer-name mapping in each but no RecipeData row,
# since the runtime keys a recipe to a single profession.
def memberships(ids, ability_rows, skill_rows):
    skills, selected, _ = professions(skill_rows)
    result = defaultdict(set)
    for row in ability_rows:
        spell, sid = int(row["Spell"]), int(row["SkillLine"])
        if spell not in ids or sid not in selected:
            continue
        seen = set()
        while True:
            if sid in seen or sid not in skills:
                raise ValueError(f"Missing/cyclic SkillLine parent for recipe {spell}: {sid}")
            seen.add(sid)
            parent = int(skills[sid]["ParentSkillLineID"])
            if parent not in selected:
                break
            sid = parent
        result[spell].add(sid)
    missing = ids - result.keys()
    if missing:
        raise ValueError(f"Threshold recipes without a profession: {sorted(missing)}")
    return result


def reagents_by_spell(ids, rows):
    result = {}
    for row in rows:
        spell = int(row["SpellID"])
        if spell not in ids:
            continue
        reagents, unresolved = Counter(), False
        for slot in range(8):
            item, quantity = int(row[f"Reagent_{slot}"]), int(row[f"ReagentCount_{slot}"])
            if item < 0:
                unresolved = True  # Non-item/sentinel reagent: never treat it as free.
            elif item == quantity == 0:
                continue
            elif item <= 0 or quantity <= 0:
                raise ValueError(f"Recipe {spell}: contradictory reagent {item} x {quantity}")
            else:
                reagents[item] += quantity
        value = None if unresolved else tuple(sorted(reagents.items()))
        put_unique(result, spell, value, "reagents")
    return result


def output_of(spell, rows):
    if not rows:
        raise ValueError(f"Recipe {spell}: no effects to resolve output")
    creates = [row for row in rows if int(row["Effect"]) == CREATE_ITEM]
    if not creates:
        # Permanent enchants may also have dummy/teleport effects; campfires
        # summon an object. No other effect is evidence of a non-item output.
        effects = {int(row["Effect"]) for row in rows}
        if effects == {TRANS_DOOR} or (ENCHANT_ITEM in effects and effects <= {DUMMY, TELEPORT_UNITS, ENCHANT_ITEM}):
            if any(int(row["EffectItemType"]) or int(row["EffectTriggerSpell"]) for row in rows):
                raise ValueError(f"Recipe {spell}: indirect item/triggered output needs review")
            return False
        raise ValueError(f"Recipe {spell}: unresolved output effects {sorted(effects)}")
    if len(creates) != 1:
        raise ValueError(f"Recipe {spell}: multiple create-item effects")
    row = creates[0]
    item = int(row["EffectItemType"])
    base, variance = float(row["EffectBasePointsF"]), float(row["Variance"])
    if (
        item <= 0
        or not math.isfinite(base)
        or not math.isfinite(variance)
        or base < 0
        or variance < 0
        or (base == 0 and variance != 0)
        or any(float(row[key]) != 0 for key in YIELD_MODIFIERS)
    ):
        raise ValueError(f"Recipe {spell}: invalid or scaled output yield")
    # BasePointsF is the centre of the yield range, not the old DB2 base-minus-one.
    # Variance is its relative full width. CREATE_ITEM clamps zero yield to one;
    # accept a random yield only when this clamp cannot change its mean.
    if variance and base * (1 - variance / 2) < 1 - 1e-6:
        raise ValueError(f"Recipe {spell}: output variance crosses the minimum yield")
    return item, max(1, base)


def generate(ids, ability_rows, skill_rows, reagent_rows, effect_rows, item_rows, name_rows, cooldown_tables=None):
    member = memberships(ids, ability_rows, skill_rows)
    lines = {spell: next(iter(sids)) for spell, sids in member.items() if len(sids) == 1}
    reagents = reagents_by_spell(ids, reagent_rows)
    effects = defaultdict(dict)
    for row in effect_rows:
        spell = int(row["SpellID"])
        if spell in ids and int(row["DifficultyID"]) == 0:
            put_unique(effects[spell], int(row["EffectIndex"]), row, f"effects of recipe {spell}")
    recipes = {}
    for spell in sorted(ids):
        if spell in lines and reagents.get(spell) is not None:
            recipes[spell] = (lines[spell], reagents[spell], output_of(spell, list(effects[spell].values())))
    if not recipes:
        raise ValueError("No resolved recipes; leaving existing output untouched")

    output_ids = {output[0] for _, _, output in recipes.values() if output is not False}
    sell = {}
    for row in item_rows:
        item = int(row["ID"])
        if item in output_ids:
            copper = int(row["SellPrice"])
            if copper < 0:
                raise ValueError(f"Item {item}: negative sell price")
            put_unique(sell, item, copper, "sell price")
    missing_items = output_ids - sell.keys()
    sell = {item: copper for item, copper in sell.items() if copper > 0}

    spell_names = {}
    for row in name_rows:
        spell = int(row["ID"])
        if spell in ids and row["Name_lang"]:
            put_unique(spell_names, spell, row["Name_lang"], "spell name")
    names = defaultdict(dict)
    for spell, name in sorted(spell_names.items()):
        for sid in sorted(member[spell]):
            profession = names[sid]
            profession[name] = False if name in profession else spell
    # Every profession, with or without a skill-up recipe: the runtime finds a gathering
    # profession by its name to price what it gathers.
    skills, selected, _ = professions(skill_rows)
    profession_lines = {}
    for sid in sorted(selected):
        if int(skills[sid]["ParentSkillLineID"]) not in selected:
            put_unique(profession_lines, skills[sid]["DisplayName_lang"], sid, "profession name")
    stats = {
        "thresholds": len(ids),
        "recipes": len(recipes),
        "omitted_reagents": len(ids) - len(recipes),
        "multi_profession": len(ids) - len(lines),
        "reagent_entries": sum(len(r) for _, r, _ in recipes.values()),
        "distinct_reagents": len({item for _, r, _ in recipes.values() for item, _ in r}),
        "item_outputs": sum(o is not False for _, _, o in recipes.values()),
        "non_item_outputs": sum(o is False for _, _, o in recipes.values()),
        "sell_prices": len(sell),
        "missing_output_items": len(missing_items),
        "names": sum(len(n) for n in names.values()),
        "ambiguous_names": sum(v is False for n in names.values() for v in n.values()),
        "missing_names": len(ids) - len(spell_names),
    }
    cooldowns = cooldown_data(recipes, *cooldown_tables) if cooldown_tables else ({}, {}, {})
    stats["recipe_cooldowns"], stats["cooldown_items"], stats["focus_objects"] = (len(table) for table in cooldowns)
    return recipes, sell, names, profession_lines, stats, cooldowns


# A cooldown below this is a cast delay, not a craft limit (the longest such recipe cooldown is 10 minutes).
MIN_COOLDOWN_MS = 3600000
ITEM_USE = 0  # ItemEffect.TriggerType: on use


def spell_cooldowns(rows):
    """Spell -> cooldown in ms (the longer of the spell's own and its category's), for those of at least an hour."""
    result = {}
    for row in rows:
        if int(row["DifficultyID"]) != 0:
            continue
        ms = max(int(row["CategoryRecoveryTime"]), int(row["RecoveryTime"]))
        if ms >= MIN_COOLDOWN_MS:
            result[int(row["SpellID"])] = max(result.get(int(row["SpellID"]), 0), ms)
    return result


def cooldown_data(
    recipes, cooldown_rows, effect_rows, item_effect_rows, item_link_rows, reagent_rows, requirement_rows, focus_rows
):
    """The three cooldown tables of #413, all from DB2.

    recipe_cooldowns  recipe spell -> ms, for recipes whose own spell has a cooldown of at least an hour (a transmute).
    items             item a cooldown spell makes -> { tool (the item you use), spell, ms, quantity, reagents }, for items
                      that are a reagent of a recipe: an item-use spell (ItemEffect on use) with a cooldown of at least an
                      hour that is not itself a recipe and creates exactly one item (Salt Shaker -> Refined Deeprock Salt).
    focus             recipe spell -> name of the object it needs (SpellCastingRequirements.RequiresSpellFocus), e.g.
                      "Tanning Rack".
    """
    cooldowns = spell_cooldowns(cooldown_rows)
    recipe_cooldowns = {spell: ms for spell, ms in cooldowns.items() if spell in recipes}

    creates = defaultdict(list)
    for row in effect_rows:
        if int(row["DifficultyID"]) == 0 and int(row["Effect"]) == CREATE_ITEM:
            creates[int(row["SpellID"])].append(row)
    reagent_of = {item for _, reagents, _ in recipes.values() for item, _ in reagents}
    spell_reagents = {}
    for row in reagent_rows:
        spell = int(row["SpellID"])
        if spell not in creates:
            continue
        found = Counter()
        for slot in range(8):
            item, quantity = int(row[f"Reagent_{slot}"]), int(row[f"ReagentCount_{slot}"])
            if item > 0 and quantity > 0:
                found[item] += quantity
        spell_reagents[spell] = tuple(sorted(found.items()))
    tools = defaultdict(set)
    for row in item_link_rows:
        tools[int(row["ItemEffectID"])].add(int(row["ItemID"]))
    items = {}
    for row in item_effect_rows:
        spell = int(row["SpellID"])
        if int(row["TriggerType"]) != ITEM_USE or spell in recipes or len(creates.get(spell, ())) != 1:
            continue
        ms = max(int(row["CoolDownMSec"]), int(row["CategoryCoolDownMSec"]), cooldowns.get(spell, 0))
        made = creates[spell][0]
        item = int(made["EffectItemType"])
        if ms < MIN_COOLDOWN_MS or item not in reagent_of or item <= 0:
            continue
        holders = tools.get(int(row["ID"]), set())
        if len(holders) != 1 or not spell_reagents.get(spell):
            raise ValueError(
                f"Cooldown spell {spell}: needs review (items {sorted(holders)}, reagents {spell_reagents.get(spell)})"
            )
        quantity = max(1, float(made["EffectBasePointsF"]))
        entry = {
            "tool": next(iter(holders)),
            "spell": spell,
            "ms": ms,
            "quantity": quantity,
            "reagents": spell_reagents[spell],
        }
        put_unique(items, item, entry, "cooldown item")

    focus_names = {int(row["ID"]): row["Name_lang"] for row in focus_rows}
    focus = {}
    for row in requirement_rows:
        spell, object_id = int(row["SpellID"]), int(row["RequiresSpellFocus"])
        if spell in recipes and object_id:
            if not focus_names.get(object_id):
                raise ValueError(f"Recipe {spell}: unnamed focus object {object_id}")
            put_unique(focus, spell, focus_names[object_id], "focus object")
    return recipe_cooldowns, items, focus


def lua_string(value):
    # Preserve the source locale and exact spelling; do not normalize trainer names.
    escapes = {"\\": "\\\\", '"': '\\"', "\n": "\\n", "\r": "\\r", "\t": "\\t"}
    return '"' + "".join(escapes.get(c, f"\\{ord(c):03d}" if ord(c) < 32 else c) for c in value) + '"'


def render(recipes, sell, names, profession_lines, stats, cooldowns=({}, {}, {})):
    lines = [
        "-- Generated by tools/gen_recipes.py — do not edit.",
        "-- luacheck: ignore 631",  # Deliberately compact generated rows.
        f"-- Source: wago.tools DB2, {PRODUCT} {BUILD}, {SOURCE_DATE}.",
        f"-- DB2: https://wago.tools/db2/SpellReagents/csv?build={BUILD}",
        "-- SkillLineAbility, SkillLine, SpellEffect, ItemSparse, SpellName: same source and build.",
        "-- SpellCooldowns, ItemEffect, ItemXItemEffect, SpellCastingRequirements, SpellFocusObject: same source and build.",
        "-- Threshold recipe spell IDs only; skillLine is the parent profession ID.",
        "-- Output quantity is mean yield; false is verified non-item output. Missing recipes are unknown.",
        "-- Trainer names use the source locale (enUS); false means ambiguous within the profession.",
        "-- " + "; ".join(f"{key}={value}" for key, value in stats.items()) + ".",
        "---@type string, table",
        "local _, ns = ...",
        "-- stylua: ignore",
        "ns.RecipeData = {",
    ]
    for spell, (skill, reagents, output) in sorted(recipes.items()):
        reagent_text = ", ".join(f"{{ itemID = {item}, quantity = {quantity} }}" for item, quantity in reagents)
        out = "false" if output is False else f"{{ itemID = {output[0]}, quantity = {output[1]:g} }}"
        lines.append(f"\t[{spell}] = {{ skillLine = {skill}, reagents = {{ {reagent_text} }}, output = {out} }},")
    lines.extend(["}", "", "ns.ItemSellPrices = {"])
    for item, copper in sorted(sell.items()):
        lines.append(f"\t[{item}] = {copper},")
    lines.extend(["}", "", "-- stylua: ignore", "ns.RecipeNames = {"])
    for skill, entries in sorted(names.items()):
        lines.append(f"\t[{skill}] = {{")
        for name, spell in sorted(entries.items()):
            value = "false" if spell is False else str(spell)
            lines.append(f"\t\t[{lua_string(name)}] = {value},")
        lines.append("\t},")
    lines.extend(
        [
            "}",
            "",
            "-- Profession name (source locale) to skill line; the game's own profession",
            "-- APIs report other IDs on Forever.",
            "ns.ProfessionSkillLines = {",
        ]
    )
    for name, skill in sorted(profession_lines.items()):
        lines.append(f"\t[{lua_string(name)}] = {skill},")
    lines.append("}")
    recipe_cooldowns, cooldown_items, focus = cooldowns
    lines.extend(
        [
            "",
            "-- Cooldowns (#413). Recipe spell to its own cooldown in ms (an hour or more), threshold recipes only.",
            "ns.RecipeCooldowns = {",
        ]
    )
    for spell, ms in sorted(recipe_cooldowns.items()):
        lines.append(f"\t[{spell}] = {ms},")
    lines.extend(
        [
            "}",
            "",
            "-- A reagent that a cooldown spell makes to the item you use, the spell, its cooldown in ms, the units one use",
            "-- makes and what the spell consumes (Salt Shaker: 1 Deeprock Salt into 1 Refined Deeprock Salt).",
            "ns.CooldownItems = {",
        ]
    )
    for item, e in sorted(cooldown_items.items()):
        reagent_text = ", ".join(f"{{ itemID = {i}, quantity = {q} }}" for i, q in e["reagents"])
        lines.append(
            f"\t[{item}] = {{ tool = {e['tool']}, spell = {e['spell']}, ms = {e['ms']}, "
            f"quantity = {e['quantity']:g}, reagents = {{ {reagent_text} }} }},"
        )
    lines.extend(["}", "", "-- Recipe spell to the object it is cast near (a Tanning Rack), source locale.", "ns.RecipeFocus = {"])
    for spell, name in sorted(focus.items()):
        lines.append(f"\t[{spell}] = {lua_string(name)},")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--refresh", action="store_true", help="redownload the pinned sources")
    mode.add_argument("--offline", action="store_true", help="use cached sources only")
    args = parser.parse_args()
    options = {"refresh": args.refresh, "offline": args.offline}
    ids = threshold_ids()
    recipes, sell, names, profession_lines, stats, cooldowns = generate(
        ids,
        db2("SkillLineAbility", ("Spell", "SkillLine"), **options),
        db2("SkillLine", ("ID", "DisplayName_lang", "CategoryID", "CanLink", "ParentSkillLineID"), **options),
        db2(
            "SpellReagents",
            ("SpellID", *(f"Reagent_{i}" for i in range(8)), *(f"ReagentCount_{i}" for i in range(8))),
            **options,
        ),
        db2(
            "SpellEffect",
            (
                "SpellID",
                "DifficultyID",
                "EffectIndex",
                "Effect",
                "EffectItemType",
                "EffectBasePointsF",
                "Variance",
                *YIELD_MODIFIERS,
            ),
            **options,
        ),
        db2("ItemSparse", ("ID", "SellPrice"), **options),
        db2("SpellName", ("ID", "Name_lang"), **options),
        (
            db2("SpellCooldowns", ("SpellID", "DifficultyID", "CategoryRecoveryTime", "RecoveryTime"), **options),
            db2("SpellEffect", ("SpellID", "DifficultyID", "Effect", "EffectItemType", "EffectBasePointsF"), **options),
            db2("ItemEffect", ("TriggerType", "CoolDownMSec", "CategoryCoolDownMSec", "SpellID"), **options),
            db2("ItemXItemEffect", ("ItemEffectID", "ItemID"), **options),
            db2(
                "SpellReagents",
                ("SpellID", *(f"Reagent_{i}" for i in range(8)), *(f"ReagentCount_{i}" for i in range(8))),
                **options,
            ),
            db2("SpellCastingRequirements", ("SpellID", "RequiresSpellFocus"), **options),
            db2("SpellFocusObject", ("ID", "Name_lang"), **options),
        ),
    )
    content = render(recipes, sell, names, profession_lines, stats, cooldowns)
    write_lua(OUTPUT, content)
    for key, value in stats.items():
        print(f"{key}: {value}")
    print(f"Unresolved reagent recipes omitted: {sorted(ids - recipes.keys())}")
    print(f"Wrote {OUTPUT.relative_to(ROOT)}: {len(content.encode('utf-8')):,} bytes")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, urllib.error.URLError) as error:
        sys.exit(f"error: {error}")
