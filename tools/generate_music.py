#!/usr/bin/env python3
"""Chiptune generator for WIT Monster: Risk Run.

Synthesises NES-style 8-bit loops from scratch — two pulse channels, a
triangle bass and an LFSR noise channel — and writes 8-bit mono WAVs into
assets/audio/music/. Rendering is deterministic, so re-running reproduces
byte-identical tracks.

Usage:  python3 tools/generate_music.py
"""
import math, os, wave, array
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "assets/audio/music"
SR = 22050                      # plenty for square waves, keeps the build small
BITS = 8                        # literally 8-bit: authentic crunch, half the size

# ---------------------------------------------------------------- note helpers
_STEP = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name):
    """'A4' -> 69, 'F#3' -> 54."""
    letter, rest = name[0].upper(), name[1:]
    semis = _STEP[letter]
    if rest and rest[0] in "#b":
        semis += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return semis + (int(rest) + 1) * 12


def freq(note):
    return 440.0 * (2.0 ** ((note - 69) / 12.0))


def parse(seq):
    """'A4:2 r:4 C5:2' -> [(midi|None, sixteenths), ...]"""
    out = []
    for token in seq.split():
        name, _, length = token.partition(":")
        out.append((None if name == "r" else midi(name), int(length)))
    return out


# ------------------------------------------------------------------ oscillators
def env_at(i, n, attack, decay, sustain):
    """Simple AD-S-R shaped envelope; chiptune wants a fast, percussive front."""
    if i < attack:
        return i / attack if attack else 1.0
    j = i - attack
    if j < decay:
        return 1.0 + (sustain - 1.0) * (j / decay)
    tail = n - attack - decay
    k = n - i
    if tail > 0 and k < n * 0.18:
        return sustain * (k / (n * 0.18))
    return sustain


def render_pulse(buf, start, count, f, vol, duty=0.5, vibrato=0.0):
    if count <= 0 or f <= 0:
        return
    attack, decay = max(int(0.004 * SR), 1), max(int(0.05 * SR), 1)
    step = f / SR
    phase = 0.0
    for i in range(count):
        pos = start + i
        if pos >= len(buf):
            break
        rate = step
        if vibrato:
            rate *= 1.0 + vibrato * math.sin(2.0 * math.pi * 5.5 * i / SR)
        phase = (phase + rate) % 1.0
        amp = env_at(i, count, attack, decay, 0.72) * vol
        buf[pos] += amp if phase < duty else -amp


def render_triangle(buf, start, count, f, vol):
    """Bass channel. NES triangle is quantised to 16 steps — keep that grit."""
    if count <= 0 or f <= 0:
        return
    step = f / SR
    phase = 0.0
    for i in range(count):
        pos = start + i
        if pos >= len(buf):
            break
        phase = (phase + step) % 1.0
        tri = 4.0 * abs(phase - 0.5) - 1.0
        tri = round(tri * 8.0) / 8.0
        fade = 1.0 if i < count - SR // 80 else 0.3
        buf[pos] += tri * vol * fade


_lfsr = 1


def render_noise(buf, start, count, vol, period, decay_pow=2.0):
    """15-bit LFSR like the NES noise channel: kicks, snares and hats."""
    global _lfsr
    if count <= 0:
        return
    hold = max(int(period), 1)
    value, counter = 1.0, 0
    for i in range(count):
        pos = start + i
        if pos >= len(buf):
            break
        counter += 1
        if counter >= hold:
            counter = 0
            bit = ((_lfsr ^ (_lfsr >> 1)) & 1)
            _lfsr = (_lfsr >> 1) | (bit << 14)
            value = 1.0 if (_lfsr & 1) else -1.0
        buf[pos] += value * vol * ((1.0 - i / count) ** decay_pow)


# -------------------------------------------------------------------- arranging
CHORDS = {
    "i": (0, 3, 7), "I": (0, 4, 7), "iv": (0, 3, 7), "IV": (0, 4, 7),
    "v": (0, 3, 7), "V": (0, 4, 7), "VI": (0, 4, 7), "III": (0, 4, 7),
    "VII": (0, 4, 7), "ii": (0, 3, 7), "vi": (0, 3, 7),
}


def sixteenth(bpm):
    return int(SR * 60.0 / bpm / 4.0)


def build(spec):
    """Render one track from its spec dict."""
    bpm = spec["bpm"]
    six = sixteenth(bpm)
    prog = spec["progression"]          # [(root_note_name, quality, bars)]
    melody = parse(spec["melody"])
    counter = parse(spec.get("counter", "")) if spec.get("counter") else []

    total_bars = sum(b for _, _, b in prog)
    total = total_bars * 16 * six
    buf = array.array("d", [0.0]) * total

    # --- bass + arpeggio, driven by the chord progression -------------------
    cursor = 0
    for root_name, quality, bars in prog:
        root = midi(root_name)
        tones = [root + t for t in CHORDS[quality]]
        for bar in range(bars):
            bar_start = cursor + bar * 16 * six
            # triangle bass: root/root/fifth/root in eighths
            pattern = [0, 0, 2, 0, 1, 0, 2, 0]
            for e, idx in enumerate(pattern):
                note = tones[idx] - 12
                render_triangle(buf, bar_start + e * 2 * six, 2 * six,
                                freq(note), spec.get("bass_vol", 0.55))
            # pulse2 arpeggio: chord tones as fast sixteenths
            arp = spec.get("arp_octave", 0)
            for s in range(16):
                note = tones[s % 3] + 12 * (1 + arp)
                render_pulse(buf, bar_start + s * six, six,
                             freq(note), spec.get("arp_vol", 0.16),
                             duty=spec.get("arp_duty", 0.125))
            # --- drums ---------------------------------------------------
            for s in range(0, 16, 2):                       # hats on eighths
                render_noise(buf, bar_start + s * six, six // 2,
                             0.055, 3, 1.4)
            render_noise(buf, bar_start, six * 2, 0.30, 26, 2.6)          # kick
            render_noise(buf, bar_start + 8 * six, six * 2, 0.30, 26, 2.6)
            render_noise(buf, bar_start + 4 * six, six * 2, 0.22, 7, 2.0)  # snare
            render_noise(buf, bar_start + 12 * six, six * 2, 0.22, 7, 2.0)
        cursor += bars * 16 * six

    # --- lead melody ---------------------------------------------------------
    pos = 0
    for note, length in melody:
        if note is not None:
            render_pulse(buf, pos, length * six, freq(note),
                         spec.get("lead_vol", 0.60),
                         duty=spec.get("lead_duty", 0.5),
                         vibrato=0.004 if length >= 4 else 0.0)
        pos += length * six

    # --- optional counter-melody --------------------------------------------
    pos = 0
    for note, length in counter:
        if note is not None:
            render_pulse(buf, pos, length * six, freq(note),
                         spec.get("counter_vol", 0.26),
                         duty=spec.get("counter_duty", 0.25))
        pos += length * six

    return buf


def write_wav(buf, path):
    # Square waves rarely sit at zero, so a raw loop point clicks. A 4 ms
    # fade at each end is inaudible as a volume change but lands the seam
    # on silence, which makes the loop join cleanly.
    edge = int(SR * 0.004)
    for i in range(edge):
        k = i / edge
        buf[i] *= k
        buf[len(buf) - 1 - i] *= k

    peak = max(abs(v) for v in buf) or 1.0
    gain = 0.86 / peak
    frames = array.array("B", [0]) * len(buf)
    for i, v in enumerate(buf):
        s = v * gain
        s = -1.0 if s < -1.0 else (1.0 if s > 1.0 else s)
        frames[i] = int((s + 1.0) * 127.5)          # unsigned 8-bit PCM
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(1)
        w.setframerate(SR)
        w.writeframes(frames.tobytes())
    return len(frames)


# ============================================================== the compositions
# Each level gets its own key, tempo and character (GAME_DESIGN.md §12, §21).
TRACKS = {
    # Level 1 - residential infernos. Heroic minor, the "main theme" feel.
    "blaze_borough": dict(
        bpm=150, lead_duty=0.5, arp_duty=0.125, arp_vol=0.15,
        progression=[("A3", "i", 2), ("F3", "VI", 2), ("C3", "III", 2), ("G3", "VII", 2),
                     ("A3", "i", 2), ("F3", "VI", 2), ("G3", "VII", 2), ("E3", "V", 2)],
        melody=(
            "A4:2 C5:2 E5:4 D5:2 C5:2 B4:4   A4:2 C5:2 E5:2 A5:6 r:4 "
            "F4:2 A4:2 C5:4 B4:2 A4:2 G4:4   F4:4 G4:2 A4:2 C5:8 "
            "C5:2 E5:2 G5:4 F5:2 E5:2 D5:4   C5:2 E5:2 G5:2 C6:6 r:4 "
            "G4:2 B4:2 D5:4 C5:2 B4:2 A4:4   G4:2 B4:2 D5:2 G5:4 r:6 "
            "E5:4 D5:2 C5:2 B4:4 A4:4        A4:2 B4:2 C5:2 D5:2 E5:8 "
            "A5:4 G5:2 F5:2 E5:4 D5:4        C5:2 D5:2 E5:2 F5:2 A5:8 "
            "G5:4 F5:2 E5:2 D5:4 B4:4        D5:2 E5:2 F5:2 G5:2 B5:8 "
            "E5:2 G#5:2 B5:4 A5:2 G#5:2 F#5:4  E5:2 G#5:2 B5:2 E6:6 G#5:2 B5:2"
        )),
    # Level 2 - futuristic highways. Fastest track, relentless forward motion.
    "crashway_5000": dict(
        bpm=168, lead_duty=0.25, arp_duty=0.125, arp_vol=0.17, bass_vol=0.6,
        progression=[("E3", "i", 2), ("C3", "VI", 2), ("D3", "VII", 2), ("E3", "i", 2),
                     ("E3", "i", 2), ("G3", "III", 2), ("A3", "iv", 2), ("B3", "V", 2)],
        melody=(
            "E5:2 G5:2 B5:2 G5:2 E5:2 G5:2 B5:4   B5:2 A5:2 G5:2 F#5:2 E5:8 "
            "C5:2 E5:2 G5:2 E5:2 C5:2 E5:2 G5:4   G5:2 F5:2 E5:2 D5:2 C5:8 "
            "D5:2 F#5:2 A5:2 F#5:2 D5:2 F#5:2 A5:4  A5:2 G5:2 F#5:2 E5:2 D5:8 "
            "E5:2 G5:2 B5:2 E6:2 B5:2 G5:2 E5:4   E5:4 r:2 B4:2 E5:8 "
            "B5:4 A5:2 G5:2 F#5:4 E5:4            E5:2 F#5:2 G5:2 A5:2 B5:8 "
            "D6:4 B5:2 G5:2 D5:4 B4:4             G5:2 A5:2 B5:2 D6:2 G6:8 "
            "A5:4 G5:2 F#5:2 E5:4 C5:4            A4:2 C5:2 E5:2 A5:2 C6:8 "
            "B5:2 D#6:2 F#6:4 E6:2 D#6:2 B5:4     B5:2 F#5:2 D#5:2 B4:4 F#5:2 A5:2 B5:2"
        )),
    # Level 3 - flooded harbour. Slower, rolling, everything moves in swells.
    "storm_surge_harbor": dict(
        bpm=132, lead_duty=0.5, arp_duty=0.25, arp_vol=0.14, lead_vol=0.58,
        progression=[("D3", "i", 2), ("A3", "v", 2), ("Bb3", "VI", 2), ("F3", "III", 2),
                     ("D3", "i", 2), ("G3", "iv", 2), ("A3", "V", 2), ("D3", "i", 2)],
        melody=(
            "D5:4 F5:4 A5:4 F5:4      E5:4 D5:4 C5:8 "
            "C5:4 E5:4 A5:4 E5:4      G5:4 F5:4 E5:8 "
            "D5:4 F5:4 Bb5:4 F5:4     A5:4 G5:4 F5:8 "
            "C5:4 F5:4 A5:4 C6:4      A5:4 G5:4 F5:8 "
            "A5:2 G5:2 F5:2 E5:2 D5:8 D5:2 E5:2 F5:2 G5:2 A5:8 "
            "Bb5:4 A5:2 G5:2 D5:4 G5:4  G5:2 A5:2 Bb5:2 D6:2 G6:8 "
            "A5:4 C#6:4 E6:4 C#6:4    B5:4 A5:4 G5:8 "
            "F5:4 E5:4 D5:4 A4:4      D5:16"
        )),
    # Level 4 - the digital city. Staccato, stuttering, deliberately "wrong".
    "cyber_city": dict(
        bpm=160, lead_duty=0.125, arp_duty=0.5, arp_vol=0.13, arp_octave=1,
        progression=[("B3", "i", 2), ("F#3", "v", 2), ("G3", "VI", 2), ("D3", "III", 2),
                     ("B3", "i", 2), ("E3", "iv", 2), ("F#3", "V", 2), ("B3", "i", 2)],
        melody=(
            "B4:1 r:1 D5:1 r:1 F#5:2 r:2 F#5:1 r:1 E5:1 r:1 D5:4 "
            "B4:1 r:1 B4:1 r:1 D5:2 F#5:2 B5:8 "
            "F#5:1 r:1 A5:1 r:1 C#6:2 r:2 C#6:1 r:1 B5:1 r:1 A5:4 "
            "F#5:2 A5:2 C#6:4 F#6:8 "
            "G5:1 r:1 B5:1 r:1 D6:2 r:2 D6:1 r:1 C6:1 r:1 B5:4 "
            "G5:2 B5:2 D6:4 G6:8 "
            "D5:1 r:1 F#5:1 r:1 A5:2 r:2 A5:1 r:1 G5:1 r:1 F#5:4 "
            "D5:2 F#5:2 A5:4 D6:8 "
            "F#5:2 E5:2 D5:2 C#5:2 B4:8    B4:2 C#5:2 D5:2 E5:2 F#5:8 "
            "G5:2 F#5:2 E5:2 D5:2 B4:8     E5:2 G5:2 B5:2 E6:2 G6:8 "
            "C#6:2 B5:2 A#5:2 F#5:2 C#6:8  F#5:2 A#5:2 C#6:2 F#6:2 A#6:8 "
            "B5:4 F#5:4 D5:4 B4:4          B4:2 D5:2 F#5:2 B5:2 D6:8"
        )),
    # Level 5 - the broken amusement park. Major key, bouncy, faintly sinister.
    "liability_land": dict(
        bpm=145, lead_duty=0.25, arp_duty=0.125, arp_vol=0.16,
        progression=[("C3", "I", 2), ("A3", "vi", 2), ("F3", "IV", 2), ("G3", "V", 2),
                     ("C3", "I", 2), ("A3", "vi", 2), ("D3", "ii", 2), ("G3", "V", 2)],
        melody=(
            "C5:2 E5:2 G5:2 E5:2 C5:2 E5:2 G5:4   G5:2 E5:2 C5:2 E5:2 G5:8 "
            "A4:2 C5:2 E5:2 C5:2 A4:2 C5:2 E5:4   E5:2 C5:2 A4:2 C5:2 E5:8 "
            "F5:2 A5:2 C6:4 A5:2 F5:2 A5:4        C6:4 A5:2 F5:2 A5:8 "
            "G5:2 B5:2 D6:4 B5:2 G5:2 B5:4        D6:4 B5:2 G5:2 D6:8 "
            "E6:4 D6:2 C6:2 G5:4 E5:4             C6:2 B5:2 A5:2 G5:2 E5:8 "
            "A5:4 G5:2 E5:2 C5:4 A4:4             A4:2 C5:2 E5:2 A5:2 C6:8 "
            "D5:2 F#5:2 A5:2 D6:2 F#6:8           A5:4 F#5:2 D5:2 A5:8 "
            "G5:2 B5:2 D6:2 G6:2 D6:2 B5:2 G5:4   B5:4 D6:4 G6:8"
        )),
    # Boss theme (§21: every level needs one). Fastest, darkest, relentless.
    "boss_theme": dict(
        bpm=172, lead_duty=0.25, arp_duty=0.125, arp_vol=0.18, bass_vol=0.65,
        lead_vol=0.62,
        progression=[("D3", "i", 2), ("Bb3", "VI", 2), ("C3", "VII", 2), ("A3", "V", 2),
                     ("D3", "i", 2), ("G3", "iv", 2), ("Bb3", "VI", 2), ("A3", "V", 2)],
        melody=(
            "D5:2 A5:2 F5:2 D5:2 A4:2 D5:2 F5:4   E5:2 F5:2 E5:2 D5:2 A4:8 "
            "Bb4:2 F5:2 D5:2 Bb4:2 F4:2 Bb4:2 D5:4  C5:2 D5:2 C5:2 Bb4:2 F4:8 "
            "C5:2 G5:2 E5:2 C5:2 G4:2 C5:2 E5:4   D5:2 E5:2 D5:2 C5:2 G4:8 "
            "A4:2 E5:2 C#5:2 A4:2 E5:2 A5:2 C#6:4  A5:2 G5:2 F5:2 E5:2 A5:8 "
            "D6:4 C6:2 Bb5:2 A5:4 F5:4            D5:2 F5:2 A5:2 D6:2 F6:8 "
            "G5:4 F5:2 E5:2 D5:4 Bb4:4            G4:2 Bb4:2 D5:2 G5:2 Bb5:8 "
            "Bb5:4 A5:2 G5:2 F5:4 D5:4            Bb4:2 D5:2 F5:2 Bb5:2 D6:8 "
            "A5:2 C#6:2 E6:4 D6:2 C#6:2 A5:4      A5:2 E5:2 C#5:2 A4:4 E5:2 A5:2"
        )),
    # Short cue for the end-of-run claim report (§21 victory cue).
    "claim_victory": dict(
        bpm=150, lead_duty=0.5, arp_vol=0.14, arp_duty=0.25,
        progression=[("C3", "I", 1), ("F3", "IV", 1), ("G3", "V", 1), ("C3", "I", 1)],
        melody=(
            "C5:2 E5:2 G5:4 E5:2 G5:2 C6:4 "
            "F5:2 A5:2 C6:4 A5:4 F5:4 "
            "G5:2 B5:2 D6:4 B5:2 D6:2 G6:4 "
            "C6:4 G5:4 E5:4 C6:4"
        )),
}


def main():
    total = 0
    for name, spec in TRACKS.items():
        buf = build(spec)
        path = OUT_DIR / f"{name}.wav"
        size = write_wav(buf, path)
        seconds = size / SR
        total += size
        print(f"  {name:22s} {seconds:5.1f}s  {size/1024:7.0f} KB  "
              f"{spec['bpm']:3d} BPM")
    print(f"\n  {len(TRACKS)} tracks, {total/1024/1024:.2f} MB total "
          f"({SR} Hz, {BITS}-bit mono)")


if __name__ == "__main__":
    main()
