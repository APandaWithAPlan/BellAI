"""
train_voice.py - fine-tune Orpheus 3B on your voice clips.

Setup (once):
    pip install snac soundfile peft

Run (from the Voice Training folder):
    python train_voice.py

What it does
  1. Reads voice_data/clips/metadata.csv and the WAV clips next to it
  2. Turns each clip into audio tokens with the SNAC codec
  3. Fine-tunes unsloth/orpheus-3b-0.1-ft with LoRA (using transformers + peft)
  4. Saves your voice to the folder bella_voice_lora
  5. Speaks a few test sentences into test_outputs/ so you can hear the result

Options
    python train_voice.py --epochs 5     train longer (default 3)
    python train_voice.py --rank 32      smaller LoRA (default 64)
"""

import argparse
import csv
import sys
from pathlib import Path

from speak import (AUDIO_OFFSET, BEGIN_OF_TEXT, CODEBOOK, END_OF_HUMAN, END_OF_SPEECH, END_OF_TEXT,
                   LORA_DIR, SAMPLE_RATE, START_OF_HUMAN, START_OF_SPEECH, VOICE, load_base_model,
                   synthesize)

HERE = Path(__file__).resolve().parent
CLIPS = HERE / "voice_data" / "clips"
BASE_MODEL = "unsloth/orpheus-3b-0.1-ft"
MAX_TOKENS = 2048
START_OF_AI, END_OF_AI, PAD = 128261, 128262, 128263

TEST_LINES = [
    "Good morning! I'm awake, I'm listening, and I'm only a little bit covered in cat hair.",
    "Your timer is set for ten minutes, starting now.",
    "Beanie knocked the plant over again. <sigh> I'll add potting soil to the shopping list.",
]


def read_metadata():
    path = CLIPS / "metadata.csv"
    if not path.exists():
        sys.exit(f"Can't find {path}. Run prepare_dataset.py first.")
    with open(path, encoding="utf-8-sig", newline="") as f:
        rows = list(csv.reader(f))[1:]
    items = []
    for row in rows:
        if len(row) != 2 or not row[1].strip():
            sys.exit(f"Bad row in metadata.csv (expected file_name,text): {row}")
        if not (CLIPS / row[0]).exists():
            sys.exit(f"metadata.csv lists {row[0]}, but that file isn't in {CLIPS}")
        items.append((row[0], row[1].strip()))
    return items


def interleave(layer1, layer2, layer3):
    """SNAC's 3 code layers -> Orpheus's flat token order, 7 tokens per frame."""
    tokens = []
    for i in range(len(layer1)):
        frame = [layer1[i], layer2[2 * i], layer3[4 * i], layer3[4 * i + 1],
                 layer2[2 * i + 1], layer3[4 * i + 2], layer3[4 * i + 3]]
        tokens.extend(code + AUDIO_OFFSET + slot * CODEBOOK for slot, code in enumerate(frame))
    return tokens


def drop_repeated_frames(tokens):
    """Remove frames whose first code repeats the previous frame's (as the Orpheus recipe does)."""
    kept = tokens[:7]
    for i in range(7, len(tokens), 7):
        if tokens[i] != kept[-7]:
            kept.extend(tokens[i:i + 7])
    return kept


def build_example(text_ids, audio_tokens):
    ids = ([START_OF_HUMAN] + text_ids + [END_OF_TEXT, END_OF_HUMAN, START_OF_AI, START_OF_SPEECH]
           + audio_tokens + [END_OF_SPEECH, END_OF_AI])
    return {"input_ids": ids, "labels": list(ids), "attention_mask": [1] * len(ids)}


def collate(batch):
    import torch

    longest = max(len(b["input_ids"]) for b in batch)
    out = {"input_ids": [], "labels": [], "attention_mask": []}
    for b in batch:
        pad = longest - len(b["input_ids"])
        out["input_ids"].append(b["input_ids"] + [PAD] * pad)
        out["labels"].append(b["labels"] + [-100] * pad)
        out["attention_mask"].append(b["attention_mask"] + [0] * pad)
    return {k: torch.tensor(v, dtype=torch.long) for k, v in out.items()}


def main():
    parser = argparse.ArgumentParser(description="Fine-tune Orpheus on your voice.")
    parser.add_argument("--epochs", type=float, default=3)
    parser.add_argument("--rank", type=int, default=64)
    parser.add_argument("--lr", type=float, default=2e-4)
    args = parser.parse_args()

    items = read_metadata()
    print(f"Found {len(items)} clips.")

    import soundfile as sf
    import torch
    from peft import LoraConfig, get_peft_model
    from snac import SNAC
    from transformers import AutoTokenizer, Trainer, TrainingArguments

    if not torch.cuda.is_available():
        sys.exit("PyTorch can't see your GPU. Reinstall the CUDA build of PyTorch from pytorch.org.")

    tokenizer = AutoTokenizer.from_pretrained(BASE_MODEL)
    model = get_peft_model(
        load_base_model(BASE_MODEL),
        LoraConfig(
            r=args.rank,
            lora_alpha=args.rank,
            lora_dropout=0.0,
            bias="none",
            target_modules=["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"],
            task_type="CAUSAL_LM",
        ),
    )
    model.print_trainable_parameters()

    print("Converting clips to audio tokens...")
    snac_model = SNAC.from_pretrained("hubertsiuzdak/snac_24khz").to("cuda").eval()
    examples, skipped = [], 0
    for name, text in items:
        audio, rate = sf.read(str(CLIPS / name), dtype="float32", always_2d=True)
        if rate != SAMPLE_RATE:
            sys.exit(f"{name} is {rate} Hz, expected {SAMPLE_RATE}. Re-run prepare_dataset.py.")
        wave = torch.from_numpy(audio.mean(axis=1)).reshape(1, 1, -1).to("cuda")
        with torch.inference_mode():
            codes = snac_model.encode(wave)
        layers = [c[0].tolist() for c in codes]
        audio_tokens = drop_repeated_frames(interleave(*layers))
        text_ids = [BEGIN_OF_TEXT] + tokenizer.encode(f"{VOICE}: {text}", add_special_tokens=False)
        example = build_example(text_ids, audio_tokens)
        if not audio_tokens or len(example["input_ids"]) > MAX_TOKENS:
            skipped += 1
            continue
        examples.append(example)
    print(f"Prepared {len(examples)} training examples" + (f" ({skipped} skipped)." if skipped else "."))
    if not examples:
        sys.exit("Nothing to train on.")

    trainer = Trainer(
        model=model,
        train_dataset=examples,
        data_collator=collate,
        args=TrainingArguments(
            per_device_train_batch_size=1,
            gradient_accumulation_steps=4,
            num_train_epochs=args.epochs,
            warmup_steps=5,
            learning_rate=args.lr,
            lr_scheduler_type="linear",
            weight_decay=0.001,
            optim="adamw_torch",
            bf16=True,
            logging_steps=5,
            save_strategy="no",
            seed=3407,
            output_dir=str(HERE / "training_runs"),
            report_to="none",
        ),
    )
    print("Training. The 'loss' number printed below should drift downward.")
    stats = trainer.train()
    print(f"Training took {stats.metrics['train_runtime'] / 60:.1f} minutes.")

    model.save_pretrained(str(LORA_DIR))
    tokenizer.save_pretrained(str(LORA_DIR))
    print(f"Saved your voice to {LORA_DIR}")

    print("Speaking test sentences...")
    model.eval()
    out_dir = HERE / "test_outputs"
    out_dir.mkdir(exist_ok=True)
    for i, line in enumerate(TEST_LINES, 1):
        try:
            audio = synthesize(model, tokenizer, snac_model, line)
            sf.write(str(out_dir / f"test_{i}.wav"), audio, SAMPLE_RATE)
            print(f"  test_{i}.wav  ({len(audio) / SAMPLE_RATE:.1f}s)  {line}")
        except Exception as err:
            print(f"  test {i} failed: {err}")
    print(f"Done. Listen to the files in {out_dir}")


if __name__ == "__main__":
    main()
