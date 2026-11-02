#!/usr/bin/env python3
"""Cuts the main trailer together from the raw takes and the title cards. Dev-only.

    python3 tools/steam/assemble_main.py <ffmpeg> <workdir> <out.mp4>

<workdir> holds the recordings and cards:  join/join.avi  lobby/lobby.avi  cards/card_<name>.mp4
intro_bombardium.mp4 (make_intro.py) is looked up in docs/steam/out next to the output.
Every game take is cut to its part (START/LEN in seconds from the start of the recording), the
game's sound is pulled down a little, the lobby is zoomed (its interface is small in the frame),
then the lot is joined: intro, card, take, card, take...
"""
import subprocess
import sys
from pathlib import Path

ffmpeg, work, out = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
seg_dir = work / "seg"
seg_dir.mkdir(exist_ok=True)
AUDIO = "volume=0.6,alimiter=limit=0.9:level=disabled"
LOBBY_ZOOM = "crop=1280:720:320:150,scale=1920:1080:flags=lanczos"


def seg(name, src, start, length, vf=None):
    o = seg_dir / f"{name}.mp4"
    cmd = [ffmpeg, "-v", "error", "-y", "-ss", str(start), "-t", str(length), "-i", str(src), "-af", AUDIO]
    if vf:
        cmd += ["-vf", vf]
    cmd += ["-r", "30", "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2", str(o)]
    subprocess.run(cmd, check=True)
    return o


card = lambda n: work / "cards" / f"card_{n}.mp4"
join, lobby = work / "join" / "join.avi", work / "lobby" / "lobby.avi"
parts = [
    out.parent / "intro_bombardium.mp4",
    card("classic"), seg("a1", join, 7.0, 9.0),
    card("players"), seg("a2", join, 16.0, 7.5),
    card("gamepads"), seg("a3", join, 23.5, 3.4),
    card("bots"), seg("l1", lobby, 1.0, 4.6, LOBBY_ZOOM),
    card("heroes"), seg("l2", lobby, 5.4, 5.0, LOBBY_ZOOM),
]
cmd = [ffmpeg, "-v", "error", "-y"]
for p in parts:
    cmd += ["-i", str(p)]
n = len(parts)
fc = "".join(f"[{i}:v][{i}:a]" for i in range(n)) + f"concat=n={n}:v=1:a=1[v][a]"
cmd += ["-filter_complex", fc, "-map", "[v]", "-map", "[a]", "-c:v", "libx264", "-preset", "slow", "-crf", "22",
        "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", str(out)]
subprocess.run(cmd, check=True)
print("wrote", out)
