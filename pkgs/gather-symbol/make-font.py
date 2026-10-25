"""The Gather logo as a one-glyph font; see default.nix.

Usage: make-font.py SVG OUTPUT.ttf
"""

import sys

import fontforge

CODEPOINT = 0xFFF00

svg, out = sys.argv[1], sys.argv[2]

font = fontforge.font()
font.familyname = "Gather Symbol"
font.fontname = "GatherSymbol"
font.fullname = "Gather Symbol"
font.encoding = "UnicodeFull"
# SF Pro's em, which the logo used to be patched into: importOutlines fits
# the SVG to ascent + descent, so it comes out the size it was there
font.em = 2048
font.ascent = 1638
font.descent = 410

glyph = font.createChar(CODEPOINT, "gather")
glyph.importOutlines(svg)
# As wide as the logo, with no side bearings, like Symbols Nerd Font's icons
# beside it (waybar spaces them out)
xmin, _, xmax, _ = glyph.boundingBox()
glyph.transform((1, 0, 0, 1, -xmin, 0))
glyph.width = round(xmax - xmin)

font.generate(out)
