#!/usr/bin/env python3
"""Generate the companion's icon (#310): the W key brand mark as a multi-size .ico and the Windows resource
object that gives the exe its icon. Stdlib only.

Outputs (all committed):
  companion/tray/craftwise.ico                       16 20 24 32 40 48 64 256 px; embedded for the tray
  companion/cmd/craftwise-companion/rsrc_windows_amd64.syso   the same icons as RT_ICON / RT_GROUP_ICON, picked
                                                     up by `go build` for windows/amd64 (no other step)
  companion/tray/icon-preview.png                    every size on a light and a dark ground (1x and 8x)

Where the shapes come from:
  24 px and up   web/public/img/key-wow-32.svg (the site's app key: gold folded key, dark face, teal nokta,
                 white W), rendered with the rasteriser of tools/gen_addon_textures.py, the same one that
                 made CraftWise/Media/cw-key-w.tga from velikopter-brand's key-wow.svg.
  16 and 20 px   drawn for their pixel grid: whole-pixel rectangles (gold body with the top-right corner cut,
                 dark face, a pixel-art W, no nokta, no fold), because the 100 unit drawing turns to mush
                 at that size. The W bitmaps below are the only hand-drawn part.

Entries below 256 px are 32-bit BMP (DIB) images, the 256 px one is PNG: the combination every Windows from
Vista on reads, and what CreateIconFromResourceEx accepts for the tray.

Usage: python3 tools/gen_companion_icon.py
"""

import struct
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_addon_textures as tex  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SVG = ROOT / "web" / "public" / "img" / "key-wow-32.svg"
ICO = ROOT / "companion" / "tray" / "craftwise.ico"
SYSO = ROOT / "companion" / "cmd" / "craftwise-companion" / "rsrc_windows_amd64.syso"
PREVIEW = ROOT / "companion" / "tray" / "icon-preview.png"
SIZES = (16, 20, 24, 32, 40, 48, 64, 256)

GOLD, FACE, WHITE = "#E8B94B", "#141517", "#F4F4F1"

W16 = ("XX......XX",
       "XX......XX",
       "XX..XX..XX",
       "XX.XXXX.XX",
       ".XXX..XXX.")
W20 = ("XX......XX",
       "XX......XX",
       "XX......XX",
       "XX..XX..XX",
       "XX.XXXX.XX",
       ".XXX..XXX.",
       "..XX..XX..")


def rects(c, boxes, colour):
    c.fill([[(x0, y0), (x1, y0), (x1, y1), (x0, y1)] for x0, y0, x1, y1 in boxes], tex.hex_rgb(colour))


def bitmap(c, rows, x0, y0, colour):
    rects(c, [(x0 + x, y0 + y, x0 + x + 1, y0 + y + 1) for y, r in enumerate(rows) for x, ch in enumerate(r) if ch == "X"],
          colour)


def small_key(n):
    """16 or 20 px: gold body without its top-right corner (3 or 4 px diagonal), dark face, pixel W."""
    c = tex.Canvas(n, n)
    cut = 3 if n == 16 else 4
    c.fill([[(0, 0), (n - cut, 0), (n, cut), (n, n), (0, n)]], tex.hex_rgb(GOLD))
    inset = 2 if n == 16 else 3
    rects(c, [(inset, inset, n - inset, n - inset)], FACE)
    w = W16 if n == 16 else W20
    bitmap(c, w, (n - len(w[0])) // 2, inset + (n - 2 * inset - len(w) + 1) // 2, WHITE)
    return c


def render(n):
    """Straight RGBA bytes, top row first."""
    c = small_key(n) if n < 24 else tex.render_svg(SVG, n)
    return bytes(c.rgba_bytes(False))


def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)


def png(pixels, w, h, colour_type):
    bpp = 4 if colour_type == 6 else 3
    raw = b"".join(b"\x00" + pixels[y * w * bpp:(y + 1) * w * bpp] for y in range(h))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, colour_type, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def dib(rgba, n):
    """BITMAPINFOHEADER + BGRA bottom-up + 1 bpp AND mask (all zero: alpha does the cutting)."""
    head = struct.pack("<IiiHHIIiiII", 40, n, n * 2, 1, 32, 0, n * n * 4, 0, 0, 0, 0)
    pix = bytearray()
    for y in range(n - 1, -1, -1):
        for x in range(n):
            r, g, b, a = rgba[(y * n + x) * 4:(y * n + x) * 4 + 4]
            pix += bytes((b, g, r, a))
    return head + bytes(pix) + bytes(((n + 31) // 32) * 4 * n)


def images():
    out = []
    for n in SIZES:
        rgba = render(n)
        out.append((n, png(rgba, n, n, 6) if n == 256 else dib(rgba, n), rgba))
    return out


def build_ico(imgs):
    off = 6 + 16 * len(imgs)
    ents, data = b"", b""
    for n, blob, _ in imgs:
        ents += struct.pack("<BBBBHHII", n % 256, n % 256, 0, 0, 1, 32, len(blob), off + len(data))
        data += blob
    return struct.pack("<HHH", 0, 1, len(imgs)) + ents + data


def build_syso(imgs):
    """COFF object (amd64) with one .rsrc section: RT_ICON 1..n and RT_GROUP_ICON 1 (language 0x409). The
    RVA of every resource data entry is relocated (IMAGE_REL_AMD64_ADDR32NB) against the section symbol."""
    grp = struct.pack("<HHH", 0, 1, len(imgs)) + b"".join(
        struct.pack("<BBBBHHIH", s % 256, s % 256, 0, 0, 1, 32, len(b), i + 1) for i, (s, b, _) in enumerate(imgs))
    types = [(3, [(i + 1, b) for i, (_, b, _) in enumerate(imgs)]), (14, [(1, grp)])]
    # layout: root dir; per type a dir of names; per name a dir of one language; then the data entries; then data
    pos = 16 + 8 * len(types)
    plan = []
    for t, names in types:
        tdir = pos
        pos += 16 + 8 * len(names)
        ents = []
        for nid, blob in names:
            ents.append((nid, pos, blob))
            pos += 16 + 8
        plan.append((t, tdir, ents))
    de = pos
    pos += 16 * sum(len(e) for _, _, e in plan)
    res = bytearray(pos)

    def dirhdr(at, count):
        res[at:at + 16] = struct.pack("<IIHHHH", 0, 0, 0, 0, 0, count)

    def entry(at, i, ident, target, sub):
        res[at + 16 + 8 * i:at + 24 + 8 * i] = struct.pack("<II", ident, target | (0x80000000 if sub else 0))

    dirhdr(0, len(plan))
    relocs, blobs = [], []
    data_off = pos
    for ti, (t, tdir, ents) in enumerate(plan):
        entry(0, ti, t, tdir, True)
        dirhdr(tdir, len(ents))
        for ni, (nid, ndir, blob) in enumerate(ents):
            entry(tdir, ni, nid, ndir, True)
            dirhdr(ndir, 1)
            entry(ndir, 0, 0x409, de, False)
            res[de:de + 16] = struct.pack("<IIII", data_off, len(blob), 0, 0)
            relocs.append(de)
            blobs.append(blob)
            data_off += (len(blob) + 3) & ~3
            de += 16
    for b in blobs:
        res += b + bytes(-len(b) % 4)
    size = len(res)
    sec = struct.pack("<8sIIIIIIHHI", b".rsrc", 0, 0, size, 60, 60 + size, 0, len(relocs), 0, 0x40000040)
    rel = b"".join(struct.pack("<IIH", o, 0, 3) for o in relocs)
    symoff = 60 + size + len(rel)
    sym = (struct.pack("<8sIhHBB", b".rsrc", 0, 1, 0, 3, 1)
           + struct.pack("<IHHIHBBBB", size, len(relocs), 0, 0, 1, 0, 0, 0, 0))
    head = struct.pack("<HHIIIHH", 0x8664, 1, 0, symoff, 2, 0, 0)
    return head + sec + bytes(res) + rel + sym + struct.pack("<I", 4)


def preview(imgs):
    """Each size on a light and a dark ground, 1x and (up to 48 px) 8x with nearest-neighbour."""
    pad, scale = 8, 8
    items = [(n, rgba, 1) for n, _, rgba in imgs] + [(n, rgba, scale) for n, _, rgba in imgs if n <= 48]
    row_h = 48 * scale + 2 * pad
    total_w = pad + sum(n * k + pad for n, _, k in items)
    grounds = [(243, 243, 241), (32, 33, 37)]
    pix = bytearray()
    for gi, g in enumerate(grounds):
        rows = [[g] * total_w for _ in range(row_h)]
        x = pad
        for n, rgba, k in items:
            for yy in range(n * k):
                for xx in range(n * k):
                    i = ((yy // k) * n + xx // k) * 4
                    r, gg, b, a = rgba[i:i + 4]
                    al = a / 255
                    base = rows[pad + yy][x + xx]
                    rows[pad + yy][x + xx] = (round(r * al + base[0] * (1 - al)), round(gg * al + base[1] * (1 - al)),
                                              round(b * al + base[2] * (1 - al)))
            x += n * k + pad
        for r in rows:
            pix += b"".join(bytes(p) for p in r)
    return png(bytes(pix), total_w, row_h * 2, 2)


def main():
    imgs = images()
    ICO.write_bytes(build_ico(imgs))
    SYSO.write_bytes(build_syso(imgs))
    PREVIEW.write_bytes(preview(imgs))
    for p in (ICO, SYSO, PREVIEW):
        print(f"wrote {p.relative_to(ROOT)} ({p.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
