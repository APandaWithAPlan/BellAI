"""
tune_voice.py - train your voice for several epochs and score every epoch automatically.

Since nobody can sit and listen after every round, this script does the judging itself:
  * after each epoch it speaks the same test sentences with the model so far
  * a speaker-recognition model scores how close each one sounds to your real clips
  * Whisper checks the words came out right
  * the best-scoring epoch is saved as your voice (bella_voice_lora)

Every epoch's test audio is kept in tune_outputs/epoch_N so you can still judge by ear.

Run (from the Voice Training folder):
    python tune_voice.py                 train 8 epochs and keep the best
    python tune_voice.py --epochs 12     try more epochs
    python tune_voice.py --use-epoch 5   switch your saved voice to epoch 5 (no training)

Needs about 4 GB of free disk space (one saved copy per epoch in training_runs).
"""

import argparse
import difflib
import random
import re
import shutil
import sys
from pathlib import Path

from prepare_dataset import resample
from speak import BEGIN_OF_TEXT, LORA_DIR, SAMPLE_RATE, VOICE, load_base_model, synthesize
from train_voice import (BASE_MODEL, CLIPS, MAX_TOKENS, build_example, collate,
                         drop_repeated_frames, interleave, read_metadata)

HERE = Path(__file__).resolve().parent
RUNS = HERE / "training_runs"
OUT = HERE / "tune_outputs"

# Sentences the model has never seen, with no numbers (so Whisper's spelling can't differ).
EVAL_LINES = [
    "Good evening. I turned off the kitchen lights and locked the back door for you.",
    "It looks like rain this afternoon, so you might want to take a jacket with you.",
    "Beanie has been sitting by the window all morning, watching the birds in the yard.",
    "Sorry, I didn't catch that. Could you say it again, a little more slowly?",
    "Oh my gosh, your friends are here! Should I turn the music up in the living room?",
]


def words(text):
    return re.sub(r"[^a-z' ]", " ", re.sub(r"<[^>]*>", " ", text.lower())).split()


def word_accuracy(expected, heard):
    """1.0 means Whisper heard exactly the words that were asked for."""
    return difflib.SequenceMatcher(None, words(expected), words(heard)).ratio()


class VoiceJudge:
    """Scores generated speech against your real recordings."""

    def __init__(self, real_clips):
        import torch
        from transformers import AutoFeatureExtractor, WavLMForXVector

        self.torch = torch
        name = "microsoft/wavlm-base-plus-sv"
        self.extractor = AutoFeatureExtractor.from_pretrained(name)
        self.speaker_model = WavLMForXVector.from_pretrained(name).to("cuda").eval()
        embeddings = torch.stack([self.embed(clip) for clip in real_clips])
        total = embeddings.sum(dim=0)
        self.centroid = torch.nn.functional.normalize(total, dim=0)
        # How similar your real clips are to each other: the best score a model could hope for.
        others = torch.nn.functional.normalize(total.unsqueeze(0) - embeddings, dim=1)
        self.ceiling = float((embeddings * others).sum(dim=1).mean())

        self.whisper = None
        try:
            from faster_whisper import WhisperModel
            self.whisper = WhisperModel("large-v3", device="cuda", compute_type="float16")
        except Exception as err:
            print(f"(Whisper check unavailable: {err})")

    def embed(self, audio24):
        torch = self.torch
        audio16 = resample(audio24, SAMPLE_RATE, 16000)
        inputs = self.extractor(audio16, sampling_rate=16000, return_tensors="pt")
        with torch.no_grad():
            out = self.speaker_model(**{k: v.to("cuda") for k, v in inputs.items()}).embeddings
        return torch.nn.functional.normalize(out, dim=-1)[0]

    def similarity(self, audio24):
        return float((self.embed(audio24) * self.centroid).sum())

    def accuracy(self, audio24, expected):
        if self.whisper is None:
            return None
        try:
            segments, _ = self.whisper.transcribe(resample(audio24, SAMPLE_RATE, 16000), language="en")
            return word_accuracy(expected, " ".join(s.text for s in segments))
        except Exception:
            return None


def use_epoch(number):
    source = RUNS / f"epoch_{number}"
    if not (source / "adapter_config.json").exists():
        sys.exit(f"No saved epoch {number} in {RUNS}. Run tune_voice.py first.")
    shutil.copytree(source, LORA_DIR, dirs_exist_ok=True)
    print(f"Your saved voice is now epoch {number}. Try it with speak.py.")


def main():
    parser = argparse.ArgumentParser(description="Train several epochs and keep the best-scoring one.")
    parser.add_argument("--epochs", type=int, default=8)
    parser.add_argument("--rank", type=int, default=64)
    parser.add_argument("--lr", type=float, default=1e-4)
    parser.add_argument("--use-epoch", type=int, help="copy a saved epoch into bella_voice_lora and exit")
    args = parser.parse_args()
    if args.use_epoch is not None:
        return use_epoch(args.use_epoch)

    items = read_metadata()
    print(f"Found {len(items)} clips.")

    import numpy as np
    import soundfile as sf
    import torch
    from peft import LoraConfig, get_peft_model
    from snac import SNAC
    from transformers import AutoTokenizer, Trainer, TrainerCallback, TrainingArguments

    if not torch.cuda.is_available():
        sys.exit("PyTorch can't see your GPU.")

    tokenizer = AutoTokenizer.from_pretrained(BASE_MODEL)
    model = get_peft_model(
        load_base_model(BASE_MODEL),
        LoraConfig(
            r=args.rank, lora_alpha=args.rank, lora_dropout=0.0, bias="none", task_type="CAUSAL_LM",
            target_modules=["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"],
        ),
    )

    print("Converting clips to audio tokens...")
    snac_model = SNAC.from_pretrained("hubertsiuzdak/snac_24khz").to("cuda").eval()
    examples, real_audio = [], []
    for name, text in items:
        audio, rate = sf.read(str(CLIPS / name), dtype="float32", always_2d=True)
        if rate != SAMPLE_RATE:
            sys.exit(f"{name} is {rate} Hz, expected {SAMPLE_RATE}. Re-run prepare_dataset.py.")
        mono = np.ascontiguousarray(audio.mean(axis=1))
        if len(mono) >= 3 * SAMPLE_RATE:
            real_audio.append(mono)
        with torch.inference_mode():
            codes = snac_model.encode(torch.from_numpy(mono).reshape(1, 1, -1).to("cuda"))
        audio_tokens = drop_repeated_frames(interleave(*[c[0].tolist() for c in codes]))
        text_ids = [BEGIN_OF_TEXT] + tokenizer.encode(f"{VOICE}: {text}", add_special_tokens=False)
        example = build_example(text_ids, audio_tokens)
        if audio_tokens and len(example["input_ids"]) <= MAX_TOKENS:
            examples.append(example)
    print(f"Prepared {len(examples)} training examples.")

    print("Loading the judge (speaker model + Whisper)...")
    random.seed(7)
    judge = VoiceJudge(random.sample(real_audio, min(40, len(real_audio))))
    print(f"Your real clips score {judge.ceiling:.3f} against each other. That is the target.")

    results = []

    def evaluate(epoch):
        model.eval()
        folder = OUT / f"epoch_{epoch}"
        folder.mkdir(parents=True, exist_ok=True)
        sims, accs = [], []
        torch.manual_seed(1234)                 # same randomness every epoch, for a fair comparison
        for i, line in enumerate(EVAL_LINES, 1):
            try:
                audio = synthesize(model, tokenizer, snac_model, line)
            except Exception as err:
                print(f"    line {i} failed: {err}")
                sims.append(0.0)
                accs.append(0.0)
                continue
            sf.write(str(folder / f"line_{i}.wav"), audio, SAMPLE_RATE)
            sims.append(judge.similarity(audio))
            acc = judge.accuracy(audio, line)
            if acc is not None:
                accs.append(acc)
        sim = sum(sims) / len(sims)
        acc = sum(accs) / len(accs) if accs else None
        score = sim - (0.5 if acc is not None and acc < 0.85 else 0.0)   # garbled speech can't win
        results.append({"epoch": epoch, "sim": sim, "acc": acc, "score": score})
        shown = "n/a" if acc is None else f"{acc:.0%}"
        print(f"  epoch {epoch}: sounds-like-you {sim:.3f} (target {judge.ceiling:.3f}), words right {shown}")
        if epoch > 0:
            model.save_pretrained(str(RUNS / f"epoch_{epoch}"))
            tokenizer.save_pretrained(str(RUNS / f"epoch_{epoch}"))
        model.train()

    class JudgeEachEpoch(TrainerCallback):
        def on_epoch_end(self, train_args, state, control, **kwargs):
            evaluate(round(state.epoch))

    print("Scoring the untrained model first (epoch 0), for comparison...")
    evaluate(0)

    trainer = Trainer(
        model=model,
        train_dataset=examples,
        data_collator=collate,
        callbacks=[JudgeEachEpoch()],
        args=TrainingArguments(
            per_device_train_batch_size=1,
            gradient_accumulation_steps=4,
            num_train_epochs=args.epochs,
            warmup_steps=10,
            learning_rate=args.lr,
            lr_scheduler_type="constant_with_warmup",
            weight_decay=0.001,
            optim="adamw_torch",
            bf16=True,
            logging_steps=10,
            save_strategy="no",
            seed=3407,
            output_dir=str(RUNS),
            report_to="none",
        ),
    )
    trainer.train()

    trained = [r for r in results if r["epoch"] > 0]
    best = max(trained, key=lambda r: r["score"])
    print("\nEpoch   sounds-like-you   words right")
    for r in results:
        shown = "n/a" if r["acc"] is None else f"{r['acc']:.0%}"
        mark = "   <- best" if r is best else ""
        print(f"{r['epoch']:>5}   {r['sim']:>15.3f}   {shown:>11}{mark}")
    print(f"(your real clips score {judge.ceiling:.3f})")
    use_epoch(best["epoch"])
    print(f"Listen for yourself in {OUT}. To pick a different epoch: python tune_voice.py --use-epoch N")


if __name__ == "__main__":
    main()
