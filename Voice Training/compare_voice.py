"""
compare_voice.py - measure how close generated speech is to your real recordings.

It measures the same acoustic properties on your real clips and on generated clips,
then shows where the generated voice falls outside the range of the real one.

Run (from the Voice Training folder):
    python compare_voice.py                       compare every epoch in tune_outputs
    python compare_voice.py test_outputs          compare one folder of WAV files
    python compare_voice.py my.wav other.wav      compare specific files
    python compare_voice.py --similarity          also score speaker similarity (needs the GPU)

Only numpy is required. It runs on the CPU in a few seconds.

What the measurements mean
    pitch          typical pitch of the voice, in Hz
    pitch range    how much the pitch moves around (low = flat, monotone)
    pitch jumps    frame-to-frame pitch change (high = jittery or glitchy, low = unnaturally smooth)
    clarity        how cleanly periodic the voiced sound is (low = buzzy or noisy)
    movement       how fast the sound changes over time (low = static or droning)
    brightness     share of energy above 4 kHz (low = muffled, high = hissy)
    tone match     distance between the average tone colour and your real voice, in dB (lower is closer)
    voiced         share of time spent on voiced sound (speech pacing)
"""

import argparse
import sys
import wave
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
REAL_DIR = HERE / "voice_data" / "clips"
TUNE_DIR = HERE / "tune_outputs"
WIN, HOP = 0.04, 0.01                      # analysis window and step, in seconds
BANDS = np.geomspace(100, 11000, 25)       # band edges for the average-tone measurement

METRICS = [                                # key, label, format
    ("pitch", "pitch (Hz)", "{:.0f}"),
    ("range", "pitch range", "{:.2f}"),
    ("jumps", "pitch jumps", "{:.3f}"),
    ("clarity", "clarity", "{:.3f}"),
    ("movement", "movement", "{:.2f}"),
    ("bright", "brightness", "{:.3f}"),
    ("tone", "tone match (dB)", "{:.2f}"),
    ("voiced", "voiced", "{:.2f}"),
]


def load(path):
    """Read a WAV file as mono float32. Returns (samples, sample_rate)."""
    try:
        with wave.open(str(path)) as w:
            if w.getsampwidth() != 2:
                raise wave.Error("not 16-bit")
            rate, channels = w.getframerate(), w.getnchannels()
            data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768
        return data.reshape(-1, channels).mean(axis=1), rate
    except (wave.Error, EOFError):
        import soundfile as sf             # for float or 24-bit files
        data, rate = sf.read(str(path), dtype="float32", always_2d=True)
        return data.mean(axis=1), rate


def analyse(path):
    """Measure one file. Returns a dict of numbers plus its average-tone curve, or None if unusable."""
    audio, rate = load(path)
    win, hop = int(WIN * rate), int(HOP * rate)
    if len(audio) < win * 5:
        return None
    count = 1 + (len(audio) - win) // hop
    frames = audio[np.arange(win)[None, :] + hop * np.arange(count)[:, None]]
    frames = frames - frames.mean(axis=1, keepdims=True)
    energy = np.sqrt((frames ** 2).mean(axis=1))
    loud = energy > 0.1 * np.percentile(energy, 95)

    # Pitch from the autocorrelation of each frame (computed with FFTs).
    size = 1 << int(np.ceil(np.log2(2 * win)))
    power = np.abs(np.fft.rfft(frames, size, axis=1)) ** 2
    acf = np.fft.irfft(power, axis=1)[:, :win]
    acf = acf / (acf[:, :1] + 1e-12)
    acf = acf / (1 - np.arange(win) / win)[None, :]           # undo the shrinking-overlap bias
    low, high = int(rate / 450), int(rate / 80)
    region = acf[:, low - 1:high + 1]
    middle = region[:, 1:-1]
    best = middle.max(axis=1, keepdims=True)
    # Take the first strong peak, not the tallest, so the pitch isn't read an octave too low.
    is_peak = (middle > region[:, :-2]) & (middle >= region[:, 2:]) & (middle >= 0.85 * best)
    index = np.where(is_peak.any(axis=1), is_peak.argmax(axis=1), middle.argmax(axis=1))
    rows = np.arange(count)
    before, peak, after = region[rows, index], region[rows, index + 1], region[rows, index + 2]
    curve = before - 2 * peak + after
    shift = np.where(np.abs(curve) > 1e-9, 0.5 * (before - after) / np.where(curve == 0, 1, curve), 0.0)
    lag = low + index + np.clip(shift, -0.5, 0.5)             # sub-sample precision
    voiced = loud & (peak > 0.5)
    if voiced.sum() < 20:
        return None
    f0 = rate / lag
    semis = 12 * np.log2(f0[voiced] / np.median(f0[voiced]))
    both = voiced[1:] & voiced[:-1]
    steps = np.abs(12 * np.log2(f0[1:] / f0[:-1]))[both]
    steps = steps[steps < 6]                                   # ignore octave slips

    spectrum = np.abs(np.fft.rfft(frames * np.hanning(win)[None, :], axis=1)) ** 2
    freqs = np.fft.rfftfreq(win, 1 / rate)
    log_spec = 10 * np.log10(spectrum + 1e-10)
    flux = np.sqrt(((log_spec[1:] - log_spec[:-1]) ** 2).mean(axis=1))[loud[1:] & loud[:-1]]
    speech = spectrum[loud].mean(axis=0)
    tone = np.array([10 * np.log10(speech[(freqs >= a) & (freqs < b)].mean() + 1e-12)
                     for a, b in zip(BANDS[:-1], BANDS[1:])])
    tone = tone - tone.mean()                                  # ignore overall loudness

    return {
        "pitch": float(np.median(f0[voiced])),
        "range": float(np.percentile(semis, 90) - np.percentile(semis, 10)),
        "jumps": float(np.median(steps)) if len(steps) else 0.0,
        "clarity": float(peak[voiced].mean()),
        "movement": float(flux.mean()) if len(flux) else 0.0,
        "bright": float(speech[freqs >= 4000].sum() / speech.sum()),
        "voiced": float(voiced.sum() / max(loud.sum(), 1)),
        "_tone": tone,
    }


def analyse_many(paths):
    results = [r for r in (analyse(p) for p in paths) if r is not None]
    return results


def add_tone_distance(results, reference_tone):
    for r in results:
        r["tone"] = float(np.sqrt(((r["_tone"] - reference_tone) ** 2).mean()))


def real_baseline():
    """Measure the real clips. Each clip's tone is compared with the average of the others."""
    paths = sorted(REAL_DIR.glob("*.wav"))
    if not paths:
        sys.exit(f"No real clips found in {REAL_DIR}")
    results = analyse_many(paths)
    tones = np.stack([r["_tone"] for r in results])
    total = tones.sum(axis=0)
    for r in results:
        r["tone"] = float(np.sqrt(((r["_tone"] - (total - r["_tone"]) / (len(results) - 1)) ** 2).mean()))
    ranges = {key: (np.percentile([r[key] for r in results], 10), np.percentile([r[key] for r in results], 90))
              for key, _, _ in METRICS}
    return results, total / len(results), ranges


def verdict(value, low, high):
    if value < low:
        return "LOW"
    if value > high:
        return "HIGH"
    return "ok"


def report(name, results, ranges):
    """Print one group's averages against the real range. Returns how many measurements are in range."""
    print(f"\n{name}  ({len(results)} files)")
    print(f"  {'measurement':<17}{'generated':>10}   {'your real voice':<19}")
    inside = 0
    for key, label, fmt in METRICS:
        value = float(np.mean([r[key] for r in results]))
        low, high = ranges[key]
        flag = verdict(value, low, high)
        inside += flag == "ok"
        print(f"  {label:<17}{fmt.format(value):>10}   {fmt.format(low)} to {fmt.format(high):<10} {flag}")
    return inside


def main():
    parser = argparse.ArgumentParser(description="Compare generated speech with your real recordings.")
    parser.add_argument("targets", nargs="*", help="folders or WAV files (default: every epoch in tune_outputs)")
    parser.add_argument("--similarity", action="store_true", help="also score speaker similarity (GPU)")
    args = parser.parse_args()

    groups = []
    if args.targets:
        files = []
        for target in map(Path, args.targets):
            if target.is_dir():
                groups.append((target.name, sorted(target.glob("*.wav"))))
            elif target.is_file():
                files.append(target)
            else:
                sys.exit(f"Can't find {target}")
        if files:
            groups.append(("files", files))
    else:
        folders = sorted((p for p in TUNE_DIR.glob("epoch_*") if p.is_dir()), key=lambda p: int(p.name.split("_")[1]))
        if not folders:
            sys.exit("No tune_outputs found. Pass a folder or WAV files to compare.")
        groups = [(p.name, sorted(p.glob("*.wav"))) for p in folders]

    print("Measuring your real clips...")
    real, reference_tone, ranges = real_baseline()
    print(f"  {len(real)} real clips measured. 'Your real voice' is the range the middle 80% of them fall in.")

    judge = None
    if args.similarity:
        try:
            from tune_voice import VoiceJudge
            import random
            random.seed(7)
            sample = [load(p)[0] for p in random.sample(sorted(REAL_DIR.glob("*.wav")), 40)]
            judge = VoiceJudge(sample)
            judge.whisper = None
        except Exception as err:
            print(f"(speaker similarity unavailable: {err})")

    summary = []
    for name, paths in groups:
        results = analyse_many(paths)
        if not results:
            print(f"\n{name}: no usable audio")
            continue
        add_tone_distance(results, reference_tone)
        inside = report(name, results, ranges)
        similarity = None
        if judge is not None:
            similarity = float(np.mean([judge.similarity(load(p)[0]) for p in paths]))
            print(f"  speaker similarity {similarity:.3f}   (your real clips score {judge.ceiling:.3f})")
        summary.append((name, inside, similarity))

    if len(summary) > 1:
        print("\nSummary: measurements inside your real range, out of", len(METRICS))
        for name, inside, similarity in summary:
            extra = "" if similarity is None else f"   similarity {similarity:.3f}"
            print(f"  {name:<10} {inside}{extra}")
    print("\nThese numbers describe the sound; they can't fully replace listening.")


if __name__ == "__main__":
    main()
