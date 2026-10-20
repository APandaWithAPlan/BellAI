# installs the bell voice from the zip into a gpt-sovits folder
# usage: python setup_voice.py <path to GPT-SoVITS>
# safe to run twice
import shutil
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ZIP = HERE / "BellAiVoiceGPTSoVITSModel.zip"
ANCHOR = "tts_pipeline = TTS(tts_config)"
PATCH = """
# --- bell voice: stops sentence endings getting cut off (from setup_voice.py)
from bellai_tail_fix import install_tail_hold
install_tail_hold(tts_pipeline)
_bell_init_vits = tts_pipeline.init_vits_weights
def _bell_init_vits_weights(*args, **kwargs):  # new model after /set_sovits_weights, so redo it
    result = _bell_init_vits(*args, **kwargs)
    install_tail_hold(tts_pipeline)
    return result
tts_pipeline.init_vits_weights = _bell_init_vits_weights
# --- end bell voice
"""


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__ or "usage: python setup_voice.py <path to GPT-SoVITS>")
    gsv = Path(sys.argv[1]).resolve()
    api = gsv / "api_v2.py"
    if not api.is_file():
        sys.exit(f"no api_v2.py in {gsv}")

    # where each file in the zip goes
    targets = {
        "gpt.ckpt": gsv / "GPT_weights_v2" / "gpt.ckpt",
        "sovits.pth": gsv / "SoVITS_weights_v2" / "sovits.pth",
        "bellai_tail_fix.py": gsv / "bellai_tail_fix.py",
        "voice.json": HERE / "voice" / "voice.json",
        "reference.wav": HERE / "voice" / "reference.wav",
    }
    with zipfile.ZipFile(ZIP) as z:
        for name, dest in targets.items():
            dest.parent.mkdir(parents=True, exist_ok=True)
            with z.open(name) as src, open(dest, "wb") as out:
                shutil.copyfileobj(src, out)
            print("wrote", dest)

    # patch api_v2 (once)
    code = api.read_text(encoding="utf-8")
    if "bellai_tail_fix" in code:
        print("api_v2.py already patched")
    elif ANCHOR not in code:
        sys.exit(f"couldn't find '{ANCHOR}' in api_v2.py, add the tail fix by hand (see bellai_tail_fix.py)")
    else:
        shutil.copy2(api, api.with_name("api_v2.py.bak"))
        api.write_text(code.replace(ANCHOR, ANCHOR + "\n" + PATCH, 1), encoding="utf-8")
        print("patched api_v2.py (backup: api_v2.py.bak)")

    print("\ndone. run start_voice.bat next")
    print("api_v2 on another machine? set BELL_REF_AUDIO to reference.wav's path over there")


if __name__ == "__main__":
    main()
