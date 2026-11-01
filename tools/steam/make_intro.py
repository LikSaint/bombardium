#!/usr/bin/env python3
"""Title sting for the Steam videos, laid out like the old film poster it nods to: a huge
"BOMB" on top with a tail of speed lines, "ardium!!!" big underneath and a small "PARTY GAME!"
tucked in on the left. The whole block is in perspective (shorter on the left, taller on the
right), tilted up to the right, flying in with a brass fanfare. Dev-only, not part of the game.

    python3 tools/steam/make_intro.py <outdir> <ffmpeg>

Needs Pillow and numpy. Writes <outdir>/intro.mp4: 1920x1080, 30 fps, 3.0 s, with sound.
"""
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

W, H, FPS, SECS = 1920, 1080, 30, 3.0
FONT = "/System/Library/Fonts/Supplemental/Arial Black.ttf"
TILT = 8.0            # degrees counter-clockwise: the block climbs to the right
LEFT_SCALE = 0.58     # height of the block's left edge against its right edge
HIT = 0.95            # seconds: the long note, where the title lands and flashes
SHEAR = 0.26          # italic


def styled(text: str, size: int) -> Image.Image:
    """One line of lettering, finished: dark rim, chrome band, red-orange-yellow face, italic."""
    font = ImageFont.truetype(FONT, size)
    pad = int(size * 0.18)
    tmp = Image.new("L", (10, 10))
    l, t, r, b = ImageDraw.Draw(tmp).textbbox((0, 0), text, font=font)
    w, h = r - l + pad * 2, b - t + pad * 2
    top, bottom = pad, pad + (b - t)
    rim, band = max(3, int(size * 0.075)), max(2, int(size * 0.052))

    def text_mask(width: int) -> Image.Image:
        m = Image.new("L", (w, h), 0)
        ImageDraw.Draw(m).text((pad - l, pad - t), text, font=font, fill=255,
                               stroke_width=width, stroke_fill=255)
        return m

    def vgrad(stops) -> Image.Image:
        g = np.zeros((h, w, 4), np.uint8)
        g[..., 3] = 255
        for y in range(h):
            u = min(1.0, max(0.0, (y - top) / max(1, bottom - top)))
            col = stops[-1][1]
            for i in range(len(stops) - 1):
                u0, c0 = stops[i]
                u1, c1 = stops[i + 1]
                if u <= u1:
                    k = 0.0 if u1 == u0 else (u - u0) / (u1 - u0)
                    col = tuple(c0[j] + (c1[j] - c0[j]) * k for j in range(3))
                    break
            g[y, :, :3] = col
        return Image.fromarray(g)

    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    layer.paste(Image.new("RGBA", (w, h), (24, 26, 40, 255)), (0, 0), text_mask(rim + band))
    chrome = vgrad([(0.0, (255, 255, 255)), (0.3, (205, 215, 235)), (0.5, (110, 120, 150)),
                    (0.56, (235, 240, 250)), (1.0, (150, 160, 190))])
    layer.paste(chrome, (0, 0), text_mask(band + 1))
    layer.paste(Image.new("RGBA", (w, h), (120, 8, 8, 255)), (0, 0), text_mask(max(1, size // 60)))
    face = vgrad([(0.0, (214, 22, 22)), (0.35, (244, 72, 18)), (0.62, (255, 150, 20)),
                  (1.0, (255, 232, 70))])
    layer.paste(face, (0, 0), text_mask(0))
    gloss = Image.new("L", (w, h), 0)
    ImageDraw.Draw(gloss).rectangle((0, top + 4, w, top + (bottom - top) * 0.3), fill=70)
    layer.paste(Image.new("RGBA", (w, h), (255, 255, 255, 255)), (0, 0),
                ImageChops.multiply(gloss, text_mask(0)))
    return layer.transform((w + int(h * SHEAR), h), Image.AFFINE,
                           (1, SHEAR, -h * SHEAR, 0, 1, 0), Image.BICUBIC)


def perspective_coeffs(dest, src):
    """Coefficients for Image.transform(PERSPECTIVE): maps each dest point back to its src point."""
    rows, rhs = [], []
    for (x, y), (u, v) in zip(dest, src):
        rows.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        rows.append([0, 0, 0, x, y, 1, -v * x, -v * y])
        rhs += [u, v]
    return np.linalg.solve(np.array(rows, float), np.array(rhs, float)).tolist()


def build_block():
    """The stacked lettering in perspective, and its tail of speed lines (same warp, own layer)."""
    big = styled("BOMB", 350)
    mid = styled("ardium!!!", 215)
    p1 = styled("PARTY", 84)
    p2 = styled("GAME!", 84)
    bw, bh = 1700, 740
    block = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    block.alpha_composite(big, (0, 0))
    block.alpha_composite(p1, (10, 395))
    block.alpha_composite(p2, (40, 495))
    block.alpha_composite(mid, (430, 400))

    # The tail: four streaks off the last letter of BOMB, level with the middle of the word.
    tail = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    td = ImageDraw.Draw(tail)
    x0, ymid = big.width - 30, 185
    for dy, thick, length in [(-58, 15, 560), (-20, 13, 470), (18, 11, 380), (54, 9, 290)]:
        for px in range(length):
            a = int(255 * (1 - px / length) ** 0.8)
            td.rectangle((x0 + px, ymid + dy, x0 + px, ymid + dy + thick), fill=(255, 244, 205, a))

    dest = [(0, 0.30 * bh), (0, 0.30 * bh + LEFT_SCALE * bh), (bw, bh), (bw, 0)]    # TL, BL, BR, TR
    src = [(0, 0), (0, bh), (bw, bh), (bw, 0)]
    co = perspective_coeffs(dest, src)
    return (block.transform((bw, bh), Image.PERSPECTIVE, co, Image.BICUBIC),
            tail.transform((bw, bh), Image.PERSPECTIVE, co, Image.BICUBIC))


def background() -> Image.Image:
    rng = np.random.default_rng(7)
    vx = np.linspace(-1, 1, W)[None, :]
    vy = np.linspace(-1, 1, H)[:, None]
    glow = np.exp(-(((vx - 0.1) / 0.75) ** 2 + ((vy - 0.8) / 0.4) ** 2))
    base = np.zeros((H, W, 3), np.float32)
    base[..., 0] = 4 + 60 * glow
    base[..., 1] = 6 + 105 * glow
    base[..., 2] = 14 + 190 * glow
    img = Image.fromarray(base.clip(0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    for _ in range(160):
        x, y = int(rng.integers(0, W)), int(rng.integers(0, int(H * 0.7)))
        v = int(rng.integers(90, 230))
        d.point((x, y), fill=(v, v, 255))
    return img.convert("RGBA")


def ease_out(t: float) -> float:
    return 1 - (1 - t) ** 3


def place(img: Image.Image, layer: Image.Image, centre, scale: float) -> Image.Image:
    """Scale, tilt and drop `layer` on `img` with its middle at `centre`; returns the placed layer
    (full frame size) so a mask can be taken from it."""
    ls = layer.resize((max(2, int(layer.width * scale)), max(2, int(layer.height * scale))), Image.LANCZOS)
    rot = ls.rotate(TILT, resample=Image.BICUBIC, expand=True)
    full = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    full.paste(rot, (int(centre[0] - rot.width / 2), int(centre[1] - rot.height / 2)))
    img.alpha_composite(full)
    return full


def frame(i, block, tail, glow, bg) -> Image.Image:
    t = i / FPS
    e = ease_out(min(1.0, t / HIT))
    scale = 1.2 * (0.2 + 0.8 * e)
    final = (W / 2 + 170, H / 2 + 10)
    centre = (final[0] + (1 - e) * -560, final[1] + (1 - e) * 380)
    img = bg.copy()

    pulse = 0.75 + 0.25 * np.sin(t * 9)
    gcol = Image.new("RGBA", glow.size, (255, 150, 60, 255))
    gcol.putalpha(glow.point(lambda v: int(v * pulse)))
    place(img, gcol, centre, scale)

    # The tail grows once the title has landed.
    grow = max(0.0, min(1.0, (t - HIT * 0.8) / 0.55))
    if grow > 0:
        cut = int(tail.width * (0.2 + 0.8 * grow))
        part = Image.new("RGBA", tail.size, (0, 0, 0, 0))
        part.paste(tail.crop((0, 0, cut, tail.height)), (0, 0))
        place(img, part, centre, scale)
    placed = place(img, block, centre, scale)

    # A shine sweeping over the lettering after it lands.
    if t > HIT:
        k = (t - HIT) / 0.9
        if k < 1.0:
            sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            sx = -300 + k * (W + 600)
            ImageDraw.Draw(sh).polygon([(sx, 0), (sx + 90, 0), (sx - 140, H), (sx - 230, H)], fill=(255, 255, 255, 120))
            sh = sh.filter(ImageFilter.GaussianBlur(14))
            sh.putalpha(ImageChops.multiply(sh.split()[3], placed.split()[3]))
            img.alpha_composite(sh)
    dt = t - HIT
    if 0 <= dt < 0.35:
        img.alpha_composite(Image.new("RGBA", (W, H), (255, 245, 220, int(210 * (1 - dt / 0.35) ** 2))))
    fade = min(1.0, t / 0.12) * min(1.0, (SECS - t) / 0.3)
    if fade < 1.0:
        img.alpha_composite(Image.new("RGBA", (W, H), (0, 0, 0, int(255 * (1 - fade)))))
    return img.convert("RGB")


def brass(freq: float, dur: float, sr: int, vib: float = 5.0) -> np.ndarray:
    n = int(dur * sr)
    t = np.arange(n) / sr
    f = freq * (1 + 0.004 * np.sin(2 * np.pi * vib * t) * np.minimum(1, t / 0.25))
    ph = 2 * np.pi * np.cumsum(f) / sr
    wave_ = sum(np.sin(h * ph) / (h ** 0.9) for h in range(1, 11))
    bright = np.minimum(1, t / 0.07)
    wave_ = np.sin(ph) + bright * (wave_ - np.sin(ph))
    env = np.minimum(1, t / 0.025) * np.minimum(1, (dur - t) / 0.08).clip(0, 1)
    return wave_ * env


def fanfare(path: Path, sr: int = 44100) -> None:
    """Two short stabs and one long chord, the way a space-opera crawl opens: da-da-DAAAAA."""
    n = int(SECS * sr)
    out = np.zeros(n)

    def put(sig, at, gain):
        a = int(at * sr)
        seg = sig[: n - a]
        out[a: a + len(seg)] += seg * gain

    D4, G4, D5, G5, B5 = 293.66, 392.0, 587.33, 783.99, 987.77
    for at in (0.0, 0.45):
        put(brass(G4, 0.30, sr), at, 0.55)
        put(brass(D5, 0.30, sr), at, 0.35)
    for f, g in [(G4 / 2, 0.55), (G4, 0.5), (D5, 0.5), (G5, 0.5), (B5, 0.35)]:
        put(brass(f, 1.95, sr, 5.5), HIT, g)
    rng = np.random.default_rng(3)
    noise = rng.uniform(-1, 1, int(1.6 * sr))
    hp = noise - np.convolve(noise, np.ones(8) / 8, mode="same")
    put(hp * np.exp(-np.arange(len(hp)) / sr * 3.0), HIT, 0.3)
    tt = np.arange(int(0.6 * sr)) / sr
    put(np.sin(2 * np.pi * (70 - 25 * tt) * tt) * np.exp(-tt * 6), HIT, 0.9)
    rev = np.zeros(n)
    for delay, g in [(0.045, 0.32), (0.09, 0.22), (0.15, 0.15), (0.23, 0.1)]:
        d = int(delay * sr)
        rev[d:] += out[:-d] * g
    out = out + rev
    out *= np.minimum(1, (SECS - np.arange(n) / sr) / 0.35)
    out = out / np.abs(out).max() * 0.86
    pcm = (out * 32767).astype("<i2")
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(pcm.tobytes())


def main() -> None:
    outdir = Path(sys.argv[1])
    ffmpeg = sys.argv[2]
    outdir.mkdir(parents=True, exist_ok=True)
    block, tail = build_block()
    glow = block.filter(ImageFilter.GaussianBlur(28)).split()[3]
    bg = background()
    frames = outdir / "frames"
    frames.mkdir(exist_ok=True)
    for i in range(int(SECS * FPS)):
        frame(i, block, tail, glow, bg).save(frames / f"f{i:03d}.png")
    fanfare(outdir / "fanfare.wav")
    subprocess.run([ffmpeg, "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", str(frames / "f%03d.png"),
                    "-i", str(outdir / "fanfare.wav"), "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16",
                    "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2", "-shortest",
                    str(outdir / "intro.mp4")], check=True)
    print("wrote", outdir / "intro.mp4")


if __name__ == "__main__":
    main()
