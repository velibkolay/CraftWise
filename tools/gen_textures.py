#!/usr/bin/env python3
"""Pre-render the Classic skin's noise textures into bitmap tiles for wow.velikopter.com (#132).

The sources are our own SVG drawings in web/public/tex/ (stone.svg, grain.svg, parchment.svg, haze.svg, all
feTurbulence noise) and the torn parchment edge that item.html used to draw with an SVG filter. Browsers re-run
those filters on every repaint, which made the Classic skin lag; the site now uses the bitmaps written here.
Chromium draws them exactly as the page drew the SVGs, so the look stays the same:

  stone, grain        the SVG tile as is, 1x and 2x (image-set in site.css)
  haze                at half size (it is very soft), drawn at 900 x 600
  parchment           the tile with the torn filter's displacement baked in (the wavy fibres)
  torn-{t,b,l,r}      alpha masks of the torn edge, one per side, 2x, lossless
  rim-{t,b,l,r}       the parchment's dark rim and inner shades along the torn edge, one per side, 2x, lossless

The torn filter's noise is made periodic (stitchTiles over PERIOD, then feTile) so the tiles and edge strips
repeat without seams. Needs Playwright for Python with Chromium:
  pip install playwright && python3 -m playwright install chromium

Usage: python3 tools/gen_textures.py
"""

import base64
from pathlib import Path

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent
TEX = ROOT / "web" / "public" / "tex"

QUALITY = 0.86  # WebP quality of the tiles (noise: lower settings show as blotches); the edge strips are lossless (1)
PERIOD = 480  # parchment tile and torn-noise period (px)
REACH = 6  # how far the torn edge may reach outside the parchment's box (site.css: inset -6px)
TEAR = 40  # depth of the mask strips (px): the torn contour
DEPTH = 100  # depth of the rim strips (px): the 2 px rim and the 14 px and 60 px shades
SIZE = 3 * PERIOD  # rendered parchment; the tiles are cut from its middle, away from the render's own edges
OFF = 60  # where the rendered box sits on the page, so the edge's outward reach is on screen
# The noise is anchored at the box's top left, where its lattice damps it: the top and left edges tear less than
# the bottom and right ones, which fall anywhere. Those two are cut from a box this much larger, off the lattice.
FAR = 10

# item.html's former #torn filter, with its noise stitched over one PERIOD and tiled.
TORN = (
    f'<svg width="0" height="0" style="position:absolute"><filter id="torn" filterUnits="userSpaceOnUse" '
    f'x="-{OFF}" y="-{OFF}" width="{SIZE + 2 * OFF}" height="{SIZE + 2 * OFF}">'
    f'<feTurbulence type="fractalNoise" baseFrequency="0.035" numOctaves="3" seed="4" stitchTiles="stitch" '
    f'x="0" y="0" width="{PERIOD}" height="{PERIOD}" result="n"/><feTile in="n" result="t"/>'
    '<feDisplacementMap in="SourceGraphic" in2="t" scale="10" xChannelSelector="R" yChannelSelector="G"/>'
    "</filter></svg>"
)
# The parchment's inset shades; they follow the torn edge.
RIM = "inset 0 0 0 2px rgba(70, 36, 12, 0.9), inset 0 0 14px rgba(90, 48, 18, 0.75), inset 0 0 60px rgba(120, 70, 30, 0.45)"

ENCODE = """async ([png, type, q]) => {
	const img = new Image();
	img.src = "data:image/png;base64," + png;
	await img.decode();
	const c = document.createElement("canvas");
	c.width = img.naturalWidth;
	c.height = img.naturalHeight;
	c.getContext("2d").drawImage(img, 0, 0);
	const blob = await new Promise((r) => c.toBlob(r, type, q));
	const buf = new Uint8Array(await blob.arrayBuffer());
	let s = "";
	for (let i = 0; i < buf.length; i += 0x8000) s += String.fromCharCode(...buf.subarray(i, i + 0x8000));
	return btoa(s);
}"""


def svg_url(name):
    data = (TEX / f"{name}.svg").read_bytes()
    return "url(data:image/svg+xml;base64," + base64.b64encode(data).decode() + ")"


def page_html(body):
    return f'<!doctype html><html><body style="margin:0;background:transparent">{body}</body></html>'


def main():
    written = []
    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        encoder = browser.new_page()

        def save(name, png, quality):
            out = base64.b64decode(encoder.evaluate(ENCODE, [base64.b64encode(png).decode(), "image/webp", quality]))
            (TEX / name).write_bytes(out)
            written.append(f"{name} {len(out)} bytes")

        for scale in (1, 2):
            ctx = browser.new_context(viewport={"width": SIZE + 2 * OFF, "height": SIZE + 2 * OFF}, device_scale_factor=scale)
            page = ctx.new_page()
            suffix = "" if scale == 1 else "@2x"

            # stone and grain: the SVG tile as the page drew it
            for name, w, h in (("stone", 360, 360), ("grain", 400, 60)):
                page.set_content(page_html(f'<div style="width:{w}px;height:{h}px;background:{svg_url(name)}"></div>'))
                save(f"{name}{suffix}.webp", page.screenshot(clip={"x": 0, "y": 0, "width": w, "height": h}, omit_background=True), QUALITY)

            if scale == 1:
                # haze: soft enough to store at half size
                page.set_content(page_html(f'<div style="width:450px;height:300px;background:{svg_url("haze")} 0 0 / 450px 300px"></div>'))
                save("haze.webp", page.screenshot(clip={"x": 0, "y": 0, "width": 450, "height": 300}, omit_background=True), QUALITY)

            def render(style, size=SIZE):
                page.set_content(page_html(TORN + f'<div style="position:absolute;left:{OFF}px;top:{OFF}px;width:{size}px;height:{size}px;filter:url(#torn);{style}"></div>'))
                return lambda x, y, w, h: page.screenshot(clip={"x": OFF + x, "y": OFF + y, "width": w, "height": h}, omit_background=True)

            if scale == 1:
                # parchment: the texture with the torn displacement baked in, one period from the middle
                # (soft enough that 2x screens get the same tile: a 2x one would be 0.6 MB, nearly all alpha)
                shot = render(f"background:{svg_url('parchment')}")
                save("parchment.webp", shot(PERIOD, PERIOD, PERIOD, PERIOD), QUALITY)
            else:
                # edge strips: one period along each side, from REACH outside the box to inside it
                far = SIZE + FAR

                def sides(d):
                    return {
                        "t": (SIZE, (PERIOD, -REACH, PERIOD, d)),
                        "l": (SIZE, (-REACH, PERIOD, d, PERIOD)),
                        "b": (far, (PERIOD, far + REACH - d, PERIOD, d)),
                        "r": (far, (far + REACH - d, PERIOD, d, PERIOD)),
                    }

                for prefix, style, d in (("torn", "background:#000;border-radius:6px", TEAR), ("rim", f"border-radius:6px;box-shadow:{RIM}", DEPTH)):
                    for side, (size, clip) in sides(d).items():
                        save(f"{prefix}-{side}.webp", render(style, size)(*clip), 1)
            ctx.close()
        browser.close()
    print("\n".join(written))


if __name__ == "__main__":
    main()
