#!/usr/bin/env python3
"""Generate the addon's own textures in CraftWise/Media/ (#151, spec in #150: Shapes and textures, Assets).

Stdlib only. Every file is a 32-bit uncompressed TGA with straight (not premultiplied) alpha, power-of-two
sized, bottom-left origin. The shapes are white where the addon tints them with SetVertexColor (or the |T
escape's colour), so one file serves every colour; the header art and the W key are baked in colour.

  cw-fold.tga            64 x 64   dog-ear: white lower-left triangle, transparent upper-right half
  cw-nokta.tga           32 x 32   the nokta: a white diamond touching the four edges (drawn 11 x 11)
  cw-check.tga           16 x 16   checkbox tick, the boards' path "M1 4.2 3 6l4-4.5" (viewBox 8, stroke 1.6)
  cw-header-wide.tga   1024 x 64   window header (board "Window layout", 880 x 56 units): gold key block in
                                   two tones (#E8B94B / #D9A93A, diagonal right edge) and the dark planes
                                   (#202125, #25262A); the top-right 22 unit corner stays transparent
  cw-header-narrow.tga  512 x 64   docked header (board "Docked layout", 380 x 64 units), same parts
  cw-key-w.tga           64 x 64   velikopter-brand app-keys/key-wow.svg rendered as is (not redrawn)
  cw-up.tga, cw-down.tga 16 x 16   ▲ and ▼: Atkinson Hyperlegible has no such glyph; the boards' caret
                                   (path "M1 3h8L5 8z" in a 10 unit box), pointing up and down
  cw-arrow.tga           16 x 16   →: no such glyph either; shaft and head on the same 10 unit grid
  cw-gear.tga            32 x 32   the window header's Settings gear (#153), the boards' icon: a ring
                                   (r 2.5) and eight spokes, stroke 1.6, butt caps, in a 16 unit box
  cw-dock.tga            32 x 32   the header's dock button: a frame (11 x 10, stroke 1.4) with its left
                                   4 units filled, in a 14 unit box
  cw-close.tga           32 x 32   the header's close button: two diagonals, stroke 1.6, square caps, in a
                                   12 unit box
  cw-undock.tga          32 x 32   the docked header's undock button (#161, board "Docked layout, on your
                                   screen"): the same frame with a title bar line (M1.5 5h11), stroke 1.4

The header files hold the boards' polygons scaled to the texture: drawn over the whole header (880 x 56 in
the window, 380 x 64 docked) they give the board's shapes. Stretch them horizontally only if a layout ever
changes width; the W key and "CraftWise" are separate textures and text so they stay sharp.

The W key is read from a velikopter-brand checkout (default: ../velikopter-brand next to this repo, or
--brand PATH) and rendered with the same rasteriser: polygons and the W path, fills and fill-opacity, in
document order. The shipped file was made from branch kit-v3-origami at 91a7baf; the script warns when the
checkout is at another commit.

Fonts (one-off, not part of this script; fontTools is a tool, not a dependency):

  pip install --break-system-packages fonttools          # 4.67.0 was used
  C=c30b221beb0c1da59d563feb91ec8656a1fa972a             # google/fonts main, 12 Nov 2026
  curl -fLo next.ttf "https://raw.githubusercontent.com/google/fonts/$C/ofl/atkinsonhyperlegiblenext/AtkinsonHyperlegibleNext%5Bwght%5D.ttf"
  curl -fLo mono.ttf "https://raw.githubusercontent.com/google/fonts/$C/ofl/atkinsonhyperlegiblemono/AtkinsonHyperlegibleMono%5Bwght%5D.ttf"
  F=CraftWise/Media/Fonts
  fonttools varLib.instancer next.ttf wght=400 --static --update-name-table -o $F/AtkinsonHyperlegibleNext-Regular.ttf
  fonttools varLib.instancer next.ttf wght=700 --static --update-name-table -o $F/AtkinsonHyperlegibleNext-Bold.ttf
  fonttools varLib.instancer next.ttf wght=800 --static --update-name-table -o $F/AtkinsonHyperlegibleNext-ExtraBold.ttf
  fonttools varLib.instancer mono.ttf wght=400 --static --update-name-table -o $F/AtkinsonHyperlegibleMono-Regular.ttf
  fonttools varLib.instancer mono.ttf wght=600 --static --update-name-table -o $F/AtkinsonHyperlegibleMono-SemiBold.ttf
  cp ../velikopter-brand/fonts/OFL-Next.txt ../velikopter-brand/fonts/OFL-Mono.txt $F/

  sha256 of the variable files: next 5a455d1c...e31745, mono 5ce8b169...f646. Neither OFL.txt names a
  Reserved Font Name, so the cut families keep their names. The cut has · − × but not ▲ ▼ → (nor ▾):
  those are the textures above.

Usage: python3 tools/gen_addon_textures.py [--brand PATH]
"""

import argparse
import re
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MEDIA = ROOT / "CraftWise" / "Media"
BRAND_COMMIT = "91a7baf"
SS = 16  # sub-scanlines per pixel row; coverage along a scanline is exact


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i : i + 2], 16) / 255 for i in (0, 2, 4))


WHITE = (1.0, 1.0, 1.0)


class Canvas:
    """Straight-alpha RGBA in floats, composited source-over like a browser draws SVG."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [[0.0, 0.0, 0.0, 0.0] for _ in range(w * h)]  # premultiplied while drawing

    def fill(self, polygons, rgb, opacity=1.0, sx=1.0, sy=1.0):
        """Fill polygons (lists of (x, y), y down) with the nonzero rule, scaled by sx, sy."""
        cov = coverage([[(x * sx, y * sy) for x, y in p] for p in polygons], self.w, self.h)
        r, g, b = rgb
        for i, c in enumerate(cov):
            if c <= 0:
                continue
            a = min(c, 1.0) * opacity
            p = self.px[i]
            p[0] = r * a + p[0] * (1 - a)
            p[1] = g * a + p[1] * (1 - a)
            p[2] = b * a + p[2] * (1 - a)
            p[3] = a + p[3] * (1 - a)

    def rgba_bytes(self, bleed):
        """Rows top to bottom as straight RGBA bytes. Transparent pixels take the colour of the nearest
        drawn neighbour (bleed) so bilinear filtering at the edges doesn't pull in black."""
        w, h = self.w, self.h
        col = [None] * (w * h)
        for i, p in enumerate(self.px):
            if p[3] > 0:
                col[i] = (p[0] / p[3], p[1] / p[3], p[2] / p[3])
        if bleed:
            for _ in range(max(w, h)):
                missing = [i for i, c in enumerate(col) if c is None]
                if not missing:
                    break
                fill = {}
                for i in missing:
                    x, y = i % w, i // w
                    for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                        if 0 <= nx < w and 0 <= ny < h and col[ny * w + nx] is not None:
                            fill[i] = col[ny * w + nx]
                            break
                if not fill:
                    break
                for i, c in fill.items():
                    col[i] = c
        out = bytearray()
        for i, p in enumerate(self.px):
            r, g, b = col[i] if col[i] is not None else WHITE
            out += bytes(round(v * 255) for v in (r, g, b, p[3]))
        return out


def coverage(polygons, w, h):
    """Per-pixel area coverage of the union (nonzero winding) of polygons: SS sub-scanlines per row, and on
    each the exact covered length per pixel."""
    cov = [0.0] * (w * h)
    edges = []
    for poly in polygons:
        for i in range(len(poly)):
            (x0, y0), (x1, y1) = poly[i], poly[(i + 1) % len(poly)]
            if y0 != y1:
                edges.append((x0, y0, x1, y1, 1 if y1 > y0 else -1))
    for row in range(h):
        for k in range(SS):
            y = row + (k + 0.5) / SS
            hits = []
            for x0, y0, x1, y1, d in edges:
                if min(y0, y1) <= y < max(y0, y1):
                    hits.append((x0 + (y - y0) * (x1 - x0) / (y1 - y0), d))
            if not hits:
                continue
            hits.sort()
            wind = 0
            for j, (x, d) in enumerate(hits):
                before = wind
                wind += d
                if before == 0 and wind != 0:
                    start = x
                elif before != 0 and wind == 0:
                    add_span(cov, row * w, w, start, x)
    return [c / SS for c in cov]


def add_span(cov, base, w, a, b):
    a, b = max(a, 0.0), min(b, float(w))
    if b <= a:
        return
    i0, i1 = int(a), min(int(b), w - 1)
    if i0 == i1:
        cov[base + i0] += b - a
        return
    cov[base + i0] += (i0 + 1) - a
    for i in range(i0 + 1, i1):
        cov[base + i] += 1.0
    cov[base + i1] += b - i1


def write_tga(path, canvas, bleed=True):
    """32-bit uncompressed true-colour TGA, 8 alpha bits, bottom-left origin (rows bottom to top)."""
    w, h = canvas.w, canvas.h
    assert w & (w - 1) == 0 and h & (h - 1) == 0, f"{path.name}: not a power of two"
    rgba = canvas.rgba_bytes(bleed)
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    body = bytearray()
    for y in range(h - 1, -1, -1):
        row = rgba[y * w * 4 : (y + 1) * w * 4]
        for x in range(w):
            r, g, b, a = row[x * 4 : x * 4 + 4]
            body += bytes((b, g, r, a))
    path.write_bytes(header + bytes(body))
    print(f"wrote {path.relative_to(ROOT)} ({w} x {h})")


def stroke_polyline(points, width):
    """Outline of a two-segment polyline stroked with butt caps and a miter join (SVG defaults)."""
    (ax, ay), (bx, by), (cx, cy) = points
    h = width / 2

    def normal(x0, y0, x1, y1):
        dx, dy = x1 - x0, y1 - y0
        n = (dx * dx + dy * dy) ** 0.5
        return -dy / n * h, dx / n * h

    n1, n2 = normal(ax, ay, bx, by), normal(bx, by, cx, cy)

    def meet(p, d, q, e):  # intersection of p + t*d and q + s*e
        den = d[0] * e[1] - d[1] * e[0]
        t = ((q[0] - p[0]) * e[1] - (q[1] - p[1]) * e[0]) / den
        return p[0] + t * d[0], p[1] + t * d[1]

    d1, d2 = (bx - ax, by - ay), (cx - bx, cy - by)
    left = meet((ax + n1[0], ay + n1[1]), d1, (bx + n2[0], by + n2[1]), d2)
    right = meet((ax - n1[0], ay - n1[1]), d1, (bx - n2[0], by - n2[1]), d2)
    return [
        (ax + n1[0], ay + n1[1]), left, (cx + n2[0], cy + n2[1]),
        (cx - n2[0], cy - n2[1]), right, (ax - n1[0], ay - n1[1]),
    ]


# Header planes from the boards (units, y down). Window: 880 x 56, docked: 380 x 64.
HEADER_WIDE = (880, 56, [
    ((0, 0, 200, 0, 150, 56, 0, 56), "#E8B94B"),
    ((200, 0, 150, 56, 0, 56), "#D9A93A"),
    ((200, 0, 560, 0, 520, 56, 150, 56), "#202125"),
    ((560, 0, 858, 0, 880, 22, 880, 56, 520, 56), "#25262A"),
])
HEADER_NARROW = (380, 64, [
    ((0, 0, 120, 0, 70, 64, 0, 64), "#E8B94B"),
    ((120, 0, 70, 64, 0, 64), "#D9A93A"),
    ((120, 0, 300, 0, 230, 64, 70, 64), "#202125"),
    ((300, 0, 358, 0, 380, 22, 380, 64, 230, 64), "#25262A"),
])


def stroke_segment(x0, y0, x1, y1, width, square=False):
    """A straight line stroked with butt caps (or square caps: extended by half the width)."""
    dx, dy = x1 - x0, y1 - y0
    n = (dx * dx + dy * dy) ** 0.5
    ux, uy = dx / n, dy / n
    h = width / 2
    if square:
        x0, y0, x1, y1 = x0 - ux * h, y0 - uy * h, x1 + ux * h, y1 + uy * h
    nx, ny = -uy * h, ux * h
    return [(x0 + nx, y0 + ny), (x1 + nx, y1 + ny), (x1 - nx, y1 - ny), (x0 - nx, y0 - ny)]


def circle(cx, cy, r, clockwise=True, steps=96):
    import math
    pts = [(cx + r * math.cos(2 * math.pi * i / steps), cy + r * math.sin(2 * math.pi * i / steps))
           for i in range(steps)]
    return pts if clockwise else pts[::-1]


def rect(x0, y0, x1, y1, clockwise=True):
    pts = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    return pts if clockwise else pts[::-1]


def pairs(flat):
    return [(flat[i], flat[i + 1]) for i in range(0, len(flat), 2)]


def header(name, tw, th, spec):
    w, h, planes = spec
    c = Canvas(tw, th)
    for pts, colour in planes:
        c.fill([pairs(pts)], hex_rgb(colour), sx=tw / w, sy=th / h)
    write_tga(MEDIA / name, c)


def svg_path_polygons(d):
    """Absolute M/L/H/V/Z paths (all key-wow.svg uses) as polygons; anything else is an error."""
    tokens = re.findall(r"[MLHVZmlhvz]|-?\d*\.?\d+(?:e-?\d+)?", d)
    polys, cur, cmd, i = [], [], None, 0
    x = y = 0.0
    while i < len(tokens):
        t = tokens[i]
        if t.isalpha():
            if t not in "MLHVZ":
                raise ValueError(f"unsupported path command {t!r}")
            cmd = t
            i += 1
            if cmd == "Z":
                if cur:
                    polys.append(cur)
                cur = []
            continue
        if cmd == "M":
            if cur:
                polys.append(cur)
            x, y = float(tokens[i]), float(tokens[i + 1])
            cur = [(x, y)]
            i += 2
            cmd = "L"  # further pairs after M are line-tos
        elif cmd == "L":
            x, y = float(tokens[i]), float(tokens[i + 1])
            cur.append((x, y))
            i += 2
        elif cmd == "H":
            x = float(tokens[i])
            cur.append((x, y))
            i += 1
        elif cmd == "V":
            y = float(tokens[i])
            cur.append((x, y))
            i += 1
        else:
            raise ValueError("path data before a command")
    if cur:
        polys.append(cur)
    return polys


def render_svg(svg_path, size):
    root = ET.parse(svg_path).getroot()
    ns = "{http://www.w3.org/2000/svg}"
    vb = [float(v) for v in root.get("viewBox").split()]
    if vb[0] != 0 or vb[1] != 0:
        raise ValueError("viewBox must start at 0 0")
    sx, sy = size / vb[2], size / vb[3]
    c = Canvas(size, size)
    for el in root:
        tag = el.tag.replace(ns, "")
        if tag in ("title", "metadata", "desc"):
            continue
        if tag == "polygon":
            nums = [float(v) for v in re.split(r"[\s,]+", el.get("points").strip())]
            polys = [pairs(nums)]
        elif tag == "path":
            polys = svg_path_polygons(el.get("d"))
        else:
            raise ValueError(f"unsupported element <{tag}> in {svg_path.name}")
        if set(el.attrib) - {"points", "d", "fill", "fill-opacity"}:
            raise ValueError(f"unsupported attributes on <{tag}>: {sorted(el.attrib)}")
        c.fill(polys, hex_rgb(el.get("fill")), float(el.get("fill-opacity", "1")), sx, sy)
    return c


def brand_commit(brand):
    try:
        return subprocess.run(["git", "-C", str(brand), "rev-parse", "HEAD"], capture_output=True, text=True,
                              check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--brand", type=Path, default=ROOT.parent / "velikopter-brand",
                    help="velikopter-brand checkout (default: ../velikopter-brand)")
    args = ap.parse_args()
    key = args.brand / "app-keys" / "key-wow.svg"
    if not key.exists():
        sys.exit(f"{key} not found: pass --brand <velikopter-brand checkout>")
    commit = brand_commit(args.brand)
    if not commit or not commit.startswith(BRAND_COMMIT):
        print(f"warning: velikopter-brand is at {commit or 'unknown'}, cw-key-w.tga was made from {BRAND_COMMIT}",
              file=sys.stderr)
    MEDIA.mkdir(parents=True, exist_ok=True)

    c = Canvas(64, 64)
    c.fill([[(0, 0), (0, 64), (64, 64)]], WHITE)
    write_tga(MEDIA / "cw-fold.tga", c)

    c = Canvas(32, 32)
    c.fill([[(16, 0), (32, 16), (16, 32), (0, 16)]], WHITE)
    write_tga(MEDIA / "cw-nokta.tga", c)

    c = Canvas(16, 16)  # viewBox 0 0 8 8 at 2 px per unit
    c.fill([stroke_polyline([(1, 4.2), (3, 6), (7, 1.5)], 1.6)], WHITE, sx=2, sy=2)
    write_tga(MEDIA / "cw-check.tga", c)

    header("cw-header-wide.tga", 1024, 64, HEADER_WIDE)
    header("cw-header-narrow.tga", 512, 64, HEADER_NARROW)

    write_tga(MEDIA / "cw-key-w.tga", render_svg(key, 64))

    caret = 1.6  # the boards' 10 unit caret box on 16 px
    c = Canvas(16, 16)
    c.fill([[(1, 3), (9, 3), (5, 8)]], WHITE, sx=caret, sy=caret)
    write_tga(MEDIA / "cw-down.tga", c)
    c = Canvas(16, 16)
    c.fill([[(1, 7), (5, 2), (9, 7)]], WHITE, sx=caret, sy=caret)
    write_tga(MEDIA / "cw-up.tga", c)
    c = Canvas(16, 16)
    c.fill([[(1, 4.4), (6, 4.4), (6, 5.6), (1, 5.6)], [(5, 2), (9, 5), (5, 8)]], WHITE, sx=caret, sy=caret)
    write_tga(MEDIA / "cw-arrow.tga", c)

    # Header buttons (#153), from the boards' inline SVG icons; the hole of a ring winds the other way.
    c = Canvas(32, 32)  # viewBox 0 0 16 16
    gear = [circle(8, 8, 2.5 + 0.8), circle(8, 8, 2.5 - 0.8, clockwise=False)]
    for x0, y0, x1, y1 in ((8, 1.5, 8, 4), (8, 12, 8, 14.5), (1.5, 8, 4, 8), (12, 8, 14.5, 8),
                           (3.4, 3.4, 5.2, 5.2), (10.8, 10.8, 12.6, 12.6), (3.4, 12.6, 5.2, 10.8),
                           (10.8, 5.2, 12.6, 3.4)):
        gear.append(stroke_segment(x0, y0, x1, y1, 1.6))
    c.fill(gear, WHITE, sx=2, sy=2)
    write_tga(MEDIA / "cw-gear.tga", c)
    c = Canvas(32, 32)  # viewBox 0 0 14 14: rect 1.5 2 11 10, stroke 1.4; the left 4 also filled
    h = 0.7
    c.fill([rect(1.5 - h, 2 - h, 12.5 + h, 12 + h), rect(1.5 + h, 2 + h, 12.5 - h, 12 - h, clockwise=False),
            rect(1.5 - h, 2 - h, 5.5 + h, 12 + h)], WHITE, sx=32 / 14, sy=32 / 14)
    write_tga(MEDIA / "cw-dock.tga", c)
    c = Canvas(32, 32)  # viewBox 0 0 14 14: rect 1.5 2 11 10 and M1.5 5h11, stroke 1.4 (#161)
    c.fill([rect(1.5 - h, 2 - h, 12.5 + h, 12 + h), rect(1.5 + h, 2 + h, 12.5 - h, 12 - h, clockwise=False),
            rect(1.5 - h, 5 - h, 12.5 + h, 5 + h)], WHITE, sx=32 / 14, sy=32 / 14)
    write_tga(MEDIA / "cw-undock.tga", c)
    c = Canvas(32, 32)  # viewBox 0 0 12 12: M2 2l8 8M10 2l-8 8, stroke 1.6, square caps
    c.fill([stroke_segment(2, 2, 10, 10, 1.6, square=True), stroke_segment(10, 2, 2, 10, 1.6, square=True)],
           WHITE, sx=32 / 12, sy=32 / 12)
    write_tga(MEDIA / "cw-close.tga", c)


if __name__ == "__main__":
    main()
