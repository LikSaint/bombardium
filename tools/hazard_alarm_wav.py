#!/usr/bin/env python3
"""Writes assets/sfx/hazard_alarm.wav: the two-tone siren heard when a crate drops a hazard.

Two rising beeps, deliberately unlike anything else in the set (the rest are
noise bursts and single blips) so it is recognisable as "something dangerous
just appeared" without looking. Run from anywhere; it finds the project from
its own location, and Godot needs a re-import (open the editor once, or run
`godot --headless --import`) before the game can preload the result.
"""
import math
import os
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx", "hazard_alarm.wav")


def beep(freq_start, freq_end, seconds, volume=0.55):
    """A sine sweep with a short attack and release so it doesn't click."""
    n = int(RATE * seconds)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / n
        freq = freq_start + (freq_end - freq_start) * t
        phase += 2.0 * math.pi * freq / RATE
        edge = min(1.0, i / (RATE * 0.01), (n - i) / (RATE * 0.04))
        # A touch of the third harmonic so it cuts through the music.
        sample = math.sin(phase) + 0.25 * math.sin(3.0 * phase)
        out.append(volume * edge * sample / 1.25)
    return out


def main():
    gap = [0.0] * int(RATE * 0.06)
    samples = beep(620, 760, 0.16) + gap + beep(760, 940, 0.2)
    with wave.open(OUT, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))
    print("wrote", os.path.normpath(OUT), "-", len(samples) / RATE, "s")


if __name__ == "__main__":
    main()
