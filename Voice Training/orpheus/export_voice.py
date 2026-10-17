"""
export_voice.py - package your trained voice for Ollama, so it can speak in real time.

What it does
  1. Bakes your saved voice (bella_voice_lora) into the Orpheus base model  -> bella_voice_merged
  2. Converts that to a single GGUF file, the format Ollama runs           -> bella_voice.gguf
  3. Asks Ollama to import it as the model "bellai-voice"

Run (from the orpheus folder), with Ollama installed and running:
    python export_voice.py

Run it again whenever you pick a different epoch or retrain. Then use fast_speak.py.
Steps that are already done are skipped. Use --redo to force everything again.

A smaller, faster version:
    python export_voice.py --fast
This also builds a 4-bit model called "bellai-voice-q4" (about 2 GB). It generates faster,
at a cost in quality. Use it with:  python fast_speak.py --model bellai-voice-q4

In-between sizes (better than 4-bit, faster than the normal 8-bit):
    python export_voice.py --q6      ->  "bellai-voice-q6"  (6-bit, closest to the 8-bit sound)
    python export_voice.py --q5      ->  "bellai-voice-q5"  (5-bit)

Full quality (no shrinking, about twice as slow as 8-bit, so live playback may stutter):
    python export_voice.py --f16     ->  "bellai-voice-f16" (16-bit)
"""

import io
import json
import shutil
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

from speak import LORA_DIR

HERE = Path(__file__).resolve().parent          # the orpheus folder
ROOT = HERE.parent                               # the Voice Training folder
MODELS = HERE / "models"
OUTPUTS = HERE / "outputs"
MERGED = MODELS / "bella_voice_merged"
GGUF = MODELS / "bella_voice.gguf"
MODELFILE = MODELS / "Modelfile"
OLLAMA_NAME = "bellai-voice"

# The GGUF converter comes from the llama.cpp project. Only its Python converter is downloaded.
LLAMA_TAG = "b11559"
LLAMA_ZIP = f"https://github.com/ggml-org/llama.cpp/archive/refs/tags/{LLAMA_TAG}.zip"
TOOLS = HERE / "tools" / f"llama_cpp_{LLAMA_TAG}"
WANTED = ("convert_hf_to_gguf.py", "conversion/", "gguf-py/gguf/")

GGUF_F16 = MODELS / "bella_voice_f16.gguf"
SIZES = {  # flag: (llama.cpp type, short name, description)
    "--fast": ("Q4_K_M", "q4", "4-bit"),
    "--q5": ("Q5_K_M", "q5", "5-bit"),
    "--q6": ("Q6_K", "q6", "6-bit"),
}
BIN_ZIP = f"https://github.com/ggml-org/llama.cpp/releases/download/{LLAMA_TAG}/llama-{LLAMA_TAG}-bin-win-cpu-x64.zip"
BIN_DIR = HERE / "tools" / f"llama_bin_{LLAMA_TAG}"

MODELFILE_TEXT = """FROM ./{gguf}
TEMPLATE {{ .Prompt }}
PARAMETER temperature 0.6
PARAMETER top_p 0.95
PARAMETER repeat_penalty 1.1
PARAMETER num_ctx 2048
PARAMETER num_predict 1200
PARAMETER stop <custom_token_2>
"""

# Runs llama.cpp's converter with two small safety nets for this model's tokenizer.
RUNNER = r'''
import runpy, sys, types
root = sys.argv[1]
sys.path.insert(0, root)
sys.path.insert(1, root + "/gguf-py")
try:
    import sentencepiece  # noqa: F401
except ImportError:                      # not needed for this model; a stand-in keeps the converter going
    stub = types.ModuleType("sentencepiece")
    stub.SentencePieceProcessor = type("SentencePieceProcessor", (), {})
    sys.modules["sentencepiece"] = stub
from conversion import base
_original = base.TextModel.get_vocab_base_pre
def _pre(self, tokenizer):
    try:
        return _original(self, tokenizer)
    except NotImplementedError:          # Orpheus uses the Llama 3 tokenizer
        print("Tokenizer not auto-recognised; using the Llama 3 setting.")
        return "llama-bpe"
base.TextModel.get_vocab_base_pre = _pre
sys.argv = [root + "/convert_hf_to_gguf.py"] + sys.argv[2:]
runpy.run_path(sys.argv[0], run_name="__main__")
'''


def newer(target, source):
    return target.exists() and target.stat().st_mtime >= source.stat().st_mtime


def merge():
    import torch
    from peft import PeftModel
    from transformers import AutoModelForCausalLM, AutoTokenizer

    base_name = json.loads((LORA_DIR / "adapter_config.json").read_text())["base_model_name_or_path"]
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print("Loading the base model at full precision...")
    try:
        base = AutoModelForCausalLM.from_pretrained(base_name, dtype=torch.float32)
    except TypeError:
        base = AutoModelForCausalLM.from_pretrained(base_name, torch_dtype=torch.float32)
    print("Baking in your voice...")
    model = PeftModel.from_pretrained(base.to(device), str(LORA_DIR)).merge_and_unload()
    model = model.half().cpu()
    if MERGED.exists():
        shutil.rmtree(MERGED)
    print(f"Saving to {MERGED.name} (about 7 GB)...")
    model.save_pretrained(str(MERGED), safe_serialization=True)
    AutoTokenizer.from_pretrained(str(LORA_DIR)).save_pretrained(str(MERGED))
    print("Merged model saved.")


def extract_converter(zip_bytes, destination):
    """Unpack just the converter files from a llama.cpp source zip."""
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as archive:
        for member in archive.infolist():
            inner = member.filename.split("/", 1)[1] if "/" in member.filename else ""
            if member.is_dir() or not inner.startswith(WANTED):
                continue
            target = destination / inner
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.read(member))
    if not (destination / "convert_hf_to_gguf.py").exists():
        raise RuntimeError("The download didn't contain the converter.")


def get_converter():
    if (TOOLS / "convert_hf_to_gguf.py").exists():
        return
    print("Downloading the GGUF converter from the llama.cpp project...")
    try:
        with urllib.request.urlopen(LLAMA_ZIP, timeout=300) as response:
            data = response.read()
    except Exception as err:
        sys.exit(f"Couldn't download {LLAMA_ZIP}\n({err})\nCheck your internet connection and run this again.")
    extract_converter(data, TOOLS)


def convert(target=GGUF, outtype="q8_0", label="8-bit"):
    get_converter()
    print(f"Converting to GGUF ({label}). This takes a few minutes...")
    partial = target.with_suffix(".partial.gguf")
    result = subprocess.run(
        [sys.executable, "-c", RUNNER, TOOLS.as_posix(), str(MERGED), "--outfile", str(partial), "--outtype", outtype],
        cwd=str(HERE),
    )
    if result.returncode != 0 or not partial.exists():
        partial.unlink(missing_ok=True)
        sys.exit("\nThe GGUF conversion failed. Copy the error above and send it over.")
    partial.replace(target)
    print(f"Saved {target.name} ({target.stat().st_size / 1e9:.1f} GB).")


def get_quantizer():
    """Find (or download) llama.cpp's quantize program, which shrinks a GGUF file."""
    found = list(BIN_DIR.rglob("llama-quantize.exe"))
    if found:
        return found[0]
    print("Downloading the llama.cpp quantize tool (about 19 MB)...")
    try:
        with urllib.request.urlopen(BIN_ZIP, timeout=300) as response:
            data = response.read()
    except Exception as err:
        sys.exit(f"Couldn't download {BIN_ZIP}\n({err})\nCheck your internet connection and run this again.")
    BIN_DIR.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        archive.extractall(BIN_DIR)
    found = list(BIN_DIR.rglob("llama-quantize.exe"))
    if not found:
        sys.exit("The download didn't contain llama-quantize.exe.")
    return found[0]


def quantize(kind, target, label):
    exe = get_quantizer()
    print(f"Shrinking to {label} ({kind}). This takes a minute or two...")
    partial = target.with_suffix(".partial.gguf")
    result = subprocess.run([str(exe), str(GGUF_F16), str(partial), kind], cwd=str(exe.parent))
    if result.returncode != 0 or not partial.exists():
        partial.unlink(missing_ok=True)
        sys.exit("\nShrinking the model failed. Copy the error above and send it over.")
    partial.replace(target)
    print(f"Saved {target.name} ({target.stat().st_size / 1e9:.1f} GB).")


def import_into_ollama(gguf=GGUF, name=OLLAMA_NAME, modelfile=MODELFILE):
    modelfile.write_text(MODELFILE_TEXT.replace("{gguf}", gguf.name), encoding="utf-8")
    command = f"ollama create {name} -f {modelfile.name}"
    ollama = shutil.which("ollama")
    if ollama is None:
        print("\nOllama isn't installed (or isn't on your PATH). Install it from https://ollama.com,")
        print(f"then run this from the Voice Training folder:\n    {command}")
        return
    print(f"\nImporting '{name}' into Ollama...")
    result = subprocess.run([ollama, "create", name, "-f", str(modelfile)], cwd=str(MODELS))
    if result.returncode == 0:
        extra = "" if name == OLLAMA_NAME else f" --model {name}"
        print(f"\nDone. Ollama now has the model '{name}'. Next: python fast_speak.py{extra}")
    else:
        print(f"\nOllama couldn't import the model. Make sure the Ollama app is running, then try:\n    {command}")


def main():
    redo = "--redo" in sys.argv
    adapter = LORA_DIR / "adapter_model.safetensors"
    if not adapter.exists():
        sys.exit(f"Can't find a trained voice in '{LORA_DIR.name}'. Run tune_voice.py first.")

    merged_weights = MERGED / "model.safetensors"
    if redo or not newer(merged_weights, adapter):
        merge()
    else:
        print("Merged model is up to date, skipping that step.")
    if "--f16" in sys.argv:
        if redo or not newer(GGUF_F16, merged_weights):
            convert(GGUF_F16, "f16", "16-bit")
        else:
            print("16-bit GGUF is up to date, skipping that step.")
        import_into_ollama(GGUF_F16, f"{OLLAMA_NAME}-f16", MODELS / "Modelfile.f16")
        return
    chosen = [flag for flag in SIZES if flag in sys.argv]
    if chosen:
        kind, short, label = SIZES[chosen[0]]
        target = MODELS / f"bella_voice_{short}.gguf"
        if redo or not newer(GGUF_F16, merged_weights):
            convert(GGUF_F16, "f16", "16-bit, the starting point for shrinking")
        else:
            print("16-bit GGUF is up to date, skipping that step.")
        if redo or not newer(target, GGUF_F16):
            quantize(kind, target, label)
        else:
            print(f"{label} GGUF is up to date, skipping that step.")
        import_into_ollama(target, f"{OLLAMA_NAME}-{short}", MODELS / f"Modelfile.{short}")
        return
    if redo or not newer(GGUF, merged_weights):
        convert()
    else:
        print("GGUF file is up to date, skipping that step.")
    import_into_ollama()


if __name__ == "__main__":
    main()
