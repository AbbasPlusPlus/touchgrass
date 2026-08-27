#!/usr/bin/env python3
"""
Synthesize TouchGrass notification sounds.

Three styles (bell / chime / flute) x four events (breakStart / breakEnd /
preBreak / wellness) = 12 files, written to Sources/TGAudio/Resources as
"<style>-<event>.<ext>".

Pure standard library: math + wave + random. numpy is used automatically when
it is importable, but is never required. Rendering all 12 files takes a few
seconds.

Design rules (these are the audible contract, keep them):
  * 48 kHz, mono, 16-bit source. Optionally transcoded to AAC/.m4a with
    /usr/bin/afconvert (default), since AVAudioPlayer reads both.
  * peak <= -3 dBFS, and the two "ambient" events (preBreak, wellness) sit
    deliberately quieter so they never startle.
  * 5 ms raised-cosine fade-in and 50 ms fade-out on every file, plus a DC
    blocker, so nothing can click. ( shipped a crackle bug here.)
  * gentle low-pass on bell/chime so partials never get glassy.

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


def mix(dst, src, offset):
    need = offset + len(src)
    if need > len(dst):
        dst.extend([0.0] * (need - len(dst)))
    for i, v in enumerate(src):
        dst[offset + i] += v
    return dst


# -------------------------------------------------------------- the 12 cues

# Note frequencies used below (equal temperament, A4 = 440).
G4, A4, D5, E5, B5 = 392.00, 440.00, 587.33, 659.26, 987.77
A3, D4, E4 = 220.00, 293.66, 329.63  # bowl fundamentals; E4 = a fifth above A3

# Perceived loudness target (LKFS, loudest 400 ms) and hard peak ceiling per
# event. The two ambient cues sit far below the two "something happened" cues.
LOUDNESS = {"breakStart": -16.5, "breakEnd": -17.5, "preBreak": -23.0, "wellness": -27.0}
CEILING = {"breakStart": -3.5, "breakEnd": -4.0, "preBreak": -9.0, "wellness": -12.0}
# Equal-loudness nudge: K-weighting is flat below 1 kHz, but a 220 Hz bowl still
# reads quieter than a 660 Hz chime at the same LKFS. Small, deliberate.
STYLE_TRIM = {"bell": 1.5, "chime": 0.0, "flute": 0.0}


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


BUILDERS = {"bell": build_bell, "chime": build_chime, "flute": build_flute}
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
