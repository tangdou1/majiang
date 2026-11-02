#!/usr/bin/env python3
"""Subset NotoSansSC.ttf and NotoSerifSC.ttf to only the glyphs the game uses.

Collects characters from:
  - All .gd script files (Chinese text, UI labels, etc.)
  - ASCII printable range (scores, digits, punctuation)
  - Tile.NUMBER_NAMES + suit chars (already in .gd files, but explicit)
  - Common CJK punctuation

Usage:
  /home/user/.venv-bgm/bin/python tools/subset_fonts.py
"""

import re
import sys
from pathlib import Path
from fontTools import subset

ROOT = Path(__file__).resolve().parent.parent
FONTS_DIR = ROOT / "assets" / "fonts"
SCRIPTS_DIR = ROOT / "scripts"

# ASCII printable (digits, letters, common punctuation)
ASCII_CHARS = "".join(chr(c) for c in range(0x20, 0x7F))

# Common CJK punctuation and symbols that might appear in UI
CJK_PUNCT = "·—–…「」『』【】、。，；：？！（）、《》〈〉“”‘’ \t\n"

# Digits and scoring symbols
SCORE_CHARS = "0123456789+-×÷=<>"

def collect_chars_from_gd_files():
    """Scan all .gd files for non-ASCII characters."""
    chars = set()
    for gd_file in SCRIPTS_DIR.rglob("*.gd"):
        try:
            text = gd_file.read_text(encoding="utf-8")
        except Exception:
            continue
        # Find all non-ASCII characters
        for ch in text:
            if ord(ch) > 127:
                chars.add(ch)
    return chars


def collect_tile_chars():
    """Tile number names and suit characters."""
    return set("一二三四五六七八九万筒条")


def main():
    chars = set()

    # ASCII
    chars.update(ASCII_CHARS)
    # CJK punctuation
    chars.update(CJK_PUNCT)
    # Score symbols
    chars.update(SCORE_CHARS)
    # Tile chars
    chars.update(collect_tile_chars())
    # All non-ASCII chars from .gd files
    chars.update(collect_chars_from_gd_files())

    # Filter: keep only characters that exist in the font (remove surrogates, etc.)
    valid_chars = []
    for ch in sorted(chars):
        codepoint = ord(ch)
        # Skip control characters and surrogates
        if codepoint < 0x20 or (0xD800 <= codepoint <= 0xDFFF):
            continue
        valid_chars.append(ch)

    text = "".join(valid_chars)
    print(f"Collected {len(valid_chars)} unique characters")
    print(f"Preview: {text[:80]}...")

    # Subset each font
    for font_name in ["NotoSansSC.ttf", "NotoSerifSC.ttf"]:
        font_path = FONTS_DIR / font_name
        if not font_path.exists():
            print(f"WARNING: {font_path} not found, skipping")
            continue

        print(f"\nSubsetting {font_name}...")

        # Use fonttools subset
        font = subset.load_font(str(font_path), subset.Options(
            notdef_outline=True,
            recalc_bounds=True,
            drop_tables=["DSIG", "GPOS", "GSUB", "GDEF", "BASE"],
        ))

        # Keep only the glyphs we need
        subsetter = subset.Subsetter(subset.Options(
            notdef_outline=True,
            recalc_bounds=True,
            drop_tables=["DSIG", "GPOS", "GSUB", "GDEF", "BASE"],
        ))
        subsetter.populate(text=text)
        subsetter.subset(font)

        # Save subsetted font (overwrite original)
        font.save(str(font_path))
        print(f"  {font_name}: {len(font.getGlyphOrder())} glyphs (was larger)")

    print("\nDone! Fonts subsetted in place.")


if __name__ == "__main__":
    main()
