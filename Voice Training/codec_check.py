"""
codec_check.py - hear the best quality this kind of voice model can reach.

Orpheus doesn't produce sound directly. It produces codes, and a codec called SNAC turns
those codes into audio. That codec has its own "compressed" character. This script runs
three of your REAL recordings through the codec and back, so you can hear that limit:

    test_outputs/codec_1_original.wav      your real recording
    test_outputs/codec_1_through_codec.wav the same recording after the codec

If the "through_codec" files have the same compressed sound you hear in the generated
voice, that part comes from the codec and no amount of training will remove it.

Run (from the Voice Training folder):
    python codec_check.py
"""

import csv
import random
from pathlib import Path

HERE = Path(__file__).resolve().parent
CLIPS = HERE / "voice_data" / "clips"
OUT = HERE / "test_outputs"


def main():
    import soundfile as sf
    import torch
    from snac import SNAC

    device = "cuda" if torch.cuda.is_available() else "cpu"
    snac = SNAC.from_pretrained("hubertsiuzdak/snac_24khz").to(device).eval()
    with open(CLIPS / "metadata.csv", encoding="utf-8-sig", newline="") as f:
        rows = [r for r in list(csv.reader(f))[1:] if len(r) == 2 and len(r[1]) > 60]
    random.seed(11)
    OUT.mkdir(exist_ok=True)
    for number, (name, text) in enumerate(random.sample(rows, 3), 1):
        audio, rate = sf.read(str(CLIPS / name), dtype="float32", always_2d=True)
        wave = torch.from_numpy(audio.mean(axis=1)).reshape(1, 1, -1).to(device)
        with torch.inference_mode():
            rebuilt = snac.decode(snac.encode(wave)).squeeze().float().cpu().numpy()
        sf.write(str(OUT / f"codec_{number}_original.wav"), audio.mean(axis=1), rate)
        sf.write(str(OUT / f"codec_{number}_through_codec.wav"), rebuilt[: audio.shape[0]], rate)
        print(f"{number}. {text}")
    print(f"\nSaved 6 files in {OUT}. Compare each original with its through_codec version.")


if __name__ == "__main__":
    main()
