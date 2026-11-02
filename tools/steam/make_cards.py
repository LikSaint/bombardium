#!/usr/bin/env python3
"""Title cards for the main Steam trailer: a line or two of lettering on a black screen, in the
same chrome / red-to-yellow italic style as the intro (make_intro.py), slammed in with a flash,
a shine sweeping over it and a short brass hit. Dev-only, not part of the game.

    python3 tools/steam/make_cards.py <outdir> <ffmpeg> [card ...]

Needs Pillow and numpy. Writes <outdir>/card_<name>.mp4 for every card (or just the named ones):
1920x1080, 30 fps, with sound. The wording lives in CARDS below.
"""
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_intro as mi  # noqa: E402

W, H, FPS = mi.W, mi.H, mi.FPS
TILT = 4.0          # degrees: the same climb to the right as the intro, gentler
IMPACT = 0.26       # seconds: where the lettering lands
MAX_WIDTH = 1560    # widest a line may be before it is shrunk to fit

# name: (secs, [(text, size), ...])
CARDS = {
    "classic": (2.3, [("A CLASSIC,", 170), ("REIMAGINED.", 170)]),
    "players": (2.3, [("UP TO 4 PLAYERS", 150), ("ONE SCREEN", 150)]),
    "gamepads": (2.3, [("MODERN GAMEPADS", 150), ("SUPPORTED", 150)]),
    "bots": (2.4, [("NO ONE TO PLAY WITH?", 130), ("ADD BOTS!", 190)]),
    "heroes": (2.4, [("NEW HEROES", 170), ("UNIQUE ABILITIES", 110)]),
    "sapper": (2.4, [("SAPPER", 200), ("YOU DECIDE WHEN IT BLOWS", 84)]),
    "kicker": (2.4, [("KICKER", 200), ("BOOT THE BOMB AWAY", 90)]),
    "parkour": (2.4, [("PARKOUR RUNNER", 160), ("JUMPS OVER ANYTHING", 90)]),
    "crew": (2.4, [("MINER", 150), ("ENGINEER", 150), ("GRENADIER", 150)]),
    "traps": (2.3, [("TRAPS", 190), ("AND HAZARDS", 130)]),
    "end": (3.2, [("1-4 PLAYERS", 130), ("BOTS · GAMEPADS", 110)]),
}


def build(lines):
    """The card's lettering as one transparent layer, lines centred on each other."""
    layers = []
    for text, size in lines:
        layer = mi.styled(text, size)
        if layer.width > MAX_WIDTH:
            layer = mi.styled(text, int(size * MAX_WIDTH / layer.width))
        layers.append(layer)
    gap = -int(min(l.height for l in layers) * 0.12)
    total_h = sum(l.height for l in layers) + gap * (len(layers) - 1)
    total_w = max(l.width for l in layers)
    block = Image.new("RGBA", (total_w, total_h), (0, 0, 0, 0))
    y = 0
    for l in layers:
        block.alpha_composite(l, ((total_w - l.width) // 2, y))
        y += l.height + gap
    return block


def place(img, layer, centre, scale):
    ls = layer.resize((max(2, int(layer.width * scale)), max(2, int(layer.height * scale))), Image.LANCZOS)
    rot = ls.rotate(TILT, resample=Image.BICUBIC, expand=True)
    full = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    full.paste(rot, (int(centre[0] - rot.width / 2), int(centre[1] - rot.height / 2)))
    img.alpha_composite(full)
    return full


def frame(i, secs, block, glow):
    t = i / FPS
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    k = min(1.0, t / IMPACT)
    e = mi.ease_out(k)
    scale = (1.0 + 0.5 * (1 - e)) * (1.0 + 0.035 * t / secs)
    centre = (W / 2, H / 2)

    pulse = 0.55 + 0.2 * np.sin(t * 8)
    gcol = Image.new("RGBA", glow.size, (255, 140, 50, 255))
    gcol.putalpha(glow.point(lambda v: int(v * pulse * e)))
    place(img, gcol, centre, scale)

    layer = block.copy()
    layer.putalpha(layer.split()[3].point(lambda v: int(v * min(1.0, t / 0.09))))
    placed = place(img, layer, centre, scale)

    s = (t - IMPACT) / 0.7
    if 0 <= s < 1.0:
        sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        sx = -300 + s * (W + 600)
        ImageDraw.Draw(sh).polygon([(sx, 0), (sx + 80, 0), (sx - 140, H), (sx - 220, H)], fill=(255, 255, 255, 120))
        sh = sh.filter(ImageFilter.GaussianBlur(12))
        sh.putalpha(ImageChops.multiply(sh.split()[3], placed.split()[3]))
        img.alpha_composite(sh)
    dt = t - IMPACT
    if 0 <= dt < 0.22:
        img.alpha_composite(Image.new("RGBA", (W, H), (255, 245, 220, int(150 * (1 - dt / 0.22) ** 2))))
    fade = min(1.0, (secs - t) / 0.28)
    if fade < 1.0:
        img.alpha_composite(Image.new("RGBA", (W, H), (0, 0, 0, int(255 * (1 - fade)))))
    return img.convert("RGB")


def hit_sound(path, secs, sr=44100):
    """A whoosh up to the impact, then a brass hit with a low thump: da-DAH."""
    n = int(secs * sr)
    out = np.zeros(n)

    def put(sig, at, gain):
        a = int(at * sr)
        seg = sig[: n - a]
        out[a: a + len(seg)] += seg * gain

    rng = np.random.default_rng(5)
    m = int(IMPACT * sr)
    sw = rng.uniform(-1, 1, m)
    sw = sw - np.convolve(sw, np.ones(12) / 12, mode="same")
    put(sw * (np.arange(m) / m) ** 2, 0.0, 0.35)
    G4, D5, B5 = 392.0, 587.33, 987.77
    for f, g in [(G4 / 2, 0.5), (G4, 0.5), (D5, 0.45), (B5, 0.2)]:
        put(mi.brass(f, 0.9, sr, 5.0), IMPACT, g)
    tt = np.arange(int(0.5 * sr)) / sr
    put(np.sin(2 * np.pi * (70 - 25 * tt) * tt) * np.exp(-tt * 7), IMPACT, 0.9)
    noise = rng.uniform(-1, 1, int(0.9 * sr))
    hp = noise - np.convolve(noise, np.ones(8) / 8, mode="same")
    put(hp * np.exp(-np.arange(len(hp)) / sr * 5.0), IMPACT, 0.25)
    out *= np.minimum(1, (secs - np.arange(n) / sr) / 0.3)
    out = out / np.abs(out).max() * 0.7
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes((out * 32767).astype("<i2").tobytes())


def main():
    outdir = Path(sys.argv[1])
    ffmpeg = sys.argv[2]
    names = sys.argv[3:] or list(CARDS)
    outdir.mkdir(parents=True, exist_ok=True)
    for name in names:
        secs, lines = CARDS[name]
        block = build(lines)
        padded = Image.new("RGBA", (block.width + 200, block.height + 200), (0, 0, 0, 0))
        padded.paste(block, (100, 100)) # room for the glow to fade out before the layer's edge
        glow = padded.filter(ImageFilter.GaussianBlur(26)).split()[3]
        frames = outdir / f"frames_{name}"
        frames.mkdir(exist_ok=True)
        for i in range(int(secs * FPS)):
            frame(i, secs, block, glow).save(frames / f"f{i:03d}.png")
        wav = outdir / f"{name}.wav"
        hit_sound(wav, secs)
        out = outdir / f"card_{name}.mp4"
        subprocess.run([ffmpeg, "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", str(frames / "f%03d.png"),
                        "-i", str(wav), "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16",
                        "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2", "-shortest", str(out)], check=True)
        for f in frames.glob("*.png"):
            f.unlink()
        frames.rmdir()
        wav.unlink()
        print("wrote", out)


if __name__ == "__main__":
    main()
