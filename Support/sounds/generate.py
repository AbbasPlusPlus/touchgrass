#!/usr/bin/env python3
"""
Synthesize TouchGrass notification sounds.

Seven styles (bell / chime / flute / marimba / kalimba / sparkle / pop) x four
events (breakStart / breakEnd / preBreak / wellness) = 28 files, written to
Sources/TGAudio/Resources as "<style>-<event>.<ext>".

Pure standard library: math + wave + random. numpy is used automatically when
it is importable, but is never required. Rendering all 28 files takes
about a minute.

Design rules (these are the audible contract, keep them):
  * 48 kHz, mono, 16-bit source. Optionally transcoded to AAC/.m4a with
    /usr/bin/afconvert (default), since AVAudioPlayer reads both.
  * peak <= -3 dBFS, and the two "ambient" events (preBreak, wellness) sit
    deliberately quieter so they never startle.
  * 5 ms raised-cosine fade-in and 50 ms fade-out on every file, plus a DC
    blocker, so nothing can click. (a competing app shipped a crackle bug here.)
  * gentle low-pass on every style so partials never get glassy (sparkle is
    capped at 9 kHz, which is where a glockenspiel stops being cheerful).

Usage:
    python3 Support/sounds/generate.py                 # -> .m4a in Resources
    python3 Support/sounds/generate.py --format wav    # keep 16-bit WAV
    python3 Support/sounds/generate.py --only bell-breakStart --play
"""

from __future__ import annotations

import argparse
import math
import os
import random
import shutil
import subprocess
import sys
import tempfile
import wave

SR = 48000
TWO_PI = 2.0 * math.pi

# ---------------------------------------------------------------- envelopes


def struck_env(n, attack, tau):
    """Raised-cosine attack into an exponential decay. Continuous, no corner."""
    out = [0.0] * n
    a = max(1, int(attack * SR))
    for i in range(min(a, n)):
        out[i] = 0.5 - 0.5 * math.cos(math.pi * i / a)
    inv = -1.0 / (tau * SR)
    for i in range(a, n):
        out[i] = math.exp((i - a) * inv)
    return out


def breath_env(n, attack, release):
    """Wind-instrument envelope: slow swell, flat body, soft release."""
    out = [1.0] * n
    a = max(1, int(attack * SR))
    r = max(1, int(release * SR))
    for i in range(min(a, n)):
        out[i] = 0.5 - 0.5 * math.cos(math.pi * i / a)
    for i in range(min(r, n)):
        out[n - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / r)
    # a touch of natural droop across the body
    for i in range(n):
        out[i] *= 1.0 - 0.10 * (i / n)
    return out


# ------------------------------------------------------------------ sources


def add_sine(buf, offset, freq, amp, env, phase=0.0):
    """Mix a constant-frequency sine, amplitude-shaped by `env`, into `buf`."""
    step = TWO_PI * freq / SR
    sin = math.sin
    for i, e in enumerate(env):
        j = offset + i
        if j >= len(buf):
            break
        buf[j] += amp * e * sin(phase + step * i)


def add_vibrato_sine(buf, offset, freq, amp, env, cents, rate, vib_delay):
    """Sine with a delayed, faded-in vibrato (phase-integrated, so no jumps)."""
    depth = 2.0 ** (cents / 1200.0) - 1.0
    phase = 0.0
    sin = math.sin
    n = len(env)
    for i in range(n):
        j = offset + i
        if j >= len(buf):
            break
        t = i / SR
        ramp = 0.0 if t < vib_delay else min(1.0, (t - vib_delay) / 0.25)
        f = freq * (1.0 + depth * ramp * sin(TWO_PI * rate * t))
        phase += TWO_PI * f / SR
        buf[j] += amp * env[i] * sin(phase)


def pink_noise(n, rng):
    """Paul Kellet's economy pink filter over uniform white noise."""
    b0 = b1 = b2 = b3 = b4 = b5 = b6 = 0.0
    out = [0.0] * n
    for i in range(n):
        w = rng.uniform(-1.0, 1.0)
        b0 = 0.99886 * b0 + w * 0.0555179
        b1 = 0.99332 * b1 + w * 0.0750759
        b2 = 0.96900 * b2 + w * 0.1538520
        b3 = 0.86650 * b3 + w * 0.3104856
        b4 = 0.55000 * b4 + w * 0.5329522
        b5 = -0.76160 * b5 - w * 0.0168980
        out[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362) * 0.11
        b6 = w * 0.115926
    return out


# ------------------------------------------------------------------ filters


def _biquad(buf, b0, b1, b2, a0, a1, a2):
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    x1 = x2 = y1 = y2 = 0.0
    for i, x0 in enumerate(buf):
        y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        buf[i] = y0
        x2, x1, y2, y1 = x1, x0, y1, y0
    return buf


def lowpass(buf, fc, q=0.7071):
    w0 = TWO_PI * fc / SR
    c, s = math.cos(w0), math.sin(w0)
    alpha = s / (2.0 * q)
    return _biquad(buf, (1 - c) / 2, 1 - c, (1 - c) / 2, 1 + alpha, -2 * c, 1 - alpha)


def highpass(buf, fc, q=0.7071):
    w0 = TWO_PI * fc / SR
    c, s = math.cos(w0), math.sin(w0)
    alpha = s / (2.0 * q)
    return _biquad(buf, (1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + alpha, -2 * c, 1 - alpha)


def reverb(buf, wet=0.22, rt60=1.4, damp=0.28):
    """Schroeder: 4 damped parallel combs into 2 series allpasses."""
    n = len(buf)
    combs = (1695, 1760, 1623, 1548)
    acc = [0.0] * n
    for d in combs:
        g = 10.0 ** (-3.0 * d / (SR * rt60))
        line = [0.0] * d
        store = 0.0
        idx = 0
        for i in range(n):
            y = line[idx]
            acc[i] += y
            store = y * (1.0 - damp) + store * damp
            line[idx] = buf[i] + store * g
            idx += 1
            if idx == d:
                idx = 0
    scale = 1.0 / len(combs)
    for i in range(n):
        acc[i] *= scale
    for d, g in ((605, 0.5), (480, 0.5)):
        line = [0.0] * d
        idx = 0
        for i in range(n):
            bufout = line[idx]
            inp = acc[i]
            line[idx] = inp + bufout * g
            acc[i] = bufout - g * inp
            idx += 1
            if idx == d:
                idx = 0
    dry = 1.0 - wet
    for i in range(n):
        buf[i] = dry * buf[i] + wet * acc[i]
    return buf


def dc_block(buf, r=0.9995):
    x1 = y1 = 0.0
    for i, x0 in enumerate(buf):
        y1 = x0 - x1 + r * y1
        x1 = x0
        buf[i] = y1
    return buf


# ------------------------------------------------------------------ mastering


def peak_of(buf):
    return max((abs(v) for v in buf), default=0.0)


def gain(buf, g):
    for i in range(len(buf)):
        buf[i] *= g
    return buf


def rms(buf):
    return math.sqrt(sum(v * v for v in buf) / len(buf)) if buf else 0.0


def k_weighted(buf):
    """ITU-R BS.1770 K-weighting (coefficients are exact at 48 kHz)."""
    y = list(buf)
    _biquad(y, 1.53512485958697, -2.69169618940638, 1.19839281085285,
            1.0, -1.69065929318241, 0.73248077421585)
    _biquad(y, 1.0, -2.0, 1.0, 1.0, -1.99004745483398, 0.99007225036621)
    return y


def short_term_loudness(buf, window=0.400):
    """Loudest 400 ms block, in LKFS. This is what "how loud is it" means for
    a one-shot cue; integrated RMS would punish anything with a long tail."""
    y = k_weighted(buf)
    w = min(len(y), max(1, int(window * SR)))
    hop = max(1, w // 4)
    best = 0.0
    for i in range(0, max(1, len(y) - w + 1), hop):
        acc = 0.0
        for v in y[i:i + w]:
            acc += v * v
        best = max(best, acc / w)
    return -0.691 + 10.0 * math.log10(best) if best > 1e-20 else -120.0


def trim_tail(buf, floor_db=-75.0, pad=0.06):
    """Drop trailing samples that are inaudible, so files don't carry dead air."""
    pk = peak_of(buf)
    if pk <= 1e-9:
        return buf
    thresh = pk * 10.0 ** (floor_db / 20.0)
    last = len(buf) - 1
    while last > 0 and abs(buf[last]) < thresh:
        last -= 1
    return buf[:min(len(buf), last + int(pad * SR))]


def master(buf, target_lkfs, ceiling_db):
    """Match perceived loudness across styles, then hold a hard peak ceiling."""
    buf = trim_tail(buf)
    cur = short_term_loudness(buf)
    g = 10.0 ** ((target_lkfs - cur) / 20.0)
    pk = peak_of(buf) * g
    limit = 10.0 ** (ceiling_db / 20.0)
    if pk > limit:
        g *= limit / pk
    gain(buf, g)
    return buf


def fades(buf, fade_in=0.005, fade_out=0.050):
    n = len(buf)
    a = min(n, max(1, int(fade_in * SR)))
    for i in range(a):
        buf[i] *= 0.5 - 0.5 * math.cos(math.pi * i / a)
    r = min(n, max(1, int(fade_out * SR)))
    for i in range(r):
        buf[n - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / r)
    if n:
        buf[0] = 0.0
        buf[-1] = 0.0
    return buf


def write_wav(path, buf):
    frames = bytearray()
    for v in buf:
        s = int(round(max(-1.0, min(1.0, v)) * 32767.0))
        frames += (s & 0xFFFF).to_bytes(2, "little", signed=False)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(frames))


# ------------------------------------------------------------------- voices


def singing_bowl(length, f0, mallet=0.05, attack=0.045):
    """
    Tibetan bowl: inharmonic partials at ~1 : 2.71 : 5.15 : 8.4, each rendered
    as a detuned pair (~+-0.5 Hz) so the tone breathes instead of sitting still.
    Higher partials decay faster, which is what makes it read as metal.
    """
    n = int(length * SR)
    buf = [0.0] * n
    tau = length / 4.6  # -> ~1% amplitude at the tail, before the fade-out
    ratios = (1.0, 2.71, 5.15, 8.4, 12.6)
    amps = (1.0, 0.50, 0.22, 0.085, 0.030)
    taus = (1.0, 0.72, 0.50, 0.34, 0.22)
    beats = (0.30, 0.45, 0.50, 0.60, 0.70)
    for k, ratio in enumerate(ratios):
        env = struck_env(n, attack * (1.0 - 0.12 * k), tau * taus[k])
        f = f0 * ratio
        # Unequal pair: equal halves would null completely on every beat and
        # sound like a wobble. 0.72/0.28 gives a ~6 dB swell instead.
        hi, lo = (0.72, 0.28) if k == 0 else (0.62, 0.38)
        add_sine(buf, 0, f - beats[k], amps[k] * hi, env, phase=0.0)
        add_sine(buf, 0, f + beats[k], amps[k] * lo, env, phase=1.1)
    if mallet > 0.0:
        # Soft mallet contact, mixed `mallet` dB under the bowl itself.
        rng = random.Random(0xB0)
        m = int(0.12 * SR)
        thump = pink_noise(m, rng)
        lowpass(thump, 1400.0)
        menv = struck_env(m, 0.004, 0.018)
        for i in range(m):
            thump[i] *= menv[i]
        ref = rms(buf[:m])
        lvl = rms(thump)
        if lvl > 1e-9 and ref > 1e-9:
            k = (ref * 10.0 ** (mallet / 20.0)) / lvl
            for i in range(m):
                buf[i] += k * thump[i]
    return buf


def chime_note(n, freq, amp, attack=0.010, tau=None):
    """Felt-mallet bar: near-harmonic, with one soft inharmonic partial."""
    tau = tau if tau else (n / SR) / 4.6
    buf = [0.0] * n
    spec = ((1.00, 1.000, 1.00), (2.00, 0.135, 0.70), (2.76, 0.055, 0.62),
            (3.01, 0.060, 0.52), (5.40, 0.018, 0.36))
    for ratio, a, td in spec:
        add_sine(buf, 0, freq * ratio, amp * a, struck_env(n, attack, tau * td))
    return buf


def flute_note(n, freq, amp, attack=0.085, release=0.16, breath_db=-26.0, seed=1):
    """Breathy near-sine with 5 Hz / +-6 cent vibrato and a pink breath layer.

    `breath_db` is the breath level relative to the tone, which is the only way
    to keep the air audible but polite across two octaves of note pitch.
    """
    buf = [0.0] * n
    env = breath_env(n, attack, release)
    for ratio, a in ((1.0, 1.0), (2.0, 0.105), (3.0, 0.032), (4.0, 0.011)):
        add_vibrato_sine(buf, 0, freq * ratio, amp * a, env,
                         cents=6.0, rate=5.0, vib_delay=0.18)
    rng = random.Random(seed)
    air = pink_noise(n, rng)
    highpass(air, freq * 0.7)
    lowpass(air, 6500.0)
    chiff = struck_env(n, 0.02, 0.09)
    for i in range(n):
        air[i] *= env[i] * 0.75 + chiff[i] * 0.55
    ref, lvl = rms(buf), rms(air)
    if lvl > 1e-9 and ref > 1e-9:
        k = (ref * 10.0 ** (breath_db / 20.0)) / lvl
        for i in range(n):
            buf[i] += k * air[i]
    return buf


# ------------------------------------------------------- upbeat voices


def add_glide_sine(buf, offset, f0, f1, glide, amp, env, phase=0.0):
    """Sine that bends f0 -> f1 over `glide` seconds, then holds.

    The bend is smoothstepped in the *pitch* domain and the phase is
    integrated, so there is no corner where the glide lands and no step in the
    waveform — a linear frequency ramp read as a zipper here.
    """
    g = max(1e-6, glide)
    span = math.log(f1 / f0)
    sin = math.sin
    for i, e in enumerate(env):
        j = offset + i
        if j >= len(buf):
            break
        x = min(1.0, (i / SR) / g)
        x = x * x * (3.0 - 2.0 * x)
        phase += TWO_PI * (f0 * math.exp(span * x)) / SR
        buf[j] += amp * e * sin(phase)


def _transient(n, amp, cutoff, tau, seed, attack=0.0015, hp=None):
    """A short filtered noise burst — the mallet/tine/click contact noise."""
    rng = random.Random(seed)
    buf = pink_noise(n, rng)
    if hp:
        highpass(buf, hp)
    lowpass(buf, cutoff)
    env = struck_env(n, attack, tau)
    for i in range(n):
        buf[i] *= env[i]
    lvl = rms(buf)
    if lvl > 1e-9:
        gain(buf, amp / lvl)
    return buf


def marimba_note(n, freq, amp, attack=0.0025, tau=None, seed=7):
    """Rosewood bar over a resonator tube.

    The bar's first overtone is tuned to exactly 4x — that ratio is the whole
    difference between a marimba and a xylophone (which tunes to 3x and sounds
    hard). The tube under the bar re-radiates that 4x for a moment and then
    swallows it, so the partial is loud at the strike and gone by ~60 ms: the
    "shimmer". Low bars ring longer than high ones, as real ones do.
    """
    tau = tau or 0.36 * (523.25 / freq) ** 0.45
    buf = [0.0] * n
    #        ratio  amp    decay x tau
    spec = ((1.00, 1.000, 1.00),
            (4.00, 0.270, 0.13),   # tuned overtone + tube shimmer, gone fast
            (9.20, 0.045, 0.05))   # the wooden "tick" of the strike
    for ratio, a, td in spec:
        add_sine(buf, 0, freq * ratio, amp * a, struck_env(n, attack, tau * td))
    # Yarn mallet on wood: dull, 3 ms, well under the tone.
    click = _transient(min(n, int(0.05 * SR)), amp * 0.10, 2600.0, 0.0045, seed)
    for i, v in enumerate(click):
        buf[i] += v
    return buf


def kalimba_note(n, freq, amp, attack=0.0018, tau=None, seed=21, buzz=0.055):
    """Plucked steel tine.

    A cantilever bar's partials run 1 : 6.27 : 17.5, which is what makes a
    kalimba read as metal rather than as a bell. The tine also rattles against
    its bridge for the first few milliseconds (`buzz`), and a real thumb piano
    is never quite in tune with itself, hence the detuned twin.
    """
    tau = tau or 0.62 * (659.26 / freq) ** 0.35
    buf = [0.0] * n
    spec = ((1.000, 1.000, 1.00),
            (6.270, 0.130, 0.16),
            (17.50, 0.020, 0.05))
    for ratio, a, td in spec:
        add_sine(buf, 0, freq * ratio, amp * a, struck_env(n, attack, tau * td))
    # Detuned twin, ~2.5 Hz flat: a slow swell rather than a chorus.
    add_sine(buf, 0, freq - 2.5, amp * 0.30, struck_env(n, attack, tau * 0.9), phase=0.7)
    if buzz > 0.0:
        b = _transient(min(n, int(0.06 * SR)), amp * buzz, 5200.0, 0.010, seed,
                       attack=0.0008, hp=freq * 1.5)
        for i, v in enumerate(b):
            buf[i] += v
    return buf


def glock_note(n, freq, amp, attack=0.0015, tau=None, seed=31, air=0.05):
    """Glockenspiel bar: a free steel bar, untuned overtones at 2.76 and 5.40.

    Those two are the sparkle; they decay much faster than the fundamental so
    the note starts glassy and settles into a pure tone. `air` adds a breath of
    filtered noise at the strike so the top end shimmers instead of pinging.
    """
    tau = tau or 0.95 * (1046.5 / freq) ** 0.4
    buf = [0.0] * n
    spec = ((1.00, 1.000, 1.00),
            (2.76, 0.200, 0.30),
            (5.40, 0.070, 0.16),
            (8.93, 0.022, 0.09))
    for ratio, a, td in spec:
        add_sine(buf, 0, freq * ratio, amp * a, struck_env(n, attack, tau * td))
    if air > 0.0:
        a = _transient(min(n, int(0.09 * SR)), amp * air, 8000.0, 0.014, seed,
                       attack=0.001, hp=2500.0)
        for i, v in enumerate(a):
            buf[i] += v
    return buf


def boop(n, f0, f1, amp, glide=0.060, tau=0.075, click=0.055, seed=41):
    """Modern UI "boop": a rounded sine that bends up, with a soft click on top.

    Almost a pure sine — one quiet octave keeps it from sounding like a test
    tone — and the click is a 2 ms lowpassed tick, there to give the onset an
    edge you feel rather than hear.
    """
    buf = [0.0] * n
    env = struck_env(n, 0.004, tau)
    add_glide_sine(buf, 0, f0, f1, glide, amp, env)
    add_glide_sine(buf, 0, f0 * 2.0, f1 * 2.0, glide, amp * 0.07,
                   struck_env(n, 0.004, tau * 0.45))
    if click > 0.0:
        c = _transient(min(n, int(0.03 * SR)), amp * click, 3200.0, 0.0022, seed,
                       attack=0.0006, hp=250.0)
        for i, v in enumerate(c):
            buf[i] += v
    return buf


def mix(dst, src, offset):
    need = offset + len(src)
    if need > len(dst):
        dst.extend([0.0] * (need - len(dst)))
    for i, v in enumerate(src):
        dst[offset + i] += v
    return dst


# -------------------------------------------------------------- the 28 cues

# Note frequencies used below (equal temperament, A4 = 440).
G4, A4, D5, E5, B5 = 392.00, 440.00, 587.33, 659.26, 987.77
A3, D4, E4 = 220.00, 293.66, 329.63  # bowl fundamentals; E4 = a fifth above A3
C5, G5, A5 = 523.25, 783.99, 880.00  # marimba / kalimba register
C6, D6 = 1046.50, 1174.66            # the top of the sparkle run

# Perceived loudness target (LKFS, loudest 400 ms) and hard peak ceiling per
# event. The two ambient cues sit far below the two "something happened" cues.
LOUDNESS = {"breakStart": -16.5, "breakEnd": -17.5, "preBreak": -23.0, "wellness": -27.0}
CEILING = {"breakStart": -3.5, "breakEnd": -4.0, "preBreak": -9.0, "wellness": -12.0}
# Equal-loudness nudge: K-weighting is flat below 1 kHz, but a 220 Hz bowl still
# reads quieter than a 660 Hz chime at the same LKFS. Small, deliberate.
STYLE_TRIM = {"bell": 1.5, "chime": 0.0, "flute": 0.0,
              "marimba": 0.0, "kalimba": 0.0, "sparkle": -1.0, "pop": 0.5}


def build_bell(event):
    if event == "breakStart":
        buf = singing_bowl(5.2, A3, mallet=-13.0)
    elif event == "breakEnd":
        buf = singing_bowl(2.6, E4, mallet=-14.0)
    elif event == "preBreak":
        buf = singing_bowl(1.6, A3, mallet=-17.0, attack=0.035)
    else:
        buf = singing_bowl(1.05, D4, mallet=-20.0, attack=0.030)
    highpass(buf, 55.0)
    lowpass(buf, 7000.0)
    return buf


def build_chime(event):
    out = []
    if event == "breakStart":
        mix(out, chime_note(int(2.1 * SR), E5, 1.00), 0)
        mix(out, chime_note(int(2.5 * SR), B5, 0.78), int(0.38 * SR))
    elif event == "breakEnd":
        mix(out, chime_note(int(1.9 * SR), B5, 0.85), 0)
        mix(out, chime_note(int(2.3 * SR), E5, 1.00), int(0.34 * SR))
    elif event == "preBreak":
        mix(out, chime_note(int(1.4 * SR), B5, 0.80), 0)
    else:
        mix(out, chime_note(int(1.15 * SR), E5, 0.80), 0)
    out.extend([0.0] * int(0.8 * SR))  # room for the reverb tail
    reverb(out, wet=0.20, rt60=1.4)
    highpass(out, 130.0)
    lowpass(out, 7500.0)
    return out


def build_flute(event):
    out = []
    if event == "breakStart":
        mix(out, flute_note(int(0.74 * SR), G4, 0.95, seed=11), 0)
        mix(out, flute_note(int(0.90 * SR), D5, 0.90, seed=12), int(0.60 * SR))
    elif event == "breakEnd":
        mix(out, flute_note(int(0.70 * SR), D5, 0.90, seed=13), 0)
        mix(out, flute_note(int(0.92 * SR), G4, 0.95, seed=14), int(0.56 * SR))
    elif event == "preBreak":
        mix(out, flute_note(int(0.95 * SR), A4, 0.90, seed=15), 0)
    else:
        mix(out, flute_note(int(0.85 * SR), G4, 0.90, seed=16, breath_db=-24.0), 0)
    out.extend([0.0] * int(0.25 * SR))
    reverb(out, wet=0.14, rt60=1.0)
    highpass(out, 110.0)
    lowpass(out, 9000.0)
    return out


def build_marimba(event):
    """Bouncy wooden phrase: C5-E5-G5 up to start, back down to end."""
    out = []
    if event == "breakStart":
        # Crescendo into the top note: the phrase should arrive somewhere.
        for k, f in enumerate((C5, E5, G5)):
            mix(out, marimba_note(int((0.85 + 0.25 * k) * SR), f, 0.86 + 0.07 * k, seed=7 + k),
                int(0.110 * k * SR))
    elif event == "breakEnd":
        # Decrescendo on the way down: a landing, not a second announcement.
        for k, f in enumerate((G5, E5, C5)):
            mix(out, marimba_note(int((0.85 + 0.25 * k) * SR), f, 1.00 - 0.05 * k, seed=11 + k),
                int(0.110 * k * SR))
    elif event == "preBreak":
        mix(out, marimba_note(int(0.80 * SR), C5, 0.90, seed=15), 0)
        mix(out, marimba_note(int(1.10 * SR), G5, 0.85, seed=16), int(0.130 * SR))
    else:
        mix(out, marimba_note(int(0.95 * SR), G5, 0.85, seed=17), 0)
    out.extend([0.0] * int(0.45 * SR))
    reverb(out, wet=0.16, rt60=0.85, damp=0.36)   # small warm room, not a hall
    highpass(out, 90.0)
    lowpass(out, 8000.0)
    return out


def build_kalimba(event):
    """Two-note grace: E5 -> A5 to start (85 ms apart), A5 -> E5 to end."""
    out = []
    if event == "breakStart":
        mix(out, kalimba_note(int(1.00 * SR), E5, 0.82, seed=21), 0)
        mix(out, kalimba_note(int(1.55 * SR), A5, 1.00, seed=22), int(0.085 * SR))
    elif event == "breakEnd":
        mix(out, kalimba_note(int(0.95 * SR), A5, 0.82, seed=23), 0)
        mix(out, kalimba_note(int(1.55 * SR), E5, 1.00, seed=24), int(0.085 * SR))
    elif event == "preBreak":
        mix(out, kalimba_note(int(1.25 * SR), A5, 0.90, seed=25, buzz=0.040), 0)
    else:
        mix(out, kalimba_note(int(1.05 * SR), E5, 0.85, seed=26, buzz=0.030), 0)
    out.extend([0.0] * int(0.45 * SR))
    reverb(out, wet=0.15, rt60=0.80, damp=0.40)
    highpass(out, 150.0)
    lowpass(out, 9500.0)
    return out


def build_sparkle(event):
    """Pentatonic run, 70 ms per step. Up four notes = "level up"; down three
    to close. Lowpassed at 9 kHz so the top stays airy rather than sharp."""
    out = []
    if event == "breakStart":
        for k, f in enumerate((G5, A5, C6, D6)):
            mix(out, glock_note(int((0.70 + 0.35 * k) * SR), f, 0.72 + 0.09 * k, seed=31 + k),
                int(0.070 * k * SR))
    elif event == "breakEnd":
        for k, f in enumerate((D6, C6, G5)):
            mix(out, glock_note(int((0.75 + 0.35 * k) * SR), f, 0.78 + 0.07 * k, seed=41 + k),
                int(0.075 * k * SR))
    elif event == "preBreak":
        mix(out, glock_note(int(0.80 * SR), G5, 0.80, seed=51), 0)
        mix(out, glock_note(int(1.25 * SR), C6, 0.88, seed=52), int(0.080 * SR))
    else:
        mix(out, glock_note(int(1.05 * SR), C6, 0.80, seed=53, air=0.035), 0)
    out.extend([0.0] * int(0.70 * SR))
    reverb(out, wet=0.26, rt60=1.5, damp=0.46)     # the soft tail
    highpass(out, 200.0)
    lowpass(out, 9000.0)
    return out


def build_pop(event):
    """UI boop. Everything here is under 0.6 s — a pop that rings is a chime."""
    out = []
    if event == "breakStart":
        mix(out, boop(int(0.30 * SR), 300.0, 660.0, 1.00), 0)
        mix(out, boop(int(0.34 * SR), 450.0, 990.0, 0.52,
                      glide=0.050, tau=0.062, click=0.030, seed=42), int(0.085 * SR))
    elif event == "breakEnd":
        mix(out, boop(int(0.38 * SR), 660.0, 300.0, 0.95,
                      glide=0.075, tau=0.085, seed=43), 0)
    elif event == "preBreak":
        mix(out, boop(int(0.30 * SR), 320.0, 520.0, 0.80,
                      glide=0.055, tau=0.070, click=0.030, seed=44), 0)
    else:
        mix(out, boop(int(0.26 * SR), 400.0, 600.0, 0.72,
                      glide=0.045, tau=0.055, click=0.020, seed=45), 0)
    out.extend([0.0] * int(0.12 * SR))
    reverb(out, wet=0.07, rt60=0.40, damp=0.50)    # a hint of room, no tail
    highpass(out, 120.0)
    lowpass(out, 6500.0)
    return out


BUILDERS = {"bell": build_bell, "chime": build_chime, "flute": build_flute,
            "marimba": build_marimba, "kalimba": build_kalimba,
            "sparkle": build_sparkle, "pop": build_pop}
EVENTS = ("breakStart", "breakEnd", "preBreak", "wellness")


def render(style, event):
    buf = BUILDERS[style](event)
    dc_block(buf)
    buf = master(buf, LOUDNESS[event] + STYLE_TRIM[style], CEILING[event])
    fades(buf)
    return buf


# ---------------------------------------------------------------------- main


def repo_root():
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def to_m4a(wav_path, out_path):
    subprocess.run(
        ["/usr/bin/afconvert", "-f", "m4af", "-d", "aac@48000", "-b", "128000",
         "-q", "127", "-s", "0", wav_path, out_path],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
    )


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join(repo_root(), "Sources", "TGAudio", "Resources"))
    ap.add_argument("--format", choices=("m4a", "wav"), default="m4a")
    ap.add_argument("--only", action="append", default=None,
                    metavar="STYLE[-EVENT]", help="render a subset, e.g. bell or chime-breakEnd")
    ap.add_argument("--play", action="store_true", help="afplay each file after writing it")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    jobs = [(s, e) for s in BUILDERS for e in EVENTS]
    if args.only:
        wanted = set(args.only)
        jobs = [(s, e) for s, e in jobs if s in wanted or f"{s}-{e}" in wanted]
        if not jobs:
            sys.exit(f"--only matched nothing: {sorted(wanted)}")

    tmp = tempfile.mkdtemp(prefix="tgsound-")
    try:
        for style, event in jobs:
            buf = render(style, event)
            stem = f"{style}-{event}"
            wav = os.path.join(tmp, stem + ".wav")
            write_wav(wav, buf)
            dest = os.path.join(args.out, stem + "." + args.format)
            if args.format == "m4a":
                to_m4a(wav, dest)
            else:
                shutil.copyfile(wav, dest)
            print(f"  {stem+'.'+args.format:26s} {len(buf)/SR:5.2f}s  "
                  f"{os.path.getsize(dest)/1024:6.1f} KB  "
                  f"peak {20*math.log10(max(peak_of(buf), 1e-9)):6.2f} dBFS  "
                  f"{short_term_loudness(buf):6.2f} LKFS")
            if args.play:
                subprocess.run(["/usr/bin/afplay", dest], check=False)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print(f"-> {args.out}")


if __name__ == "__main__":
    main()
