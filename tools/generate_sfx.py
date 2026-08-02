#!/usr/bin/env python3
"""Sound-effect generator for WIT Monster: Risk Run.

Same NES-style chip as the music (pulse with duty cycle, triangle, 15-bit LFSR
noise) but built around pitch sweeps, which are the soul of 8-bit sound effects.
Writes 8-bit mono WAVs into assets/audio/sfx/. Deterministic.

Usage:  python3 tools/generate_sfx.py
"""
import math, wave, array
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "assets/audio/sfx"
SR = 22050

_lfsr = 0x7FFF


def _ms(n):
    return max(int(SR * n / 1000.0), 1)


def _decay(i, n, power):
    return (1.0 - i / n) ** power


def pulse(buf, start, dur_ms, f0, f1, vol, duty=0.5, power=2.0, curve=1.0):
    """Pulse wave sweeping f0 -> f1. curve <1 sweeps fast then settles."""
    n = _ms(dur_ms)
    phase = 0.0
    for i in range(n):
        pos = start + i
        if pos >= len(buf):
            break
        t = (i / n) ** curve
        f = f0 + (f1 - f0) * t
        phase = (phase + f / SR) % 1.0
        amp = vol * _decay(i, n, power)
        buf[pos] += amp if phase < duty else -amp
    return n


def noise(buf, start, dur_ms, period0, period1, vol, power=2.0):
    """LFSR noise with a sweeping clock period — lower period = brighter."""
    global _lfsr
    n = _ms(dur_ms)
    value, counter = 1.0, 0
    for i in range(n):
        pos = start + i
        if pos >= len(buf):
            break
        t = i / n
        hold = max(int(period0 + (period1 - period0) * t), 1)
        counter += 1
        if counter >= hold:
            counter = 0
            bit = (_lfsr ^ (_lfsr >> 1)) & 1
            _lfsr = (_lfsr >> 1) | (bit << 14)
            value = 1.0 if (_lfsr & 1) else -1.0
        buf[pos] += value * vol * _decay(i, n, power)
    return n


def triangle(buf, start, dur_ms, f0, f1, vol, power=1.5):
    n = _ms(dur_ms)
    phase = 0.0
    for i in range(n):
        pos = start + i
        if pos >= len(buf):
            break
        f = f0 + (f1 - f0) * (i / n)
        phase = (phase + f / SR) % 1.0
        tri = round((4.0 * abs(phase - 0.5) - 1.0) * 8.0) / 8.0
        buf[pos] += tri * vol * _decay(i, n, power)
    return n


def arp(buf, start, freqs, step_ms, vol, duty=0.25, power=1.2):
    """Rapid note sequence — coins, fanfares, confirmations."""
    pos = start
    for f in freqs:
        pos += pulse(buf, pos, step_ms, f, f, vol, duty, power)
    return pos - start


def blank(dur_ms):
    return array.array("d", [0.0]) * _ms(dur_ms)


def write(buf, name, headroom=0.88):
    edge = _ms(2)
    for i in range(min(edge, len(buf) // 2)):
        k = i / edge
        buf[i] *= k
        buf[len(buf) - 1 - i] *= k
    peak = max((abs(v) for v in buf), default=0.0) or 1.0
    gain = headroom / peak
    frames = array.array("B", [0]) * len(buf)
    for i, v in enumerate(buf):
        s = max(-1.0, min(1.0, v * gain))
        frames[i] = int((s + 1.0) * 127.5)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / f"{name}.wav"
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(1)
        w.setframerate(SR)
        w.writeframes(frames.tobytes())
    return len(frames)


# ================================================================== the sounds
def build_all():
    made = []

    def emit(name, buf):
        made.append((name, write(buf, name)))

    # --- movement -----------------------------------------------------------
    b = blank(120); pulse(b, 0, 110, 240, 620, 0.75, 0.5, 1.8, 0.6); emit("jump", b)

    # second jump reads higher and thinner so you hear which one fired
    b = blank(140); pulse(b, 0, 130, 430, 940, 0.70, 0.25, 1.8, 0.55); emit("double_jump", b)

    b = blank(90); noise(b, 0, 80, 14, 30, 0.55, 2.6); emit("land", b)

    b = blank(190)
    noise(b, 0, 170, 22, 46, 0.75, 2.2)
    triangle(b, 0, 150, 150, 60, 0.55, 1.6)
    emit("land_hard", b)

    b = blank(180)
    noise(b, 0, 160, 5, 20, 0.45, 1.8)
    pulse(b, 0, 150, 700, 200, 0.45, 0.125, 2.0, 0.7)
    emit("dash", b)

    b = blank(120); pulse(b, 0, 110, 320, 700, 0.62, 0.125, 1.8, 0.6); emit("wall_jump", b)

    b = blank(300)
    noise(b, 0, 280, 30, 60, 0.80, 1.6)
    triangle(b, 0, 240, 180, 45, 0.70, 1.3)
    pulse(b, 0, 120, 260, 90, 0.35, 0.5, 2.2)
    emit("pound_impact", b)

    b = blank(220); pulse(b, 0, 200, 200, 980, 0.72, 0.5, 1.2, 0.5); emit("bounce", b)

    # --- weapons ------------------------------------------------------------
    b = blank(90); pulse(b, 0, 80, 980, 380, 0.55, 0.25, 2.4, 0.6); emit("shoot", b)

    b = blank(260)
    arp(b, 0, [523, 659, 784, 1046], 55, 0.42, 0.25, 0.6)
    emit("charge_ready", b)

    b = blank(280)
    pulse(b, 0, 260, 1250, 260, 0.80, 0.5, 1.6, 0.65)
    noise(b, 0, 140, 6, 24, 0.35, 2.0)
    emit("charged_shot", b)

    b = blank(340)
    noise(b, 0, 320, 4, 26, 0.70, 1.4)
    pulse(b, 0, 260, 620, 180, 0.42, 0.125, 1.6, 0.7)
    emit("flame_draft", b)

    # --- impacts ------------------------------------------------------------
    b = blank(80)
    noise(b, 0, 70, 8, 18, 0.60, 2.6)
    pulse(b, 0, 50, 760, 420, 0.40, 0.25, 2.8)
    emit("enemy_hit", b)

    b = blank(340)
    noise(b, 0, 320, 10, 52, 0.75, 1.6)
    pulse(b, 0, 260, 520, 120, 0.50, 0.5, 1.8, 0.7)
    emit("enemy_death", b)

    b = blank(300); pulse(b, 0, 280, 420, 110, 0.85, 0.5, 1.4, 0.8); emit("player_hurt", b)

    b = blank(260); noise(b, 0, 240, 12, 64, 0.80, 1.5); emit("crate_break", b)

    b = blank(240)
    noise(b, 0, 110, 16, 34, 0.55, 2.0)
    pulse(b, 0, 200, 300, 620, 0.50, 0.5, 1.6, 0.7)
    emit("munch", b)

    # --- pickups and UI ------------------------------------------------------
    b = blank(150); arp(b, 0, [988, 1319], 60, 0.62, 0.25, 1.0); emit("coin", b)

    b = blank(220); arp(b, 0, [784, 1046, 1319], 60, 0.55, 0.5, 1.0); emit("pickup_card", b)

    b = blank(640)
    arp(b, 0, [523, 659, 784, 1046, 1319], 100, 0.62, 0.5, 0.9)
    emit("room_clear", b)

    b = blank(420)
    pulse(b, 0, 180, 880, 880, 0.60, 0.5, 1.4)
    pulse(b, _ms(220), 180, 660, 660, 0.60, 0.5, 1.4)
    emit("low_coverage", b)

    b = blank(130); pulse(b, 0, 110, 660, 990, 0.45, 0.25, 1.6, 0.7); emit("streak", b)

    b = blank(70); pulse(b, 0, 60, 620, 620, 0.35, 0.25, 2.4); emit("ui_move", b)

    b = blank(200); arp(b, 0, [784, 1175], 80, 0.50, 0.5, 1.2); emit("ui_confirm", b)

    return made


if __name__ == "__main__":
    made = build_all()
    total = 0
    for name, size in made:
        total += size
        print(f"  {name:16s} {size / SR * 1000:6.0f} ms  {size / 1024:6.1f} KB")
    print(f"\n  {len(made)} sounds, {total / 1024:.0f} KB total")
