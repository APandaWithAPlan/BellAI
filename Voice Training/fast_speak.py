"""
fast_speak.py - speak in your trained voice in real time, through Ollama.

Unlike speak.py, this streams: the first words start playing while the rest is still
being generated.

Setup (once):
    pip install sounddevice
    python export_voice.py            puts your voice into Ollama as "bellai-voice"

Run (from the Voice Training folder), with Ollama running:
    python fast_speak.py              keeps running: type a line, press Enter, hear it
    python fast_speak.py "Good morning! The coffee is ready."

Options
    --out FILE     also save the audio to a WAV file (nothing is saved unless you ask)
    --quiet        don't play (use with --out)
    --model NAME   Ollama model to use (default: bellai-voice)
    --volume N     loudness boost (default 1; try 2 if it's too quiet)

After each line it prints how long the first sound took and how fast it generated.
"1.0x" means exactly real time; higher is faster than real time.
"""

import argparse
import json
import queue
import re
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

from speak import AUDIO_OFFSET, CODEBOOK, SAMPLE_RATE, VOICE, split_text

HERE = Path(__file__).resolve().parent
OLLAMA_URL = "http://127.0.0.1:11434/api/generate"
TOKEN = re.compile(r"<custom_token_(\d+)>")
FIRST_CODE = AUDIO_OFFSET - 128256          # custom_token_10 is the first audio code
FRAME_SAMPLES = 2048                        # one 7-token frame is 2048 samples (about 85 ms)


def build_prompt(text, voice=VOICE):
    """The same layout the model was trained on, written with Orpheus's marker tokens."""
    spoken = f"{voice}: {text}" if voice else text
    return f"<custom_token_3><|begin_of_text|>{spoken}<|eot_id|><custom_token_4><custom_token_5><custom_token_1>"


class Framer:
    """Turns the stream of text pieces from Ollama into complete 7-code audio frames."""

    def __init__(self):
        self.text = ""
        self.codes = []
        self.count = 0          # valid audio codes seen so far
        self.raw = ""           # first part of the raw output, kept for troubleshooting

    def feed(self, piece):
        if len(self.raw) < 400:
            self.raw += piece
        self.text += piece
        frames, last = [], 0
        for match in TOKEN.finditer(self.text):
            last = match.end()
            code = int(match.group(1)) - FIRST_CODE - (self.count % 7) * CODEBOOK
            if 0 <= code < CODEBOOK:
                self.codes.append(code)
                self.count += 1
                if self.count % 7 == 0:
                    frames.append(self.codes[-7:])
        self.text = self.text[last:][-40:]     # keep only an unfinished token, if any
        return frames


def stream_frames(text, model, stats=None):
    """Ask Ollama to speak `text`; yields audio frames as they arrive."""
    body = json.dumps({
        "model": model, "prompt": build_prompt(text), "raw": True, "stream": True, "keep_alive": "30m",
        "options": {"temperature": 0.6, "top_p": 0.95, "repeat_penalty": 1.1, "num_predict": 1200,
                    "num_ctx": 2048, "repeat_last_n": 2048, "stop": ["<custom_token_2>"]},
    }).encode()
    request = urllib.request.Request(OLLAMA_URL, data=body, headers={"Content-Type": "application/json"})
    framer = Framer()
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            for line in response:
                if not line.strip():
                    continue
                data = json.loads(line)
                if data.get("error"):
                    raise RuntimeError(data["error"])
                if data.get("done") and stats is not None and data.get("eval_duration"):
                    stats["tokens"] = stats.get("tokens", 0) + data.get("eval_count", 0)
                    stats["seconds"] = stats.get("seconds", 0.0) + data["eval_duration"] / 1e9
                yield from framer.feed(data.get("response", ""))
    except urllib.error.HTTPError as err:
        detail = err.read().decode(errors="replace")[:300]
        raise RuntimeError(f"Ollama said: {detail}. If the model is missing, run export_voice.py.") from None
    except urllib.error.URLError:
        raise RuntimeError("Can't reach Ollama. Start the Ollama app, then try again.") from None
    if framer.count == 0:
        raise RuntimeError("Ollama answered, but not with audio codes. It sent: " + repr(framer.raw[:200]))


class Decoder:
    """Turns frames into sound with the SNAC codec, a few frames at a time."""

    def __init__(self):
        import torch
        from snac import SNAC

        self.torch = torch
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        self.snac = SNAC.from_pretrained("hubertsiuzdak/snac_24khz").to(self.device).eval()

    def decode(self, frames):
        """Decode a list of frames. Returns float32 samples, 2048 per frame."""
        torch = self.torch
        layer1 = [f[0] for f in frames]
        layer2 = [c for f in frames for c in (f[1], f[4])]
        layer3 = [c for f in frames for c in (f[2], f[3], f[5], f[6])]
        codes = [torch.tensor(layer, device=self.device).unsqueeze(0) for layer in (layer1, layer2, layer3)]
        with torch.inference_mode():
            return self.snac.decode(codes).squeeze().float().cpu().numpy()


class Chunker:
    """Decodes frames in batches. Each batch is decoded together with the frames before it and a
    few frames after it, and neighbouring pieces are blended over 10 ms, so the joins are smooth.
    If decoding ever falls behind, the next batch is simply bigger, so it always catches up."""

    BEFORE, AFTER, BLEND = 8, 3, 240

    def __init__(self, decoder):
        self.decoder = decoder
        self.frames = []
        self.done = 0           # frames already turned into sound
        self.overlap = None     # how the previous decode began the piece that comes next

    def feed(self, new_frames, final=False):
        """Add frames; returns the sound that is now ready (or None)."""
        import numpy as np

        self.frames.extend(new_frames)
        ready = len(self.frames) - self.done - (0 if final else self.AFTER)
        if ready <= 0:
            return None
        start = max(0, self.done - self.BEFORE)
        audio = self.decoder.decode(self.frames[start:])
        skip = (self.done - start) * FRAME_SAMPLES
        stop = skip + ready * FRAME_SAMPLES
        piece = np.array(audio[skip:stop], dtype=np.float32)
        if self.overlap is not None and len(piece) >= self.BLEND:
            ramp = np.linspace(0.0, 1.0, self.BLEND, dtype=np.float32)
            piece[:self.BLEND] = self.overlap * (1 - ramp) + piece[:self.BLEND] * ramp
        following = audio[stop:stop + self.BLEND]
        self.overlap = np.array(following, dtype=np.float32) if len(following) == self.BLEND else None
        self.done += ready
        return piece


class Player:
    """Plays chunks through the speakers on a background thread, so generation never waits."""

    def __init__(self, head_start=0.5):
        import sounddevice as sd

        self.head_start = int(head_start * SAMPLE_RATE)
        self.queue = queue.Queue()
        self.stream = sd.OutputStream(samplerate=SAMPLE_RATE, channels=1, dtype="float32")
        self.stream.start()
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def _run(self):
        waiting, held, finished = [], 0, False
        while held < self.head_start and not finished:      # gather a little before starting
            chunk = self.queue.get()
            if chunk is None:
                finished = True
            else:
                waiting.append(chunk)
                held += len(chunk)
        for chunk in waiting:
            self.stream.write(chunk.reshape(-1, 1))
        while not finished:
            chunk = self.queue.get()
            if chunk is None:
                break
            self.stream.write(chunk.reshape(-1, 1))

    def play(self, chunk):
        self.queue.put(chunk)

    def finish(self):
        self.queue.put(None)
        self.thread.join()
        self.stream.stop()
        self.stream.close()


def say(text, decoder, model, out=None, quiet=False, volume=1.0, head_start=0.5, whole=False):
    import numpy as np

    player = None
    if not quiet:
        try:
            player = Player(0.0 if whole else head_start)
        except Exception as err:
            print(f"(can't play sound directly: {err}. Install it with: pip install sounddevice)")

    stats, inbox = {}, queue.Queue()
    END_OF_PART, END = object(), object()

    def read():                                   # runs alongside, so decoding never slows the model
        try:
            for part in split_text(text):
                for frame in stream_frames(part, model, stats):
                    inbox.put(frame)
                inbox.put(END_OF_PART)
        except Exception as err:
            inbox.put(err)
        inbox.put(END)

    threading.Thread(target=read, daemon=True).start()
    started = time.time()
    first_sound, pieces = None, []
    gap = np.zeros(int(0.25 * SAMPLE_RATE), dtype=np.float32)
    chunker = Chunker(decoder)

    need_gap = False
    held_frames = []                              # --whole: one sentence's frames, decoded together

    def emit(chunk):
        nonlocal first_sound, need_gap
        if chunk is None or not len(chunk):
            return
        if need_gap:                              # a short pause between sentences
            need_gap = False
            emit(gap / max(volume, 1e-6))
        if first_sound is None:
            first_sound = time.time() - started
        chunk = np.clip(chunk * volume, -1.0, 1.0).astype(np.float32)
        pieces.append(chunk)
        if player:
            player.play(chunk)

    try:
        finished = False
        while not finished:
            items = [inbox.get()]
            while True:                           # take everything that has arrived so far
                try:
                    items.append(inbox.get_nowait())
                except queue.Empty:
                    break
            batch = []
            for item in items:
                if isinstance(item, Exception):
                    raise item
                if item is END_OF_PART or item is END:
                    if whole:
                        held = held_frames + batch
                        held_frames = []
                        emit(Chunker(decoder).feed(held, final=True) if held else None)
                    else:
                        emit(chunker.feed(batch, final=True))
                    batch = []
                    need_gap = need_gap or chunker.done > 0 or (whole and bool(pieces))
                    chunker = Chunker(decoder)
                    if item is END:
                        finished = True
                        break
                else:
                    batch.append(item)
            if batch and whole:
                held_frames.extend(batch)
            elif batch:
                emit(chunker.feed(batch))
        generated = time.time() - started
    finally:
        if player:
            player.finish()
    if not pieces:
        raise RuntimeError("No audio was produced.")
    audio = np.concatenate(pieces)
    seconds = len(audio) / SAMPLE_RATE
    print(f"First sound after {first_sound:.2f}s. {seconds:.1f}s of speech generated in {generated:.1f}s "
          f"({seconds / generated:.1f}x real time).")
    if stats.get("seconds"):
        rate = stats["tokens"] / stats["seconds"]
        print(f"Model speed: {rate:.0f} tokens per second (real time needs about 84).")
    if out:
        import soundfile as sf
        Path(out).parent.mkdir(parents=True, exist_ok=True)
        sf.write(str(out), audio, SAMPLE_RATE)
    return audio


def main():
    parser = argparse.ArgumentParser(description="Speak in your trained voice in real time, through Ollama.")
    parser.add_argument("text", nargs="?", help="what to say (in quotes). Leave it out to keep typing lines.")
    parser.add_argument("--out", default=None, help="also save the audio to this WAV file (off by default)")
    parser.add_argument("--quiet", action="store_true", help="don't play the sound (use with --out)")
    parser.add_argument("--model", default="bellai-voice")
    parser.add_argument("--volume", type=float, default=1.0, help="loudness boost (1 = as generated)")
    parser.add_argument("--head-start", type=float, default=0.5,
                        help="seconds of sound gathered before playing; raise it if playback stutters")
    parser.add_argument("--whole", action="store_true",
                        help="finish each sentence before playing it, decoded in one piece (smoothest, "
                             "but you wait about one sentence)")
    args = parser.parse_args()

    print("Loading the audio decoder...")
    decoder = Decoder()
    if args.text:
        try:
            say(args.text, decoder, args.model, args.out, args.quiet, args.volume, args.head_start, args.whole)
        except RuntimeError as err:
            sys.exit(str(err))
        return

    print("Ready. Type a line and press Enter. It plays through your default speakers. Type quit to stop.")
    print("(The first line is slower, because Ollama is loading the model.)")
    while True:
        try:
            text = input("Say> ").strip()
        except (EOFError, KeyboardInterrupt):
            break
        if text.lower() in ("quit", "exit", "q"):
            break
        if text:
            try:
                say(text, decoder, args.model, args.out, args.quiet, args.volume, args.head_start, args.whole)
            except Exception as err:
                print(f"That one failed: {err}")


if __name__ == "__main__":
    main()
