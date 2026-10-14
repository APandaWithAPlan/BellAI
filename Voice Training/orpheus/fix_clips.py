"""
fix_clips.py - repair clip boundaries using the original recordings.

The first clip-cutting pass trusted Whisper's word timings, which run early: many clips began
with about half a second of silence and ended while the last word was still fading out.
This finds every clip inside its original recording and re-cuts it so that it
  * starts just before the first sound (keeping about 0.12 s of lead-in)
  * ends after the last word has actually finished
  * has very long silent gaps (over 0.6 s) shortened to 0.4 s, in clips without sound tags
The text in metadata.csv is not changed.

    python tools/fix_clips.py locate <recording.wav> <clip name prefix>
    python tools/fix_clips.py cut    <recording.wav> <clip name prefix>
"""
import csv, json, sys, wave
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parent.parent / "voice_data"
CLIPS, FIXED = ROOT / "clips", ROOT / "clips_fixed"
SR = 24000
HOP = 240                                    # 10 ms


def read(path):
    with wave.open(str(path)) as w:
        assert w.getsampwidth() == 2
        a = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768
        if w.getnchannels() > 1:
            a = a.reshape(-1, w.getnchannels()).mean(axis=1)
        return a, w.getframerate()


def write(path, audio):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(audio, -1, 1) * 32767).astype(np.int16).tobytes())


def raw_at_24k(path):
    raw, rate = read(path)
    if rate == SR:
        return raw
    assert rate == 2 * SR, f"unexpected sample rate {rate}"
    taps = 127
    n = np.arange(taps) - (taps - 1) / 2
    h = np.sinc(n / 2) / 2 * np.blackman(taps)
    h /= h.sum()
    return np.convolve(raw, h.astype(np.float32), mode="same")[::2].astype(np.float32)


def rows_for(prefix):
    with open(CLIPS / "metadata.csv", encoding="utf-8", newline="") as f:
        return [r for r in list(csv.reader(f))[1:] if r[0].startswith(prefix)]


def locate_one(raw, clip, lo, hi):
    P = 12000
    if len(clip) <= P:
        probe, off = clip, 0
    else:
        energy = np.convolve(clip ** 2, np.ones(P, dtype=np.float32), mode="valid")
        off = int(np.argmax(energy)); probe = clip[off:off + P]
    seg = raw[lo:hi]
    if len(seg) <= len(probe):
        return lo, 0.0
    F = 1 << int(np.ceil(np.log2(len(seg) + len(probe))))
    cc = np.fft.irfft(np.fft.rfft(seg, F) * np.conj(np.fft.rfft(probe, F)), F)[:len(seg) - len(probe) + 1]
    cs = np.concatenate([[0.0], np.cumsum(seg.astype(np.float64) ** 2)])
    en = np.sqrt(np.maximum(cs[len(probe):] - cs[:-len(probe)], 1e-9))[:len(cc)]
    ncc = cc / (en * np.linalg.norm(probe) + 1e-9)
    k = int(np.argmax(ncc))
    return lo + k - off, float(ncc[k])


def locate(recording, prefix):
    raw = raw_at_24k(recording)
    out, pos = {}, 0
    for name, _ in rows_for(prefix):
        clip, _ = read(CLIPS / name)
        start, q = locate_one(raw, clip, max(0, pos - SR), min(len(raw), pos + len(clip) + SR * 8))
        if q < 0.9:                           # not where expected: search the whole recording
            start, q = locate_one(raw, clip, 0, len(raw))
        out[name] = [int(start), int(len(clip)), round(q, 4)]
        if q >= 0.9:
            pos = start + len(clip)
    Path(str(FIXED) + f"_{prefix}offsets.json").write_text(json.dumps(out))
    qs = [v[2] for v in out.values()]
    print(f"located {len(out)} clips; exact matches: {sum(q >= 0.9 for q in qs)}; weakest {min(qs):.2f}")


def frame_levels(x):
    n = len(x) // HOP
    return np.sqrt((x[:n * HOP].reshape(n, HOP) ** 2).mean(axis=1) + 1e-12)


def refine(raw, start, length, has_tag):
    """Return the re-cut audio for one clip, plus what was changed."""
    end = start + length
    levels = frame_levels(raw[start:end])
    speech = float(np.percentile(levels, 90))
    quiet = max(0.07 * speech, 0.0015)
    info = {}

    # --- end: carry on until the sound has really stopped (3 quiet frames in a row), at most 0.45 s
    after = frame_levels(raw[end:end + int(0.6 * SR)])
    tail = frame_levels(raw[end - 3 * HOP:end])
    new_end = end
    if tail.max() > quiet:                    # the clip ends while something is still sounding
        stop = None
        for i in range(len(after) - 2):
            if after[i:i + 3].max() < quiet:
                stop = i
                break
        if stop is not None and stop * HOP <= int(0.45 * SR):
            new_end = end + (stop + 4) * HOP
            info["end_extended_ms"] = round((new_end - end) / SR * 1000)
        else:                                 # speech runs straight on: cut at the quietest nearby point
            window = frame_levels(raw[end - 8 * HOP:end + 8 * HOP])
            new_end = end - 8 * HOP + (int(np.argmin(window)) + 1) * HOP
            info["end_moved_ms"] = round((new_end - end) / SR * 1000)

    # --- start: trim long lead-in silence, or reach back if the first sound was cut
    loud = np.where(levels > max(0.12 * speech, quiet))[0]
    first = int(loud[0]) if len(loud) else 0
    new_start = start
    if first * HOP > int(0.16 * SR):
        new_start = start + first * HOP - int(0.12 * SR)
        info["lead_trimmed_ms"] = round((new_start - start) / SR * 1000)
    elif first <= 2 and start > SR:
        before = frame_levels(raw[start - int(0.4 * SR):start])[::-1]
        for i in range(len(before) - 2):
            if before[i:i + 3].max() < quiet:
                if 0 < i <= 30:
                    new_start = start - (i + 3) * HOP
                    info["start_extended_ms"] = round((start - new_start) / SR * 1000)
                break

    audio = raw[new_start:new_end].copy()

    # --- very long silent gaps -> 0.4 s (not in clips with sound tags, where a quiet sigh may hide)
    if not has_tag:
        lv = frame_levels(audio)
        silent = lv < max(0.035 * speech, 0.001)
        pieces, cursor, i, removed = [], 0, 0, 0
        while i < len(silent):
            if silent[i]:
                j = i
                while j < len(silent) and silent[j]:
                    j += 1
                run = j - i
                if run * HOP > int(0.6 * SR) and i > 0 and j < len(silent):
                    keep = int(0.2 * SR)
                    a, b = i * HOP + keep, j * HOP - keep
                    pieces.append(audio[cursor:a]); cursor = b; removed += b - a
                i = j
            else:
                i += 1
        if removed:
            pieces.append(audio[cursor:])
            fade = 240
            joined = pieces[0]
            for p in pieces[1:]:
                ramp = np.linspace(0, 1, fade, dtype=np.float32)
                joined = np.concatenate([joined[:-fade], joined[-fade:] * (1 - ramp) + p[:fade] * ramp, p[fade:]])
            audio = joined
            info["pause_removed_ms"] = round(removed / SR * 1000)

    fade = 120                                # 5 ms fade in and out
    audio[:fade] *= np.linspace(0, 1, fade, dtype=np.float32)
    audio[-fade:] *= np.linspace(1, 0, fade, dtype=np.float32)
    return audio, info


def cut(recording, prefix):
    raw = raw_at_24k(recording)
    offsets = json.loads(Path(str(FIXED) + f"_{prefix}offsets.json").read_text())
    FIXED.mkdir(exist_ok=True)
    changed = {"end_extended_ms": [], "end_moved_ms": [], "lead_trimmed_ms": [], "start_extended_ms": [], "pause_removed_ms": []}
    kept_as_is, before, after = 0, 0.0, 0.0
    for name, text in rows_for(prefix):
        start, length, q = offsets[name]
        original, _ = read(CLIPS / name)
        before += len(original) / SR
        if q < 0.9 or start < 0:              # hand-edited or not found: leave exactly as it is
            write(FIXED / name, original); kept_as_is += 1; after += len(original) / SR
            continue
        audio, info = refine(raw, start, length, "<" in text)
        if len(audio) < SR:                   # never produce a clip under one second
            write(FIXED / name, original); kept_as_is += 1; after += len(original) / SR
            continue
        write(FIXED / name, audio); after += len(audio) / SR
        for k, v in info.items():
            changed[k].append(v)
    print(f"{prefix}: {before / 60:.1f} min -> {after / 60:.1f} min; left untouched: {kept_as_is}")
    for k, v in changed.items():
        if v:
            print(f"  {k:<18} {len(v):>4} clips, median {int(np.median(v))} ms")


if __name__ == "__main__":
    {"locate": locate, "cut": cut}[sys.argv[1]](sys.argv[2], sys.argv[3])
