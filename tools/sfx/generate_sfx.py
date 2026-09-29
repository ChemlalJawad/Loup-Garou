#!/usr/bin/env python3
"""Synthesizes every sound cue and music loop in AudioConfig.lua.

Everything here is generated from scratch (oscillators, envelopes, noise),
so the output is original work with no licensing strings attached - safe to
upload to Roblox under your own account.

Usage:
    python3 -m venv .venv && .venv/bin/pip install numpy soundfile
    .venv/bin/python tools/sfx/generate_sfx.py            # writes assets/sfx/*.ogg

The output file names match the cue ids in AudioConfig.lua exactly
(UIClick.ogg, HatchReveal_Secret.ogg, Music_Hub.ogg, ...), which is what
tools/sfx/upload_audio.py relies on.
"""

from __future__ import annotations

import os
import sys

import numpy as np
import soundfile as sf

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "sfx")
RNG = np.random.default_rng(20260929)  # fixed seed: rerunning gives identical files


# --- building blocks ---------------------------------------------------------

def t_axis(duration: float) -> np.ndarray:
    return np.arange(int(duration * SR)) / SR


def freq_of(note: str) -> float:
    """'A4', 'C#5', 'Eb3' -> Hz."""
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    semis = names[note[0]]
    rest = note[1:]
    if rest[0] == "#":
        semis += 1
        rest = rest[1:]
    elif rest[0] == "b":
        semis -= 1
        rest = rest[1:]
    octave = int(rest)
    return 440.0 * 2 ** ((semis + (octave - 4) * 12) / 12)


def osc(kind: str, freq, duration: float) -> np.ndarray:
    """freq may be a float or an array (for sweeps)."""
    t = t_axis(duration)
    f = np.broadcast_to(np.asarray(freq, dtype=float), t.shape)
    phase = 2 * np.pi * np.cumsum(f) / SR
    if kind == "sine":
        return np.sin(phase)
    if kind == "square":
        return np.sign(np.sin(phase)) * 0.6
    if kind == "triangle":
        return 2 / np.pi * np.arcsin(np.sin(phase))
    if kind == "saw":
        return 2 * ((phase / (2 * np.pi)) % 1.0) - 1
    if kind == "noise":
        return RNG.uniform(-1, 1, t.shape)
    raise ValueError(kind)


def env(duration: float, attack=0.005, decay=0.08, sustain=0.6, release=0.1) -> np.ndarray:
    n = int(duration * SR)
    a, d, r = int(attack * SR), int(decay * SR), int(release * SR)
    s = max(n - a - d - r, 0)
    curve = np.concatenate([
        np.linspace(0, 1, a, endpoint=False),
        np.linspace(1, sustain, d, endpoint=False),
        np.full(s, sustain),
        np.linspace(sustain, 0, r),
    ])
    return np.pad(curve, (0, max(n - len(curve), 0)))[:n]


def pluck(duration: float, decay_rate: float = 12.0) -> np.ndarray:
    t = t_axis(duration)
    attack = np.minimum(t / 0.004, 1)
    return attack * np.exp(-t * decay_rate)


def tone(note_or_freq, duration: float, kind="sine", envelope=None, vibrato=0.0) -> np.ndarray:
    f = freq_of(note_or_freq) if isinstance(note_or_freq, str) else note_or_freq
    if vibrato:
        f = f * (1 + vibrato * np.sin(2 * np.pi * 5.5 * t_axis(duration)))
    sig = osc(kind, f, duration)
    return sig * (envelope if envelope is not None else env(duration))


def sweep(f0: float, f1: float, duration: float, kind="sine", curve="exp") -> np.ndarray:
    t = t_axis(duration)
    x = t / duration
    f = f0 * (f1 / f0) ** x if curve == "exp" else f0 + (f1 - f0) * x
    return osc(kind, f, duration)


def lowpass(sig: np.ndarray, cutoff: float) -> np.ndarray:
    # One-pole low-pass: cheap and dependency-free.
    alpha = 1 - np.exp(-2 * np.pi * cutoff / SR)
    out = np.empty_like(sig)
    acc = 0.0
    for i, x in enumerate(sig):
        acc += alpha * (x - acc)
        out[i] = acc
    return out


def mix(*parts: tuple[float, np.ndarray]) -> np.ndarray:
    """mix((start_seconds, signal), ...)"""
    end = max(int(start * SR) + len(sig) for start, sig in parts)
    out = np.zeros(end)
    for start, sig in parts:
        i = int(start * SR)
        out[i:i + len(sig)] += sig
    return out


def echo(sig: np.ndarray, delay=0.11, feedback=0.35, taps=3) -> np.ndarray:
    d = int(delay * SR)
    out = np.pad(sig, (0, d * taps))
    for k in range(1, taps + 1):
        out[d * k:d * k + len(sig)] += sig * feedback ** k
    return out


def arpeggio(notes: list[str], step: float, note_len: float, kind="triangle", decay=9.0) -> np.ndarray:
    return mix(*[(i * step, tone(n, note_len, kind, pluck(note_len, decay))) for i, n in enumerate(notes)])


def finish(sig: np.ndarray, peak=0.65, fade=0.01) -> np.ndarray:
    # 0.65 peak leaves headroom: Vorbis encoding overshoots on square waves.
    sig = sig - np.mean(sig)
    m = np.max(np.abs(sig)) or 1.0
    sig = sig / m * peak
    n = int(fade * SR)
    if n and len(sig) > n:
        sig[-n:] *= np.linspace(1, 0, n)
    return sig.astype(np.float32)


def sparkle(duration=0.5, count=10, low=2000, high=5000) -> np.ndarray:
    parts = []
    for _ in range(count):
        f = RNG.uniform(low, high)
        parts.append((RNG.uniform(0, duration * 0.7), tone(f, 0.12, "sine", pluck(0.12, 30)) * 0.4))
    return mix(*parts)


# --- cues --------------------------------------------------------------------

def ui_click():
    return mix((0, tone(1800, 0.04, "sine", pluck(0.04, 90))), (0, osc("noise", 0, 0.012) * 0.3))


def ui_open():
    return sweep(500, 1400, 0.2, "sine") * env(0.2, 0.02, 0.05, 0.7, 0.1) * 0.6 + lowpass(osc("noise", 0, 0.2), 3000) * env(0.2, 0.05, 0.05, 0.4, 0.1) * 0.25


def ui_close():
    return sweep(1200, 450, 0.15, "sine") * env(0.15, 0.01, 0.04, 0.6, 0.08) * 0.6


def purchase():
    ka = mix((0, osc("noise", 0, 0.03) * pluck(0.03, 60)))
    ching = mix((0.03, tone("E6", 0.4, "sine", pluck(0.4, 7))), (0.03, tone("B6", 0.4, "sine", pluck(0.4, 8)) * 0.6))
    return mix((0, ka), (0, ching), (0.05, sparkle(0.35, 6, 3000, 6000)))


def purchase_fail():
    return mix((0, tone(140, 0.12, "square", env(0.12, 0.005, 0.02, 0.8, 0.03))),
               (0.13, tone(110, 0.14, "square", env(0.14, 0.005, 0.02, 0.8, 0.05)))) * 0.7


def coin_reward():
    return echo(mix((0, tone("B5", 0.06, "square", pluck(0.06, 25))), (0.06, tone("E6", 0.18, "square", pluck(0.18, 14)))) * 0.5, 0.08, 0.25, 2)


def level_up():
    run = arpeggio(["C5", "E5", "G5", "C6", "E6", "G6"], 0.07, 0.35, "square", 6) * 0.45
    return echo(mix((0, run), (0.42, tone("C6", 0.6, "triangle", env(0.6, 0.01, 0.1, 0.6, 0.3)))), 0.12, 0.3)


def rebirth():
    swell = sweep(110, 880, 1.3, "saw") * env(1.3, 0.8, 0.1, 0.8, 0.4)
    swell = lowpass(swell, 2500) * 0.5
    chord = mix(*[(0.9, tone(n, 0.8, "triangle", env(0.8, 0.01, 0.2, 0.5, 0.4)) * 0.4) for n in ["C5", "E5", "G5", "C6"]])
    return mix((0, swell), (0, chord), (0.8, sparkle(0.7, 14)))


def egg_crack():
    crunch = lowpass(osc("noise", 0, 0.25), 2500) * pluck(0.25, 22)
    snaps = mix(*[(RNG.uniform(0, 0.15), osc("noise", 0, 0.02) * pluck(0.02, 120) * 0.8) for _ in range(5)])
    return mix((0, crunch), (0, snaps), (0, tone(220, 0.12, "sine", pluck(0.12, 30)) * 0.5))


def hatch(rarity: str):
    if rarity == "Common":
        return mix((0, tone(600, 0.08, "sine", pluck(0.08, 40))), (0.05, tone("C6", 0.3, "triangle", pluck(0.3, 12))))
    if rarity == "Rare":
        return echo(mix((0, tone("E5", 0.3, "triangle", pluck(0.3, 10))), (0.1, tone("B5", 0.35, "triangle", pluck(0.35, 9)))), 0.1, 0.3, 2)
    if rarity == "Epic":
        return mix((0, echo(arpeggio(["C5", "E5", "G5", "B5", "D6", "G6"], 0.06, 0.3, "triangle", 8), 0.1, 0.3)), (0.3, sparkle(0.4, 8)))
    if rarity == "Legendary":
        hit = mix(*[(0, tone(n, 0.8, "saw", env(0.8, 0.01, 0.2, 0.6, 0.4)) * 0.35) for n in ["F4", "A4", "C5", "F5"]])
        return mix((0, lowpass(hit, 3500)), (0.1, sparkle(0.7, 16)), (0, tone(55, 0.4, "sine", pluck(0.4, 6))))
    # Secret: full jackpot
    fanfare = mix(
        (0.0, tone("C5", 0.14, "square", env(0.14, 0.005, 0.03, 0.7, 0.04))),
        (0.15, tone("C5", 0.14, "square", env(0.14, 0.005, 0.03, 0.7, 0.04))),
        (0.3, tone("C5", 0.14, "square", env(0.14, 0.005, 0.03, 0.7, 0.04))),
        (0.45, mix(*[(0, tone(n, 0.8, "square", env(0.8, 0.01, 0.2, 0.6, 0.35)) * 0.4) for n in ["C5", "E5", "G5", "C6"]])),
    ) * 0.5
    crowd = lowpass(osc("noise", 0, 1.2), 900) * env(1.2, 0.5, 0.2, 0.7, 0.4) * 0.35
    return mix((0, fanfare), (0.3, crowd), (0.45, sparkle(0.8, 24)))


def quest_complete():
    return echo(mix((0, tone("G5", 0.12, "triangle", pluck(0.12, 18))), (0.1, tone("D6", 0.35, "triangle", pluck(0.35, 8)))), 0.1, 0.25, 2)


def daily_claim():
    rustle = lowpass(osc("noise", 0, 0.2), 4000) * env(0.2, 0.01, 0.05, 0.4, 0.1) * 0.4
    return mix((0, rustle), (0.12, arpeggio(["E5", "G#5", "B5", "E6"], 0.05, 0.3, "sine", 8)), (0.2, sparkle(0.4, 10)))


def code_redeem():
    return mix((0, tone("A5", 0.15, "sine", pluck(0.15, 14))), (0.08, tone("E6", 0.35, "sine", pluck(0.35, 8))))


def flag_taken():
    return mix((0, tone("A5", 0.12, "square", env(0.12, 0.003, 0.02, 0.8, 0.03))),
               (0.13, tone("D6", 0.25, "square", env(0.25, 0.003, 0.03, 0.8, 0.1)))) * 0.55


def flag_captured():
    horn = mix(*[(0, tone(n, 0.7, "saw", env(0.7, 0.02, 0.15, 0.7, 0.3)) * 0.35) for n in ["G4", "D5", "G5"]])
    return mix((0, lowpass(horn, 3000)), (0, tone(98, 0.3, "sine", pluck(0.3, 8))), (0.2, sparkle(0.5, 10)))


def flag_returned():
    return mix((0, tone("C6", 0.2, "sine", pluck(0.2, 12))), (0.09, tone("G5", 0.3, "sine", pluck(0.3, 10))))


def player_tagged():
    thud = sweep(160, 45, 0.2, "sine") * pluck(0.2, 16)
    return mix((0, thud), (0, lowpass(osc("noise", 0, 0.08), 1500) * pluck(0.08, 40) * 0.6))


def ability_used():
    whoosh = lowpass(osc("noise", 0, 0.35), 2500) * env(0.35, 0.1, 0.05, 0.6, 0.18)
    zap = sweep(300, 1400, 0.25, "saw") * env(0.25, 0.01, 0.05, 0.5, 0.15) * 0.25
    return mix((0, whoosh), (0.02, lowpass(zap, 4000)))


def powerup_collected():
    return sweep(600, 2400, 0.18, "square") * env(0.18, 0.003, 0.04, 0.6, 0.08) * 0.45


def round_start():
    beeps = mix(*[(i * 0.18, tone("A4", 0.1, "square", env(0.1, 0.003, 0.02, 0.8, 0.03)) * 0.5) for i in range(3)])
    return mix((0, beeps), (0.54, tone("A5", 0.3, "square", env(0.3, 0.003, 0.05, 0.8, 0.12)) * 0.55))


def round_win():
    melody = mix(*[(i * 0.12, tone(n, 0.3, "square", pluck(0.3, 7)) * 0.4) for i, n in enumerate(["C5", "E5", "G5", "C6", "G5", "C6"])])
    chord = mix(*[(0.72, tone(n, 0.6, "triangle", env(0.6, 0.01, 0.1, 0.6, 0.35)) * 0.35) for n in ["C5", "E5", "G5", "C6"]])
    return echo(mix((0, melody), (0, chord)), 0.12, 0.25, 2)


def round_lose():
    steps = [(i * 0.22, tone(n, 0.4, "triangle", env(0.4, 0.01, 0.1, 0.6, 0.2)) * 0.5) for i, n in enumerate(["E4", "D#4", "D4"])]
    return mix(*steps, (0.66, tone("C#4", 0.5, "triangle", env(0.5, 0.01, 0.1, 0.5, 0.3)) * 0.5))


def parade_hype():
    ooh = mix(*[(0, tone(f, 1.0, "sine", env(1.0, 0.3, 0.2, 0.7, 0.4), vibrato=0.01) * 0.3) for f in [220, 277, 330, 440]])
    return mix((0, lowpass(ooh, 1600)), (0.3, sparkle(0.7, 16)), (0.2, tone("E6", 0.5, "sine", pluck(0.5, 6)) * 0.3))


def chest_open():
    creak = sweep(180, 90, 0.35, "saw") * env(0.35, 0.05, 0.05, 0.6, 0.15)
    creak = lowpass(creak, 900) * 0.4
    jingle = arpeggio(["C6", "E6", "G6", "C7"], 0.05, 0.3, "sine", 10)
    return mix((0, creak), (0.35, jingle), (0.4, sparkle(0.5, 12)))


def coin_rain_start():
    rising = arpeggio(["C5", "D5", "E5", "G5", "A5", "C6", "D6", "E6"], 0.08, 0.25, "square", 10) * 0.4
    clinks = mix(*[(RNG.uniform(0.2, 1.0), tone(RNG.uniform(2500, 4200), 0.1, "sine", pluck(0.1, 35)) * 0.35) for _ in range(12)])
    return mix((0, rising), (0, clinks))


def lucky_rainbow_start():
    notes = ["C5", "D5", "E5", "G5", "A5", "C6", "D6", "E6", "G6", "A6", "C7"]
    harp = echo(arpeggio(notes, 0.055, 0.6, "triangle", 5) * 0.5, 0.13, 0.3)
    choir = mix(*[(0.2, tone(n, 1.1, "sine", env(1.1, 0.4, 0.2, 0.7, 0.4), vibrato=0.006) * 0.25) for n in ["C4", "G4", "E5"]])
    return mix((0, harp), (0, lowpass(choir, 2000)))


CUES = {
    "UIClick": ui_click,
    "UIOpen": ui_open,
    "UIClose": ui_close,
    "Purchase": purchase,
    "PurchaseFail": purchase_fail,
    "CoinReward": coin_reward,
    "LevelUp": level_up,
    "Rebirth": rebirth,
    "EggCrack": egg_crack,
    "HatchReveal_Common": lambda: hatch("Common"),
    "HatchReveal_Rare": lambda: hatch("Rare"),
    "HatchReveal_Epic": lambda: hatch("Epic"),
    "HatchReveal_Legendary": lambda: hatch("Legendary"),
    "HatchReveal_Secret": lambda: hatch("Secret"),
    "QuestComplete": quest_complete,
    "DailyClaim": daily_claim,
    "CodeRedeem": code_redeem,
    "FlagTaken": flag_taken,
    "FlagCaptured": flag_captured,
    "FlagReturned": flag_returned,
    "PlayerTagged": player_tagged,
    "AbilityUsed": ability_used,
    "PowerupCollected": powerup_collected,
    "RoundStart": round_start,
    "RoundWin": round_win,
    "RoundLose": round_lose,
    "ParadeHype": parade_hype,
    "ChestOpen": chest_open,
    "CoinRainStart": coin_rain_start,
    "LuckyRainbowStart": lucky_rainbow_start,
}


# --- music -------------------------------------------------------------------

def music_loop(bpm: float, chords: list[list[str]], bass: list[str], melody: list[str | None], lead_kind: str, drums: bool) -> np.ndarray:
    """4/4, one chord per bar, melody in 8th notes. Loops seamlessly: the
    total length is an exact number of bars and every note ends inside it."""
    beat = 60 / bpm
    bars = len(chords)
    total = bars * 4 * beat
    out = np.zeros(int(total * SR))

    def place(start: float, sig: np.ndarray, gain: float):
        i = int(start * SR)
        j = min(i + len(sig), len(out))
        out[i:j] += sig[: j - i] * gain

    for bar, chord in enumerate(chords):
        t0 = bar * 4 * beat
        for n in chord:  # soft pad, re-struck each half bar
            for half in range(2):
                place(t0 + half * 2 * beat, tone(n, 2 * beat * 0.95, "triangle", env(2 * beat * 0.95, 0.03, 0.2, 0.5, 0.3)), 0.12)
        for b in range(4):  # bass on every beat
            place(t0 + b * beat, tone(bass[bar], beat * 0.9, "square", pluck(beat * 0.9, 5)), 0.16)
        if drums:
            for b in range(4):
                kick = sweep(120, 45, 0.15, "sine") * pluck(0.15, 20)
                place(t0 + b * beat, kick, 0.5 if b % 2 == 0 else 0.3)
                hat = osc("noise", 0, 0.04) * pluck(0.04, 80)
                place(t0 + b * beat + beat / 2, hat, 0.12)
                if b % 2 == 1:
                    snare = lowpass(osc("noise", 0, 0.15), 5000) * pluck(0.15, 22)
                    place(t0 + b * beat, snare, 0.25)

    eighth = beat / 2
    for i, n in enumerate(melody):
        if n:
            place(i * eighth, tone(n, eighth * 1.6, lead_kind, pluck(eighth * 1.6, 6)), 0.18)
    return finish(out, peak=0.8, fade=0.0)


def music_hub():
    chords = [["C4", "E4", "G4"], ["A3", "C4", "E4"], ["F3", "A3", "C4"], ["G3", "B3", "D4"]] * 4
    bass = ["C2", "A1", "F1", "G1"] * 4
    phrase = ["E5", None, "G5", "E5", "D5", None, "C5", None,
              "C5", None, "E5", None, "A5", "G5", "E5", None,
              "F5", None, "A5", "F5", "E5", None, "C5", None,
              "D5", "E5", "D5", "B4", "G4", None, None, None]
    return music_loop(112, chords, bass, phrase * 4, "square", drums=False)


def music_arena():
    chords = [["A3", "C4", "E4"], ["F3", "A3", "C4"], ["G3", "B3", "D4"], ["E3", "G#3", "B3"]] * 4
    bass = ["A1", "F1", "G1", "E1"] * 4
    phrase = ["A5", "A5", "E5", "A5", "C6", None, "B5", "A5",
              "F5", "F5", "C5", "F5", "A5", None, "G5", "F5",
              "G5", "G5", "D5", "G5", "B5", None, "A5", "G5",
              "E5", "G#5", "B5", "E6", "D6", "B5", "G#5", "E5"]
    return music_loop(140, chords, bass, phrase * 4, "saw", drums=True)


MUSIC = {"Music_Hub": music_hub, "Music_Arena": music_arena}


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, fn in {**CUES, **MUSIC}.items():
        sig = fn()
        if not name.startswith("Music_"):
            sig = finish(sig)
        path = os.path.join(OUT_DIR, f"{name}.ogg")
        sf.write(path, sig, SR, format="OGG", subtype="VORBIS")
        print(f"{name:24s} {len(sig) / SR:6.2f}s  {os.path.getsize(path) // 1024:4d} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
