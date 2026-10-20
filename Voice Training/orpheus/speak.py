"""Generate speech with the trained Orpheus LoRA (slow, no Ollama needed).

Usage: python speak.py ["text"] [--out file.wav]
"""

import argparse
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent  # the orpheus folder
ROOT = HERE.parent  # the Voice Training folder
MODELS = HERE / "models"
OUTPUTS = HERE / "outputs"
LORA_DIR = MODELS / "bella_voice_lora"  # where train_voice.py saves your voice
VOICE = "bella"  # the speaker name used during training
SAMPLE_RATE = 24000

# Orpheus special tokens
START_OF_HUMAN, END_OF_HUMAN = 128259, 128260
START_OF_SPEECH, END_OF_SPEECH = 128257, 128258
BEGIN_OF_TEXT, END_OF_TEXT = 128000, 128009
AUDIO_OFFSET = 128266  # first audio-code token
CODEBOOK = 4096  # codes per SNAC codebook slot


def frames_to_snac_layers(tokens):
    """Turn a flat list of Orpheus audio tokens"""
    layer1, layer2, layer3 = [], [], []
    for i in range(len(tokens) // 7):
        frame = [tokens[7 * i + slot] - AUDIO_OFFSET - slot * CODEBOOK for slot in range(7)]
        if any(c < 0 or c >= CODEBOOK for c in frame):
            continue  # skip a malformed frame instead of crashing
        layer1.append(frame[0])
        layer2.extend([frame[1], frame[4]])
        layer3.extend([frame[2], frame[3], frame[5], frame[6]])
    return layer1, layer2, layer3


def synthesize(model, tokenizer, snac_model, text, voice=VOICE, max_new_tokens=1200):
    """Generate speech for `text`"""
    import torch

    prompt = f"{voice}: {text}" if voice else text
    text_ids = tokenizer.encode(prompt, add_special_tokens=False)
    ids = torch.tensor(
        [[START_OF_HUMAN, BEGIN_OF_TEXT] + text_ids + [END_OF_TEXT, END_OF_HUMAN]],
        device=next(model.parameters()).device,
    )

    with torch.inference_mode(), torch.autocast("cuda", dtype=torch.bfloat16):
        out = model.generate(
            input_ids=ids,
            attention_mask=torch.ones_like(ids),
            max_new_tokens=max_new_tokens,  # 1200 tokens is about 14 seconds of speech
            do_sample=True,
            temperature=0.6,
            top_p=0.95,
            repetition_penalty=1.1,
            eos_token_id=END_OF_SPEECH,
            use_cache=True,
        )[0].tolist()

    if START_OF_SPEECH in out:  # keep only what comes after "start of speech"
        out = out[len(out) - out[::-1].index(START_OF_SPEECH):]
    audio_tokens = [t for t in out if t >= AUDIO_OFFSET]
    layer1, layer2, layer3 = frames_to_snac_layers(audio_tokens)
    if not layer1:
        raise RuntimeError("The model produced no audio for that text. Try again or rephrase it.")

    device = next(snac_model.parameters()).device
    codes = [torch.tensor(layer, device=device).unsqueeze(0) for layer in (layer1, layer2, layer3)]
    with torch.inference_mode():
        audio = snac_model.decode(codes)
    return audio.squeeze().float().cpu().numpy()


def split_text(text, limit=160):
    """Break long text into sentence-sized pieces the model can speak in one go"""
    import re

    sentences = re.findall(r"[^.!?]+[.!?]+[\"')\]]*|[^.!?]+$", text.strip())
    pieces, current = [], ""
    for sentence in (s.strip() for s in sentences):
        chunks = []
        while len(sentence) > limit:  # a single huge sentence: cut at a comma or space
            cut = max(sentence.rfind(", ", 0, limit), sentence.rfind(" ", 0, limit))
            cut = cut if cut > 0 else limit - 1
            chunks.append(sentence[:cut + 1].strip())
            sentence = sentence[cut + 1:].strip()
        if sentence:
            chunks.append(sentence)
        for chunk in chunks:
            if current and len(current) + len(chunk) + 1 > limit:
                pieces.append(current)
                current = chunk
            else:
                current = (current + " " + chunk).strip()
    if current:
        pieces.append(current)
    return pieces


def speak_long(model, tokenizer, snac_model, text, voice=VOICE, pause=0.3):
    """Speak text of any length by generating it a few sentences at a time"""
    import numpy as np

    gap = np.zeros(int(pause * SAMPLE_RATE), dtype=np.float32)
    parts = []
    for piece in split_text(text):
        parts.extend([synthesize(model, tokenizer, snac_model, piece, voice), gap])
    return np.concatenate(parts[:-1]) if parts else gap


def load_base_model(name):
    """Load the Orpheus language model onto the GPU in bfloat16"""
    import torch
    from transformers import AutoModelForCausalLM

    try:
        model = AutoModelForCausalLM.from_pretrained(name, dtype=torch.bfloat16)
    except TypeError:  # older transformers versions use the old argument
        model = AutoModelForCausalLM.from_pretrained(name, torch_dtype=torch.bfloat16)
    return model.to("cuda")


def load_voice():
    """Load the fine-tuned model, its tokenizer, and the SNAC audio decoder"""
    import json
    import torch
    from peft import PeftModel
    from snac import SNAC
    from transformers import AutoTokenizer

    if not (LORA_DIR / "adapter_config.json").exists():
        sys.exit(f"Can't find a trained voice in '{LORA_DIR.name}'. Run train_voice.py first.")
    if not torch.cuda.is_available():
        sys.exit("PyTorch can't see your GPU.")
    base_name = json.loads((LORA_DIR / "adapter_config.json").read_text())["base_model_name_or_path"]
    tokenizer = AutoTokenizer.from_pretrained(str(LORA_DIR))
    model = PeftModel.from_pretrained(load_base_model(base_name), str(LORA_DIR))
    model = model.merge_and_unload().eval()  # bake your voice into the model for faster speech
    snac_model = SNAC.from_pretrained("hubertsiuzdak/snac_24khz").to("cuda").eval()
    return model, tokenizer, snac_model


def play(path):
    """Play a WAV file through the speakers"""
    try:
        import winsound
        winsound.PlaySound(str(path), winsound.SND_FILENAME)
    except Exception:
        pass


def main():
    parser = argparse.ArgumentParser(description="Speak text in your trained voice.")
    parser.add_argument("text", nargs="?", help="what to say (in quotes). Leave it out to keep typing lines.")
    parser.add_argument("--out", default=str(OUTPUTS / "test_outputs" / "speak.wav"))
    parser.add_argument("--quiet", action="store_true", help="save the file without playing it")
    args = parser.parse_args()

    model, tokenizer, snac_model = load_voice()
    import time
    import soundfile as sf

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)

    def say(text):
        started = time.time()
        audio = speak_long(model, tokenizer, snac_model, text)
        took = time.time() - started
        sf.write(str(out), audio, SAMPLE_RATE)
        print(f"{len(audio) / SAMPLE_RATE:.1f}s of speech, generated in {took:.1f}s. Saved to {out}")
        if not args.quiet:
            play(out)

    if args.text:
        return say(args.text)

    print("The voice is loaded and will stay loaded. Type a line and press Enter. Type quit to stop.")
    while True:
        try:
            text = input("Say> ").strip()
        except (EOFError, KeyboardInterrupt):
            break
        if text.lower() in ("quit", "exit", "q"):
            break
        if text:
            try:
                say(text)
            except Exception as err:
                print(f"That one failed: {err}")


if __name__ == "__main__":
    main()
