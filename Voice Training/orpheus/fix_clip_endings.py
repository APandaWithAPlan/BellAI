"""
fix_clip_endings.py - let every clip finish its last sound.

The clip cutter judged "silence" by loudness only. A trailing "s", "sh" or "f" is a quiet hiss,
so many clips were cut while that hiss was still going, and the voice models learned to chop
the ends off words. This finds where each clip ends inside the original recording and extends
it until both the loudness AND the hiss have died away (at most 0.6 s). Nothing else in the
clip changes.

    python fix_clip_endings.py "..\\voice_data\\raw\\<recording>.wav"            (dry run, report only)
    python fix_clip_endings.py "..\\voice_data\\raw\\<recording>.wav" --apply    (originals backed up first)
"""
import csv, shutil, sys
from pathlib import Path
import numpy as np
from fix_clips import raw_at_24k, read, write, SR, HOP

ROOT = Path(__file__).resolve().parent.parent / "voice_data"
CLIPS = ROOT / "clips"
BACKUP = ROOT / "removed_clips" / "before_ending_fix"
FADE = 240                                     # 10 ms fade-out at the new end


def levels(x):
    n = len(x) // HOP
    return np.sqrt((x[:n * HOP].reshape(n, HOP) ** 2).mean(axis=1) + 1e-12)


def hiss(x):                                   # high-frequency energy, where "s" lives
    return levels(np.diff(x, prepend=x[:1]))


def find_end(raw, clip, lo, hi):
    """Where the end of `clip` sits in raw[lo:hi]. Returns (raw index of clip end, match quality)."""
    P = min(12000, len(clip) - 2 * FADE)
    probe = clip[-(P + FADE):-FADE]
    seg = raw[lo:hi]
    if len(seg) <= P:
        return None, 0.0
    F = 1 << int(np.ceil(np.log2(len(seg) + P)))
    cc = np.fft.irfft(np.fft.rfft(seg, F) * np.conj(np.fft.rfft(probe, F)), F)[:len(seg) - P + 1]
    cs = np.concatenate([[0.0], np.cumsum(seg.astype(np.float64) ** 2)])
    en = np.sqrt(np.maximum(cs[P:] - cs[:-P], 1e-12))[:len(cc)]
    ncc = cc / (en * np.linalg.norm(probe) + 1e-9)
    k = int(np.argmax(ncc))
    return lo + k + P + FADE, float(ncc[k])


def new_ending(raw, end):
    """How many samples to add after `end` so the last sound (including hiss) has finished."""
    around = raw[max(0, end - 3 * SR):end + 3 * SR]
    loud_floor = np.percentile(levels(around), 10)
    hiss_floor = np.percentile(hiss(around), 10)
    after = raw[end - 2 * HOP:end + int(0.7 * SR)]
    lv, hv = levels(after), hiss(after)
    sounding = (lv > loud_floor * 4) | (hv > hiss_floor * 4)
    if not sounding[:3].any():
        return 0                               # already ends in silence
    for i in range(2, len(sounding) - 4):
        if not sounding[i:i + 4].any():        # 40 ms of real quiet
            add = (i - 2 + 3) * HOP            # plus 30 ms of the quiet itself
            return add if add <= int(0.6 * SR) else None
    return None                                # never went quiet: speech runs straight on, leave it


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    apply = "--apply" in sys.argv
    raw = raw_at_24k(sys.argv[1])
    with open(CLIPS / "metadata.csv", encoding="utf-8", newline="") as f:
        rows = [r for r in list(csv.reader(f))[1:] if (CLIPS / r[0]).exists()]
    if apply:
        BACKUP.mkdir(parents=True, exist_ok=True)
    pos, added, unchanged, unmatched, runon = 0, [], 0, 0, 0
    for name, text in rows:
        clip, _ = read(CLIPS / name)
        end, q = find_end(raw, clip, max(0, pos - 2 * SR), min(len(raw), pos + len(clip) * 2 + 30 * SR))
        if q < 0.9:
            end, q = find_end(raw, clip, max(0, pos - 120 * SR), min(len(raw), pos + 600 * SR))
        if end is None or q < 0.9:
            unmatched += 1
            continue
        pos = end
        add = new_ending(raw, end)
        if add is None:
            runon += 1
            continue
        if add == 0:
            unchanged += 1
            continue
        added.append(add / SR * 1000)
        if apply:
            fixed = np.concatenate([clip[:-FADE], raw[end - FADE:end + add]]).astype(np.float32)
            fixed[-FADE:] *= np.linspace(1, 0, FADE, dtype=np.float32)
            shutil.copy(CLIPS / name, BACKUP / name)
            write(CLIPS / name, fixed)
    print(f"{len(rows)} clips: {len(added)} {'extended' if apply else 'would be extended'} "
          f"(median {np.median(added) if added else 0:.0f} ms, max {max(added) if added else 0:.0f} ms), "
          f"{unchanged} already fine, {runon} run straight into the next word (left alone), {unmatched} not found (left alone)")
    if apply:
        print(f"Originals backed up in {BACKUP}")


if __name__ == "__main__":
    main()
