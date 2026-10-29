#!/usr/bin/env python3
"""Draws the Engineer's three wall sprites: assets/props/temp_wall_1.png .. temp_wall_3.png.

One per level, so how tough a wall is can be read off it from across the arena:

  1  a wooden barricade — planks and two braces. What the Engineer has always built.
  2  stone bricks banded in iron.
  3  riveted steel with gold corners and a gold emblem.

They are drawn on a 32x32 grid and doubled to 64x64 with nearest-neighbour so they sit
beside the 64px crate and stone sprites with the same chunky pixels. (Cracks are not
here: a damaged wall shows them on top, drawn by TempWall.gd, so one sprite per level
is all there is.)

Run from anywhere; it finds the project from its own location. Godot needs a re-import
afterwards (open the editor once, or `godot --headless --import`).
"""
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "assets", "props"))


def rect(d, x0, y0, x1, y1, fill):
    d.rectangle([x0, y0, x1, y1], fill=fill)


def frame(d, outline, top_fill, top_light):
    """The cube's silhouette: a dark outline, a lit top face and a seam under it."""
    rect(d, 2, 2, 29, 30, outline)
    rect(d, 3, 3, 28, 7, top_fill)
    rect(d, 3, 4, 28, 4, top_light)
    rect(d, 3, 8, 28, 8, outline)


def level_1():
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    outline = (52, 32, 18, 255)
    frame(d, outline, (196, 140, 78, 255), (226, 180, 112, 255))
    # vertical planks, alternating tones, with a dark seam between each
    plank_a, plank_b, seam = (152, 100, 52, 255), (172, 116, 62, 255), (104, 64, 32, 255)
    x = 3
    tone = 0
    while x <= 28:
        rect(d, x, 9, min(x + 4, 28), 29, plank_a if tone % 2 == 0 else plank_b)
        if x + 5 <= 28:
            rect(d, x + 5, 9, x + 5, 29, seam)
        x += 6
        tone += 1
    # two braces across, with nails
    brace, brace_edge = (112, 72, 36, 255), (74, 46, 22, 255)
    for y in (12, 23):
        rect(d, 3, y, 28, y + 2, brace)
        rect(d, 3, y + 2, 28, y + 2, brace_edge)
        for nx in (5, 26):
            d.point((nx, y + 1), fill=(222, 214, 196, 255))
    return img


def level_2():
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    outline = (28, 29, 36, 255)
    frame(d, outline, (152, 154, 162, 255), (190, 192, 200, 255))
    stone, stone_hi, mortar = (124, 126, 134, 255), (146, 148, 156, 255), (86, 88, 98, 255)
    rect(d, 3, 9, 28, 29, stone)
    # courses of bricks, each row offset from the one above
    for row, y in enumerate(range(11, 28, 5)):
        rect(d, 3, y, 28, y, mortar)
        offset = 0 if row % 2 == 0 else 4
        for x in range(3 + offset, 29, 8):
            rect(d, x, y + 1, x, y + 4, mortar)
        for x in range(4, 28, 8):
            d.point((x + offset if x + offset < 28 else x, y + 1), fill=stone_hi)
    # iron bands top and bottom, riveted
    band, band_hi = (60, 64, 76, 255), (92, 98, 114, 255)
    for y in (9, 27):
        rect(d, 3, y, 28, y + 2, band)
        rect(d, 3, y, 28, y, band_hi)
        for rx in range(6, 28, 6):
            d.point((rx, y + 1), fill=(178, 184, 198, 255))
    return img


def level_3():
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    outline = (22, 24, 34, 255)
    frame(d, outline, (198, 208, 224, 255), (240, 246, 254, 255))
    steel, steel_hi, steel_lo = (150, 162, 186, 255), (216, 226, 242, 255), (100, 112, 138, 255)
    rect(d, 3, 9, 28, 29, steel)
    # a bevelled plate inside the face
    rect(d, 5, 11, 26, 27, (174, 186, 208, 255))
    rect(d, 5, 11, 26, 11, steel_hi)
    rect(d, 5, 11, 5, 27, steel_hi)
    rect(d, 5, 27, 26, 27, steel_lo)
    rect(d, 26, 11, 26, 27, steel_lo)
    # gold corner brackets
    gold, gold_hi, gold_lo = (226, 178, 50, 255), (255, 224, 120, 255), (150, 110, 24, 255)
    for cx, cy, sx, sy in ((3, 9, 1, 1), (28, 9, -1, 1), (3, 29, 1, -1), (28, 29, -1, -1)):
        for i in range(5):
            d.point((cx + sx * i, cy), fill=gold)
            d.point((cx, cy + sy * i), fill=gold)
        d.point((cx, cy), fill=gold_hi)
    # the emblem: a gold diamond with a lit edge
    mid_x, mid_y = 15, 19
    for dy in range(-5, 6):
        w = 5 - abs(dy)
        rect(d, mid_x - w, mid_y + dy, mid_x + w, mid_y + dy, gold)
        d.point((mid_x - w, mid_y + dy), fill=gold_hi)
        d.point((mid_x + w, mid_y + dy), fill=gold_lo)
    # rivets
    for rx, ry in ((8, 14), (23, 14), (8, 24), (23, 24)):
        d.point((rx, ry), fill=(240, 244, 252, 255))
        d.point((rx + 1, ry + 1), fill=steel_lo)
    return img


def main():
    for n, build in enumerate((level_1, level_2, level_3), start=1):
        small = build()
        big = small.resize((64, 64), Image.NEAREST)
        path = os.path.join(OUT, "temp_wall_%d.png" % n)
        big.save(path)
        print("wrote", path)


if __name__ == "__main__":
    main()
