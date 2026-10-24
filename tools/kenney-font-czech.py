#!/usr/bin/env python3
"""Adds the Czech letters with a caron (and a real ring on Ů) to a Kenney font.

Kenney Fonts (CC0, https://kenney.nl/assets/kenney-fonts) carry acute accents but no
caron, and their Ů has no ring. The fonts are capitals only, so the lowercase letters are
drawn the same. The caron is a chevron in the font's own geometry (the stroke and band of
its other accents, which are flat bars, so a turned circumflex would read as a macron); the
ring is the one of Å. Both are copied as outlines above the base letter, centred on it.

    tools/kenney-font-czech.py "Kenney Future.ttf" assets/kenney/fonts/KenneyFutureCS.ttf "Kenney Future CS"
"""

import argparse
import unicodedata

from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.ttLib import TTFont

CARON = "ČčĎďĚěŇňŘřŠšŤťŽž"
RING = "Ůů"


def contours(font, name):
    """The glyph's outline split into contours, each a list of pen operations."""
    pen = RecordingPen()
    font.getGlyphSet()[name].draw(pen)
    result, current = [], []
    for operation in pen.value:
        current.append(operation)
        if operation[0] in ("closePath", "endPath"):
            result.append(current)
            current = []
    return result


def bounds(font, operations_list):
    pen = BoundsPen(font.getGlyphSet())
    for operations in operations_list:
        replay(operations, pen)
    return pen.bounds


def replay(operations, pen):
    for name, arguments in operations:
        getattr(pen, name)(*arguments)


def chevron(font, cap_height):
    """A V as wide as the circumflex of Â and as tall as the font's accent band."""
    left, bottom, right, top = bounds(font, accent(font, "Acircumflex", cap_height))
    stroke = top - bottom
    middle = (left + right) / 2
    left, right = left + stroke, right - stroke
    pen = RecordingPen()
    pen.moveTo((left, top))
    pen.lineTo((middle - stroke / 2, bottom))
    pen.lineTo((middle + stroke / 2, bottom))
    pen.lineTo((right, top))
    pen.lineTo((right - stroke, top))
    pen.lineTo((middle, bottom + stroke / 2))
    pen.lineTo((left + stroke, top))
    pen.closePath()
    return [pen.value]


def accent(font, source, cap_height):
    """The contours of `source` that lie wholly above the capital height."""
    parts = [c for c in contours(font, source) if bounds(font, [c])[1] >= cap_height]
    if not parts:
        raise SystemExit(f"{source} has no accent above {cap_height}")
    return parts


def build(font, base_char, accent_parts):
    cmap = font.getBestCmap()
    base = cmap[ord(unicodedata.normalize("NFD", base_char)[0].upper())]
    base_parts = contours(font, base)
    base_box = bounds(font, base_parts)
    accent_box = bounds(font, accent_parts)
    dx = (base_box[0] + base_box[2]) / 2 - (accent_box[0] + accent_box[2]) / 2
    pen = TTGlyphPen(font.getGlyphSet())
    for part in base_parts:
        replay(part, pen)
    target = TransformPen(pen, (1, 0, 0, 1, dx, 0))
    for part in accent_parts:
        replay(part, target)
    return pen.glyph(), font["hmtx"][base]


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("source")
    parser.add_argument("output")
    parser.add_argument("family")
    args = parser.parse_args()

    font = TTFont(args.source)
    cap_height = font["glyf"][font.getBestCmap()[ord("A")]].yMax
    caron = chevron(font, cap_height)
    ring = accent(font, "Aring", cap_height)

    new_glyphs = {}
    for chars, parts in ((CARON, caron), (RING, ring)):
        for char in chars:
            new_glyphs[char] = build(font, char, parts)

    order = font.getGlyphOrder()
    cmap_tables = [t for t in font["cmap"].tables if t.isUnicode()]
    for char, (glyph, metrics) in new_glyphs.items():
        name = font.getBestCmap().get(ord(char)) or f"uni{ord(char):04X}"
        if name not in order:
            order.append(name)
        font["glyf"][name] = glyph
        font["hmtx"][name] = metrics
        for table in cmap_tables:
            table.cmap[ord(char)] = name
    font.setGlyphOrder(order)
    font["maxp"].numGlyphs = len(order)
    if "post" in font and font["post"].formatType == 2.0:
        font["post"].extraNames = []
        font["post"].mapping = {}

    # A distinct family name, so the derived font is never confused with Kenney's own.
    for record in font["name"].names:
        if record.nameID in (1, 4, 16):
            record.string = args.family
        elif record.nameID == 6:
            record.string = args.family.replace(" ", "")
    font.save(args.output)


if __name__ == "__main__":
    main()
