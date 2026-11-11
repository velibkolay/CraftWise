#!/usr/bin/env python3
"""Build the local fishing reference addon CraftWise_FishingRef from saved web pages (issue #88; stdlib only).

The reference data is not part of CraftWise and never goes into the repository: you save the pages yourself,
this script turns them into a small local addon that CraftWise reads when it is loaded.

Usage:
    python tools/fishing_ref.py <AddOns>/CraftWise_FishingRef [--pages DIR]

Reads every .htm/.html file in <folder>/pages/ (or --pages) and writes <folder>/Data.lua and
<folder>/<folder name>.toc. Pages it understands (Wowhead pages saved with "Save page as", HTML only):
  * zone pages with a `fishing` listview: what was fished in the zone. Per item: `count` (how often it was
    fished) out of the listview's `_totalCount` (fishing loots recorded in the zone), and `stack` [min, max].
  * item pages with a `contains` listview: what a container gave (trunks, crates, clams). Per item: `count`
    out of `outof` (or the listview's `_totalCount`), and `stack`.
  * object pages (fishing pools) with a `fishing` or `contains` listview: the pool's loot, kept by object ID.
Anything else is skipped and listed. Nothing is estimated: counts and stacks are written as found.
"""

import argparse
import datetime
import html
import json
import os
import re
import sys

GLOBAL = "CraftWise_FishingRef"
TITLE = "CraftWise Fishing Reference (local)"
INTERFACE = "16001"
PAGE_TYPES = {7: "zone", 3: "item", 2: "object"}


# ---------------------------------------------------------------------------------------------------
# Scanning JavaScript without running it
# ---------------------------------------------------------------------------------------------------

def skip_string(text, i):
    """i is at a quote; returns the index after the closing quote."""
    quote = text[i]
    i += 1
    while i < len(text):
        ch = text[i]
        if ch == "\\":
            i += 2
            continue
        if ch == quote:
            return i + 1
        i += 1
    return i


def match_bracket(text, i):
    """i is at an opening bracket ({ or [); returns the index after its closing bracket, or -1."""
    pairs = {"{": "}", "[": "]", "(": ")"}
    stack = [pairs[text[i]]]
    i += 1
    while i < len(text):
        ch = text[i]
        if ch in "\"'`":
            i = skip_string(text, i)
            continue
        if ch in pairs:
            stack.append(pairs[ch])
        elif ch in ")]}":
            if not stack or ch != stack[-1]:
                return -1
            stack.pop()
            if not stack:
                return i + 1
        i += 1
    return -1


def top_level_items(body, sep=","):
    """Splits the inside of an object or array at separators that are not nested or in strings."""
    parts, start, i, depth = [], 0, 0, 0
    while i < len(body):
        ch = body[i]
        if ch in "\"'`":
            i = skip_string(body, i)
            continue
        if ch in "{[(":
            depth += 1
        elif ch in "}])":
            depth -= 1
        elif ch == sep and depth == 0:
            parts.append(body[start:i])
            start = i + 1
        i += 1
    parts.append(body[start:])
    return [p for p in (p.strip() for p in parts) if p]


def split_pair(item):
    """'key: value' (key quoted or bare) -> (key, value text) or None."""
    m = re.match(r"""\s*(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)'|([A-Za-z_$][\w$]*))\s*:""", item)
    if not m:
        return None
    key = next(g for g in m.groups() if g is not None)
    return key, item[m.end():].strip()


def object_fields(obj_text):
    """Top-level fields of a JS object literal: { key: value text }."""
    fields = {}
    for item in top_level_items(obj_text.strip()[1:-1]):
        pair = split_pair(item)
        if pair:
            fields[pair[0]] = pair[1]
    return fields


def js_to_json(text):
    """A JS literal made of objects, arrays, strings, numbers, true/false/null to JSON text.
    Handles single-quoted strings, bare keys, trailing commas, undefined and !0/!1."""
    out, i = [], 0
    while i < len(text):
        ch = text[i]
        if ch == '"':
            end = skip_string(text, i)
            out.append(text[i:end])
            i = end
        elif ch == "'":
            end = skip_string(text, i)
            inner = text[i + 1:end - 1]
            inner = re.sub(r"\\'", "'", inner).replace('"', '\\"')
            out.append('"' + inner + '"')
            i = end
        elif ch == ",":
            j = i + 1
            while j < len(text) and text[j] in " \t\r\n":
                j += 1
            if j < len(text) and text[j] in "}]":
                i += 1  # trailing comma
            else:
                out.append(ch)
                i += 1
        elif ch == "!" and text[i + 1:i + 2] in ("0", "1"):
            out.append("true" if text[i + 1] == "0" else "false")
            i += 2
        elif ch.isalpha() or ch in "_$":
            m = re.match(r"[A-Za-z_$][\w$]*", text[i:])
            word = m.group(0)
            j = i + len(word)
            while j < len(text) and text[j] in " \t\r\n":
                j += 1
            if j < len(text) and text[j] == ":":
                out.append('"' + word + '"')  # bare key
            elif word == "undefined":
                out.append("null")
            else:
                out.append(word)
            i += len(word)
        else:
            out.append(ch)
            i += 1
    return "".join(out)


def parse_value(text):
    """JSON first, then the lenient JS form; None when neither works."""
    for candidate in (text, js_to_json(text)):
        try:
            return json.loads(candidate)
        except ValueError:
            pass
    return None


def parse_array(text, warnings, what):
    """A data array; when the whole array doesn't parse, each element is tried on its own."""
    value = parse_value(text)
    if isinstance(value, list):
        return value
    rows, bad = [], 0
    for item in top_level_items(text.strip()[1:-1]):
        row = parse_value(item)
        if isinstance(row, dict):
            rows.append(row)
        else:
            bad += 1
    if bad:
        warnings.append(f"{what}: {bad} data entries could not be read")
    return rows


def listviews(text):
    """Every `new Listview({...})` of a page: { id, total, data text } (data text None when it isn't inline)."""
    found = []
    for m in re.finditer(r"new\s+(?:WH\.)?Listview\s*\(\s*\{", text):
        start = m.end() - 1
        end = match_bracket(text, start)
        if end < 0:
            continue
        fields = object_fields(text[start:end])
        lv_id = parse_value(fields.get("id", "null"))
        total = parse_value(fields.get("_totalCount", "null"))
        data = fields.get("data")
        if data is not None and not data.startswith("["):
            data = None
        found.append({"id": lv_id, "total": total if isinstance(total, int) else None, "data": data})
    return found


# ---------------------------------------------------------------------------------------------------
# Page identity
# ---------------------------------------------------------------------------------------------------

def page_info(text):
    """(type name or None, id or None, name or None) from g_pageInfo, then the page URL, then headings."""
    kind = type_id = name = None
    m = re.search(r"g_pageInfo\s*=\s*\{", text)
    if m:
        end = match_bracket(text, m.end() - 1)
        info = parse_value(text[m.end() - 1:end]) if end > 0 else None
        if isinstance(info, dict):
            kind = PAGE_TYPES.get(info.get("type"))
            type_id = info.get("typeId") if isinstance(info.get("typeId"), int) else None
            name = info.get("name") if isinstance(info.get("name"), str) else None
    if type_id is None:
        for pattern in (r'<link[^>]+rel="canonical"[^>]+href="([^"]+)"', r'<meta[^>]+property="og:url"[^>]+content="([^"]+)"',
                        r"saved from url=\(\d+\)(\S+)"):
            u = re.search(pattern, text)
            um = u and re.search(r"[/?](zone|item|object)=(\d+)", u.group(1))
            if um:
                kind = kind or um.group(1)
                type_id = int(um.group(2))
                break
    if not name:
        h = re.search(r"<h1[^>]*>(.*?)</h1>", text, re.S)
        if h:
            name = re.sub(r"<[^>]+>", "", h.group(1)).strip()
    if not name:
        t = re.search(r"<title>(.*?)</title>", text, re.S)
        if t:
            name = t.group(1).split(" - ")[0].strip()
    return kind, type_id, html.unescape(name) if name else None


def item_name(row):
    name = row.get("name")
    if not isinstance(name, str):
        return None
    # Older listview rows carry the quality as a leading digit ("6Some Fish") and no quality field.
    if "quality" not in row and re.match(r"^[0-7][^\d\s]", name):
        name = name[1:]
    return html.unescape(name)


def loot_rows(data, warnings, what, outof_default):
    items = []
    for row in data:
        if not isinstance(row, dict) or not isinstance(row.get("id"), int):
            continue
        count = row.get("count")
        if not isinstance(count, int) or count <= 0:
            continue
        entry = {"id": row["id"], "name": item_name(row), "count": count}
        stack = row.get("stack")
        if isinstance(stack, list) and len(stack) == 2 and all(isinstance(s, int) for s in stack):
            entry["stack"] = stack
        outof = row.get("outof")
        if isinstance(outof, int) and outof > 0 and outof != outof_default:
            entry["outof"] = outof
        items.append(entry)
    items.sort(key=lambda e: (-e["count"], e["id"]))
    if not items:
        warnings.append(f"{what}: no item rows with an id and a count")
    return items


def read_page(path, warnings):
    """One page -> ("zone"|"container"|"pool", record) or (None, reason)."""
    with open(path, "rb") as f:
        text = f.read().decode("utf-8", errors="replace")
    kind, type_id, name = page_info(text)
    views = {lv["id"]: lv for lv in listviews(text) if isinstance(lv["id"], str)}
    base = os.path.basename(path)
    if kind is None:
        kind = "zone" if "fishing" in views else "item" if "contains" in views else None
    if kind == "zone":
        lv = views.get("fishing")
        if not lv:
            return None, "zone page without a fishing listview"
        target = "zone"
    elif kind in ("item", "object"):
        lv = views.get("contains") or (views.get("fishing") if kind == "object" else None)
        if not lv:
            return None, f"{kind} page without a contains listview"
        target = "container" if kind == "item" else "pool"
        if type_id is None:
            return None, f"{kind} page without an ID (g_pageInfo or page URL)"
    else:
        return None, "no fishing or contains listview"
    if lv["data"] is None:
        return None, f"{lv['id']} listview data is not inline in the page"
    data = parse_array(lv["data"], warnings, base)
    total = lv["total"]
    items = loot_rows(data, warnings, base, total)
    if not items:
        return None, "no usable rows"
    if total is None:
        if not all("outof" in e for e in items):
            return None, f"{lv['id']} listview without _totalCount"
    record = {"id": type_id, "name": name, "total": total, "file": base, "items": items}
    return target, record


# ---------------------------------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------------------------------

def lua_str(s):
    s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r")
    return '"' + s + '"'


def lua_items(items, indent):
    lines = []
    for e in items:
        parts = [f"id = {e['id']}"]
        if e.get("name"):
            parts.append(f"name = {lua_str(e['name'])}")
        parts.append(f"count = {e['count']}")
        if "outof" in e:
            parts.append(f"outof = {e['outof']}")
        if "stack" in e:
            parts.append(f"stack = {{ {e['stack'][0]}, {e['stack'][1]} }}")
        lines.append(f"{indent}{{ {', '.join(parts)} }},")
    return lines


def lua_record(r, indent, key=None):
    head = [f"id = {r['id']}" if r["id"] is not None else None,
            f"name = {lua_str(r['name'])}" if r["name"] else None,
            f"total = {r['total']}" if r["total"] is not None else None,
            f"file = {lua_str(r['file'])}"]
    prefix = f"[{key}] = " if key is not None else ""
    lines = [f"{indent}{prefix}{{ {', '.join(h for h in head if h)}, items = {{"]
    lines += lua_items(r["items"], indent + "\t")
    lines.append(f"{indent}}} }},")
    return lines


def render(zones, containers, pools, pages, today):
    lines = [
        f"-- Generated by CraftWise tools/fishing_ref.py on {today} from {pages} saved pages; do not edit.",
        "-- Local reference data for CraftWise's Fishing view (issue #88). Not part of CraftWise: never commit or share.",
        "-- count = how often the item was recorded, out of total (or outof); stack = { min, max } per drop.",
        f"{GLOBAL} = {{",
        "\tversion = 1,",
        f"\tgenerated = {lua_str(today)},",
        "\tzones = {",
    ]
    for z in sorted(zones, key=lambda r: ((r["name"] or "").lower(), r["id"] or 0)):
        lines += lua_record(z, "\t\t")
    lines.append("\t},")
    for label, table in (("containers", containers), ("pools", pools)):
        lines.append(f"\t{label} = {{")
        for key in sorted(table):
            lines += lua_record(table[key], "\t\t", key)
        lines.append("\t},")
    lines.append("}")
    return "\n".join(lines) + "\n"


def render_toc(today):
    return "\n".join([
        f"## Interface: {INTERFACE}",
        f"## Title: {TITLE}",
        "## Notes: Local fishing reference for CraftWise, built by tools/fishing_ref.py from pages you saved. Not for distribution.",
        "## OptionalDeps: CraftWise",
        f"## X-Generated: {today}",
        "",
        "Data.lua",
        "",
    ])


def bigger(a, b):
    return a if (a["total"] or 0) >= (b["total"] or 0) else b


def build(folder, pages_dir=None, today=None, out=sys.stdout):
    pages_dir = pages_dir or os.path.join(folder, "pages")
    today = today or datetime.date.today().isoformat()
    if not os.path.isdir(pages_dir):
        raise SystemExit(f"No pages folder: {pages_dir}")
    files = []
    for root, dirs, names in os.walk(pages_dir):
        dirs[:] = [d for d in dirs if not d.endswith("_files")]  # "Save page as" puts assets there
        files += [os.path.join(root, n) for n in names if n.lower().endswith((".html", ".htm"))]
    files.sort()
    zones, containers, pools, skipped, warnings = {}, {}, {}, [], []
    for path in files:
        target, record = read_page(path, warnings)
        if target is None:
            skipped.append((os.path.basename(path), record))
            continue
        if target == "zone":
            key = record["id"] if record["id"] is not None else (record["name"] or record["file"]).lower()
            if key in zones:
                warnings.append(f"{record['file']}: zone also in {zones[key]['file']}; kept the one with more recorded loots")
            zones[key] = bigger(zones[key], record) if key in zones else record
        else:
            table = containers if target == "container" else pools
            key = record["id"]
            if key in table:
                warnings.append(f"{record['file']}: {target} {key} also in {table[key]['file']}; kept the one with more recorded loots")
            table[key] = bigger(table[key], record) if key in table else record
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, "Data.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write(render(zones.values(), containers, pools, len(files), today))
    toc = os.path.basename(os.path.normpath(os.path.abspath(folder))) + ".toc"
    with open(os.path.join(folder, toc), "w", encoding="utf-8", newline="\n") as f:
        f.write(render_toc(today))
    print(f"{len(files)} pages: {len(zones)} zones, {len(containers)} containers, {len(pools)} pools.", file=out)
    for z in sorted(zones.values(), key=lambda r: (r["name"] or "").lower()):
        print(f"  zone {z['name']} ({z['id']}): {len(z['items'])} items, {z['total']} recorded", file=out)
    for name, reason in skipped:
        print(f"  skipped {name}: {reason}", file=out)
    for w in warnings:
        print(f"  note: {w}", file=out)
    print(f"Wrote {os.path.join(folder, 'Data.lua')} and {toc}. Restart the game once so it sees the new addon.", file=out)
    return zones, containers, pools, skipped


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("folder", help="the CraftWise_FishingRef addon folder (Interface/AddOns/CraftWise_FishingRef)")
    parser.add_argument("--pages", help="folder with the saved pages (default: <folder>/pages)")
    parser.add_argument("--date", help=argparse.SUPPRESS)  # fixed date for tests
    args = parser.parse_args(argv)
    build(args.folder, args.pages, args.date)


if __name__ == "__main__":
    main()
