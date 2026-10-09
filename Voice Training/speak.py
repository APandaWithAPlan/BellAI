"""
speak.py - make your trained voice say something.

Run (from the Voice Training folder), after train_voice.py has finished:
    python speak.py "Good morning! Beanie is asleep on the couch."
    python speak.py "Hello <laugh> that tickles." --out hello.wav

The audio is saved as a WAV file (default: test_outputs/speak.wav).
Sound tags you can use in the text: <laugh> <chuckle> <sigh> <gasp> <yawn> <groan> <cough> <sniffle>
"""

import argparse
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
LORA_DIR = HERE / "bella_voice_lora"      # where train_voice.py saves your voice
VOICE = "bella"                           # the speaker name used during training
SAMPLE_RATE = 24000

# Orpheus special tokens (Llama-3 vocabulary is 128256 tokens; these come after it)
START_OF_HUMAN, END_OF_HUMAN = 128259, 128260
START_OF_SPEECH, END_OF_SPEECH = 128257, 128258
BEGIN_OF_TEXT, END_OF_TEXT = 128000, 128009
AUDIO_OFFSET = 128266                     # first audio-code token
CODEBOOK = 4096                           # codes per SNAC codebook slot


def frames_to_snac_layers(tokens):
    """Turn a flat list of Orpheus audio tokens (7 per frame) into SNAC's 3 code layers."""
    layer1, layer2, layer3 = [], [], []
    for i in range(len(tokens) // 7):
        frame = [tokens[7 * i + slot] - AUDIO_OFFSET - slot * CODEBOOK for slot in range(7)]
        if any(c < 0 or c >= CODEBOOK for c in frame):
            continue                       # skip a malformed frame instead of crashing
        layer1.append(frame[0])
        layer2.extend([frame[1], frame[4]])
        layer3.extend([frame[2], frame[3], frame[5], frame[6]])
    return layer1, layer2, layer3


def synthesize(model, tokenizer, snac_model, text, voice=VOICE, max_new_tokens=1200):
    """Generate speech for `text`. Returns a float32 numpy array at 24 kHz."""
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
            max_new_tokens=max_new_tokens,   # 1200 tokens is about 14 seconds of speech
            do_sample=True,
            temperature=0.6,
            top_p=0.95,
            repetition_penalty=1.1,
            eos_token_id=END_OF_SPEECH,
            use_cache=True,
        )[0].tolist()

    if START_OF_SPEECH in out:               # keep only what comes after "start of speech"
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


def load_base_model(name):
    """Load the Orpheus language model onto the GPU in bfloat16."""
    import torch
    from transformers import AutoModelForCausalLM

    try:
        model = AutoModelForCausalLM.from_pretrained(name, dtype=torch.bfloat16)
    except TypeError:                        # older transformers versions use the old argument name
        model = AutoModelForCausalLM.from_pretrained(name, torch_dtype=torch.bfloat16)
    return model.to("cuda")


def load_voice():
    """Load the fine-tuned model, its tokenizer, and the SNAC audio decoder."""
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


def main():
    parser = argparse.ArgumentParser(description="Speak text in your trained voice.")
    parser.add_argument("text", help="what to say (put it in quotes)")
    parser.add_argument("--out", default=str(HERE / "test_outputs" / "speak.wav"))
    args = parser.parse_args()

    model, tokenizer, snac_model = load_voice()
    import soundfile as sf

    audio = synthesize(model, tokenizer, snac_model, args.text)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    sf.write(str(out), audio, SAMPLE_RATE)
    print(f"Saved {len(audio) / SAMPLE_RATE:.1f} seconds of audio to {out}")


if __name__ == "__main__":
    main()
