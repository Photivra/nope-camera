#!/usr/bin/env python3
"""Makes the "nope." wordmark as outlines from Inter Bold (a maintainer tool).

Not part of the build: the output, site/assets/wordmark.svg, is a committed brand file (not
covered by the GPL; see TRADEMARKS.md). Inter is under the SIL Open Font License 1.1, which
allows converting its letters to outlines for a logo (AGENTS.md, "Name and wordmark").

Requires fontTools and brotli (pip install fonttools brotli), and Inter Bold, for example
files/inter-latin-700-normal.woff2 from the @fontsource/inter npm package.

    python3 site/tools/make-wordmark.py path/to/inter-latin-700-normal.woff2

The letters are #EDEDEE (NopeColor.mark) and the period #40C8E0 (NopeColor.markPeriod), both
sRGB, always drawn on black. Tracking is -0.045 em, as in the design figures
(docs/design/nope-site.md, 8.3). No kerning is applied.
"""
import pathlib
import sys

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "wordmark.svg"
MARK = "#EDEDEE"
PERIOD = "#40C8E0"
TRACKING_EM = -0.045


def main():
    font = TTFont(sys.argv[1])
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    upm = font["head"].unitsPerEm
    version = font["name"].getDebugName(5)
    tracking = TRACKING_EM * upm
    x = 0.0
    placed = []
    for char in "nope.":
        name = cmap[ord(char)]
        placed.append((char, name, x))
        x += glyphs[name].width + tracking
    # Bounds of the outlines in font units (y up).
    bounds = BoundsPen(glyphs)
    for _, name, dx in placed:
        glyphs[name].draw(TransformPen(bounds, (1, 0, 0, 1, dx, 0)))
    x_min, y_min, x_max, y_max = bounds.bounds
    width, height = x_max - x_min, y_max - y_min
    paths = []
    for char, name, dx in placed:
        pen = SVGPathPen(glyphs, ntos=lambda v: f"{v:.1f}".rstrip("0").rstrip("."))
        # Flip y and move the box's top left corner to 0,0.
        glyphs[name].draw(TransformPen(pen, (1, 0, 0, -1, dx - x_min, y_max)))
        paths.append((PERIOD if char == "." else MARK, pen.getCommands()))
    letters = " ".join(d for color, d in paths if color == MARK)
    period = " ".join(d for color, d in paths if color == PERIOD)
    svg = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        "<!-- The Photivra Nope Camera wordmark, \"nope.\". A brand file of Shackelford Creative, LLC: "
        "not covered by the GNU General Public License; all rights reserved (TRADEMARKS.md). "
        f"Letters converted to outlines from Inter Bold ({version}), Copyright 2016 The Inter Project "
        "Authors, SIL Open Font License 1.1. Made by site/tools/make-wordmark.py. -->\n"
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width:.0f} {height:.0f}" '
        f'width="{width / upm * 100:.2f}" height="{height / upm * 100:.2f}">'
        f'<path fill="{MARK}" d="{letters}"/>'
        f'<path fill="{PERIOD}" d="{period}"/>'
        "</svg>\n"
    )
    OUT.write_text(svg)
    print(f"{OUT.name}: {len(svg)} bytes, {width / upm:.4f} em wide, {height / upm:.4f} em high")


if __name__ == "__main__":
    main()
