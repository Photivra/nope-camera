#!/usr/bin/env python3
"""Makes the site's two Inter files from the Inter variable font (a maintainer tool).

Not part of the build: the outputs are committed in site/assets/fonts/, so the build needs no
font tools. Run it again only when the character list (charset.txt) or the Inter version changes.

Requires fontTools and brotli (pip install fonttools brotli), and the variable Inter WOFF2 from
@fontsource-variable/inter (SIL Open Font License 1.1), for example
files/inter-latin-wght-normal.woff2 from that npm package.

    python3 site/tools/make-fonts.py path/to/inter-latin-wght-normal.woff2 [path/to/Arial.ttf]

Given Arial too, it prints the fallback font's size-adjust and ascent and descent overrides that
site/styles/site.css uses, so swapping the fallback for Inter moves nothing.

Writes:
- inter-400.woff2: the regular weight (wght 400), the body text; preloaded by every page.
- inter-600-700.woff2: wght 600 to 700, a variable range, for headings and labels.
Each keeps the copyright, license and version names, and only the characters in charset.txt.
"""
import pathlib
import sys

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

HERE = pathlib.Path(__file__).resolve().parent
FONTS = HERE.parent / "assets" / "fonts"


def code_points():
    points = []
    for line in (FONTS / "charset.txt").read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        first, _, last = line.removeprefix("U+").partition("-")
        start = int(first, 16)
        end = int(last, 16) if last else start
        points.extend(range(start, end + 1))
    return points


def make(source, axis_limits, name):
    font = TTFont(source)
    font = instancer.instantiateVariableFont(font, axis_limits)
    options = subset.Options()
    options.flavor = "woff2"
    options.hinting = False
    options.desubroutinize = True
    options.name_IDs = [0, 1, 2, 3, 4, 5, 6, 13, 14]
    options.layout_features = ["kern", "liga", "calt", "case", "ccmp", "locl", "mark", "mkmk"]
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=code_points())
    subsetter.subset(font)
    out = FONTS / name
    font.flavor = "woff2"
    font.save(out)
    print(f"{out.name}: {out.stat().st_size} bytes")


def fallback_metrics(inter_path, arial_path):
    def average_width(font):
        cmap, metrics = font.getBestCmap(), font["hmtx"]
        widths = [metrics[cmap[ord(c)]][0] for c in "abcdefghijklmnopqrstuvwxyz "]
        return sum(widths) / len(widths) / font["head"].unitsPerEm

    inter = instancer.instantiateVariableFont(TTFont(inter_path), {"wght": 400})
    ratio = average_width(inter) / average_width(TTFont(arial_path))
    em = inter["head"].unitsPerEm
    print(f"size-adjust: {ratio * 100:.2f}%; ascent-override: {inter['hhea'].ascent / em / ratio * 100:.2f}%; "
          f"descent-override: {-inter['hhea'].descent / em / ratio * 100:.2f}%; line-gap-override: 0%")


def main():
    source = sys.argv[1]
    make(source, {"wght": 400}, "inter-400.woff2")
    make(source, {"wght": (600, 700)}, "inter-600-700.woff2")
    if len(sys.argv) > 2:
        fallback_metrics(source, sys.argv[2])


if __name__ == "__main__":
    main()
