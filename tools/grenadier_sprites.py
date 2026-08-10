#!/usr/bin/env python3
"""Draw the Grenadier off the Miner's frames.

Same approach as the Magnet/Miner re-skins: the base sheet is another
character's, recoloured, with the kit that names the character painted on
top. Here that kit is a launcher big enough to change the silhouette — the
Grenadier has to be told apart from the Miner it is built on at lobby size,
where two soldiers on one body would otherwise read as the same character
drawn twice. The re-skin does the rest: olive drab instead of grey, a plain
gunmetal helmet instead of the camo one, amber goggles instead of teal.

Everything is anchored to the helmet's own bounding box in each frame, so the
weapon rides the walk cycle's bob instead of floating at a fixed height.

The recolour works on *regions and rules* rather than on a table of source
colours, because the Miner's sheet isn't internally consistent: its walk
frames are drawn with a near-white trouser palette its idle frame doesn't
have (a leftover from the Parkour Runner's kit it was recoloured from), and
they carry a whole second set of anti-aliased in-between tones besides. A
lookup table would have caught the idle frame and left the walk cycle
flickering between two different characters from the waist down. The legs are
therefore normalised *per frame* — light half, dark half — so idle and walk
land on the same two tones whatever they started as.
"""
import math
import os

from PIL import Image, ImageDraw

SRC = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "characters")
DIRS = ["south", "north", "east", "west"]

# The Miner's camo helmet, minus the tones it shares with boots and belt —
# used only to locate the head, so a couple of missing helmet shades matter
# less than a stray body pixel dragging the anchor down.
HELMET_TONES = {
    (52, 58, 38), (78, 88, 54), (43, 48, 31), (64, 73, 45),
    (250, 230, 187), (248, 237, 222),
}
HEAD_BOTTOM = 22  # the head never reaches below this row in any frame
WAIST = 41        # torso above, legs below

TUBE = (62, 66, 70, 255)
TUBE_LIT = (104, 110, 116, 255)
TUBE_DARK = (32, 35, 39, 255)
BORE = (22, 24, 27, 255)
BAND = (188, 132, 48, 255)
GRIP = (74, 50, 36, 255)

TROUSERS = ((86, 78, 56), (60, 55, 40))  # light half, dark half

# Per direction: butt and muzzle as offsets from the helmet's (centre x, top
# y). The tube is always aimed up and forward — the whole point of the weapon
# is that it lobs over the wall in front of it, and a tube held level would
# say the opposite.
LAUNCHER = {
    # Facing us: shouldered across the chest, muzzle out past the far shoulder.
    "south": {"butt": (-10, 34), "muzzle": (13, 13), "half": 4},
    # Facing away: the same weapon seen from behind, so it sits shorter on the
    # canvas.
    "north": {"butt": (-9, 31), "muzzle": (11, 12), "half": 4},
    "east": {"butt": (-6, 32), "muzzle": (17, 11), "half": 4},
    "west": {"butt": (6, 32), "muzzle": (-17, 11), "half": 4},
}


def lum(p):
    return (p[0] * 299 + p[1] * 587 + p[2] * 114) / 1000.0


def is_kit(p):
    """Grey (shirt, and the walk cycle's near-white trousers) or blue-grey
    (the idle frame's trousers). Skin, hair, boots and the belt are all warm
    or brown and fall outside both tests."""
    r, g, b = p[0], p[1], p[2]
    grey = max(r, g, b) - min(r, g, b) <= 30
    blue = b >= r + 8 and b >= g + 5
    return grey or blue


def is_camo(p):
    """The helmet's greens *and* its tan blotches, which are warm enough to be
    mistaken for the hair under it. Two tests separate them: hair is redder
    (r - g around 40 against camo's under 20) and, where it isn't, it is far
    less green (g - b of 3-7 against camo's 17-34). Both are needed — the
    darkest hair passes the first test, which is what turned the whole back of
    the north-facing head into helmet."""
    r, g, b = p[0], p[1], p[2]
    return r - g <= 20 and g - b >= 8 and lum(p) < 120


def is_visor(p):
    """The goggle band, including its pale green highlights: green-dominant,
    but never as blue-starved as the camo it sits under."""
    r, g, b = p[0], p[1], p[2]
    return g >= r + 10 and b >= r - 10


def ramp(l, lo, hi):
    """A colour l/255 of the way along the lo->hi ramp."""
    t = max(0.0, min(1.0, l / 255.0))
    return tuple(round(lo[i] + (hi[i] - lo[i]) * t) for i in range(3))


def head_anchor(im):
    """(centre x, top y) of the helmet in this frame."""
    px = im.load()
    xs, ys = [], []
    for y in range(min(HEAD_BOTTOM, im.height)):
        for x in range(im.width):
            p = px[x, y]
            if p[3] > 0 and p[:3] in HELMET_TONES:
                xs.append(x)
                ys.append(y)
    return (min(xs) + max(xs)) // 2, min(ys)


def recolor(im):
    px = im.load()
    # Legs first: the split point is whatever this frame's own trousers make
    # it, which is what keeps the idle frame and the walk cycle on the same
    # two tones despite being drawn from different palettes.
    leg_lums = []
    for y in range(WAIST, im.height):
        for x in range(im.width):
            p = px[x, y]
            if p[3] > 0 and is_kit(p):
                leg_lums.append(lum(p))
    leg_lums.sort()
    split = leg_lums[len(leg_lums) // 2] if leg_lums else 0.0

    for y in range(im.height):
        for x in range(im.width):
            p = px[x, y]
            if p[3] == 0:
                continue
            if y < HEAD_BOTTOM:
                if is_visor(p):
                    px[x, y] = ramp(lum(p) * 1.6, (110, 64, 16), (245, 205, 120)) + (p[3],)
                elif is_camo(p):
                    px[x, y] = ramp(lum(p) * 2.4, (40, 43, 46), (108, 114, 120)) + (p[3],)
            elif is_kit(p):
                if y >= WAIST:
                    px[x, y] = (TROUSERS[0] if lum(p) >= split else TROUSERS[1]) + (p[3],)
                else:
                    px[x, y] = ramp(lum(p) * 1.15, (46, 50, 34), (176, 184, 128)) + (p[3],)


def draw_launcher(im, direction, anchor):
    spec = LAUNCHER[direction]
    cx, top = anchor
    bx, by = cx + spec["butt"][0], top + spec["butt"][1]
    mx, my = cx + spec["muzzle"][0], top + spec["muzzle"][1]
    half = spec["half"]
    d = ImageDraw.Draw(im)

    length = math.hypot(mx - bx, my - by)
    ux, uy = (mx - bx) / length, (my - by) / length  # along the barrel
    nx, ny = -uy, ux                                 # across it

    def along(t, across=0.0):
        return (round(bx + ux * t + nx * across), round(by + uy * t + ny * across))

    # Pistol grip, drawn first so the tube sits over the top of it.
    gx, gy = along(length * 0.34)
    d.line([(gx, gy), (gx, gy + 5)], fill=GRIP, width=3)

    # The tube: a dark silhouette with a lit top edge, which is all the
    # roundness a 68px sprite has room for.
    d.line([(bx, by), (mx, my)], fill=TUBE_DARK, width=half * 2 + 2)
    d.line([(bx, by), (mx, my)], fill=TUBE, width=half * 2)
    d.line([along(2, -half + 1), along(length - 2, -half + 1)], fill=TUBE_LIT, width=1)

    # Warm band two thirds down and a blocky sight above it: both exist to
    # break a long grey bar up into something that reads as a weapon.
    d.line([along(length * 0.62, -half), along(length * 0.62, half)], fill=BAND, width=2)
    sx, sy = along(length * 0.5, -half - 1)
    d.rectangle([sx - 1, sy - 2, sx + 1, sy], fill=TUBE_DARK)

    # Flared muzzle: the widest part of the weapon and the end the eye should
    # land on, so it gets the strongest shape on the sprite. A cone rather
    # than a wider bar — the flare is what says shells leave this thing lobbing
    # rather than flat.
    d.polygon([along(length - 7, -half - 1), along(length + 1, -half - 3),
               along(length + 1, half + 3), along(length - 7, half + 1)],
              fill=TUBE, outline=TUBE_DARK)
    d.line([along(length - 6, -half - 1), along(length, -half - 2)], fill=TUBE_LIT, width=1)
    d.line([along(length, -half - 1), along(length, half + 1)], fill=BORE, width=3)


def build(src_path, dst_path, direction):
    im = Image.open(src_path).convert("RGBA")
    # The anchor is read off the camo helmet and the recolour paints over it,
    # so it has to be taken first; the launcher goes on last, or the recolour
    # rules would read its gunmetal as more olive kit to repaint.
    anchor = head_anchor(im)
    recolor(im)
    draw_launcher(im, direction, anchor)
    im.save(dst_path)


def main():
    for direction in DIRS:
        build(f"{SRC}/miner_{direction}.png", f"{SRC}/grenadier_{direction}.png", direction)
        for i in range(6):
            build(f"{SRC}/walk/miner_{direction}_{i}.png",
                  f"{SRC}/walk/grenadier_{direction}_{i}.png", direction)
    print("wrote 28 frames")


if __name__ == "__main__":
    main()
