"""
BellAi Studio - a one-page voice studio for your GPT-SoVITS voice.

Start it by double-clicking "BellAi Studio.bat" in the Voice Training folder.
It opens http://localhost:9890 in your browser.

  * Type a line, press Enter, and hear it. The voice stays loaded, and audio streams
    back sentence by sentence, so the first sound usually arrives in well under a second.
  * "Train new voice" rebuilds the training list from voice_data/clips/metadata.csv,
    prepares the data, trains SoVITS and GPT, then tests every saved version and a few
    reference clips, and keeps whichever sounds most like you (it never replaces a
    better voice with a worse one).
  * "Find best settings" runs only that testing step on the voice you already have.

It runs on the Python that ships inside the GPT-SoVITS folder, so nothing else
needs to be installed.
"""

import csv
import difflib
import glob
import json
import os
import random
import re
import socket
import subprocess
import sys
import threading
import time
import traceback
import webbrowser
import zipfile
from collections import deque
from pathlib import Path

try:  # the Windows console can choke on the Chinese log lines GPT-SoVITS prints
    sys.stdout.reconfigure(errors="replace")
    sys.stderr.reconfigure(errors="replace")
except Exception:
    pass

STUDIO_DIR = Path(__file__).resolve().parent
VOICE_DIR = STUDIO_DIR.parent                       # the Voice Training folder
CLIPS = VOICE_DIR / "voice_data" / "clips"
METADATA = CLIPS / "metadata.csv"
LIST_FILE = VOICE_DIR / "voice_data" / "gpt_sovits" / "bella.list"
SETTINGS_FILE = STUDIO_DIR / "studio_settings.json"
RESULTS_FILE = STUDIO_DIR / "studio_results.json"
EVAL_DIR = STUDIO_DIR / "eval"
PAGE = STUDIO_DIR / "index.html"
PACKS_DIR = VOICE_DIR / "voice_packs"
PORT = 9890

TEST_LINES = [
    "Good evening. I turned off the kitchen lights and locked the back door for you.",
    "It looks like rain this afternoon, so you might want to take a jacket with you.",
    "Beanie has been sitting by the window all morning, watching the birds in the yard.",
    "Sorry, I didn't catch that. Could you say it again, a little more slowly?",
    "Oh my gosh, your friends are here! Should I turn the music up in the living room?",
]

PRESETS = {  # SoVITS epochs, GPT epochs (saved every 4 and every 5 epochs)
    "quick": (8, 15),
    "balanced": (12, 20),
    "best": (16, 30),
}


def find_gpt_sovits():
    env = os.environ.get("GPT_SOVITS_DIR")
    if env and (Path(env) / "GPT_SoVITS").is_dir():
        return Path(env)
    for folder in sorted((VOICE_DIR / "GPT-SoVITS").glob("*")):
        if (folder / "GPT_SoVITS").is_dir():
            return folder
    sys.exit("Can't find the GPT-SoVITS folder inside Voice Training\\GPT-SoVITS.")


SOVITS_DIR = find_gpt_sovits()
os.chdir(SOVITS_DIR)                                  # GPT-SoVITS uses paths relative to its folder
sys.path.insert(0, str(SOVITS_DIR))
sys.path.insert(1, str(SOVITS_DIR / "GPT_SoVITS"))
os.environ["version"] = "v2"

GPT_ROOT, SOVITS_ROOT = "GPT_weights_v2", "SoVITS_weights_v2"
BERT_DIR = "GPT_SoVITS/pretrained_models/chinese-roberta-wwm-ext-large"
HUBERT_DIR = "GPT_SoVITS/pretrained_models/chinese-hubert-base"
PRETRAINED_S2G = "GPT_SoVITS/pretrained_models/gsv-v2final-pretrained/s2G2333k.pth"
PRETRAINED_S2D = "GPT_SoVITS/pretrained_models/gsv-v2final-pretrained/s2D2333k.pth"
PRETRAINED_S1 = "GPT_SoVITS/pretrained_models/gsv-v2final-pretrained/s1bert25hz-5kh-longer-epoch=12-step=369668.ckpt"

import numpy as np  # noqa: E402
import soundfile as sf  # noqa: E402
import torch  # noqa: E402
import uvicorn  # noqa: E402
from fastapi import Body, FastAPI, HTTPException  # noqa: E402
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, StreamingResponse  # noqa: E402

HAS_GPU = torch.cuda.is_available()

# GPT-SoVITS swaps PyTorch's attention function for its own version when it loads, which
# breaks other models that use it (like the voice-similarity checker). Keep the original
# so it can be put back while those models run.
import contextlib  # noqa: E402
import torch.nn.functional as _F  # noqa: E402
_TORCH_ATTENTION = _F.multi_head_attention_forward


@contextlib.contextmanager
def torch_attention():
    patched = _F.multi_head_attention_forward
    _F.multi_head_attention_forward = _TORCH_ATTENTION
    try:
        yield
    finally:
        _F.multi_head_attention_forward = patched


# ---------------------------------------------------------------- small helpers

def natural_key(text):
    return [int(part) if part.isdigit() else part.lower() for part in re.split(r"(\d+)", text)]


def clean_text(text):
    text = re.sub(r"<[a-zA-Z]+>", " ", text or "")   # <laugh> and friends are Orpheus-only
    return re.sub(r"\s+", " ", text).strip()


def read_json(path, default):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception:
        return default


def write_json(path, data):
    Path(path).write_text(json.dumps(data, indent=2), encoding="utf-8")


def list_weights():
    gpt = sorted((p.replace("\\", "/") for p in glob.glob(f"{GPT_ROOT}/*.ckpt")), key=natural_key)
    sovits = sorted((p.replace("\\", "/") for p in glob.glob(f"{SOVITS_ROOT}/*.pth")), key=natural_key)
    return gpt, sovits


def sovits_epoch(path):
    found = re.search(r"_e(\d+)_s\d+\.pth$", path)
    return int(found.group(1)) if found else -1


def gpt_epoch(path):
    found = re.search(r"-e(\d+)\.ckpt$", path)
    return int(found.group(1)) if found else -1


def run_of(sovits_path):
    found = re.match(r"(.+)_e\d+_s\d+\.pth$", Path(sovits_path).name)
    return found.group(1) if found else None


def short_name(path):
    return Path(path).stem if path else ""


# ---------------------------------------------------------------- your clips

class Clips:
    """Reads metadata.csv once and remembers which clips work as a reference (3-10 s)."""

    def __init__(self):
        self.rows, self.refs, self.minutes = [], [], 0.0
        self.reload()

    def reload(self):
        rows, refs, seconds = [], [], 0.0
        if METADATA.exists():
            with open(METADATA, encoding="utf-8", newline="") as f:
                for row in list(csv.reader(f))[1:]:
                    if len(row) < 2 or not (CLIPS / row[0]).exists():
                        continue
                    try:
                        duration = sf.info(str(CLIPS / row[0])).duration
                    except Exception:
                        continue
                    rows.append((row[0], row[1]))
                    seconds += duration
                    text = clean_text(row[1])
                    if "<" not in row[1] and 3.2 <= duration <= 9.8 and len(text) > 12:
                        refs.append({"name": row[0], "text": text, "seconds": round(duration, 1)})
        self.rows, self.refs, self.minutes = rows, refs, seconds / 60
        self.by_name = {r["name"]: r for r in refs}

    def write_training_list(self):
        self.reload()
        lines = []
        for name, text in self.rows:
            text = clean_text(text).strip(" ,")
            if len(text) >= 3:
                lines.append(f"{CLIPS / name}|bella|en|{text}")
        LIST_FILE.parent.mkdir(parents=True, exist_ok=True)
        LIST_FILE.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return len(lines)


CLIP_DATA = Clips()


# ---------------------------------------------------------------- the voice engine

class Engine:
    """Keeps one GPT-SoVITS pipeline loaded on the GPU and hands out turns to use it."""

    def __init__(self):
        self.tts = None
        self.status = "Starting up..."
        self.ready = False
        self.lock = threading.Lock()
        self.owner = None                       # "speak", "test" or "load"
        self.settings = self.load_settings()
        self.last = {}
        self._free = None                       # GPT-SoVITS's own memory cleanup
        self._cleanup_token = None

    # ---- settings
    def load_settings(self):
        gpt, sovits = list_weights()
        chosen = read_json(SOVITS_DIR / "weight.json", {})
        settings = {
            "gpt": chosen.get("GPT", {}).get("v2") or (gpt[-1] if gpt else PRETRAINED_S1),
            "sovits": chosen.get("SoVITS", {}).get("v2") or (sovits[-1] if sovits else PRETRAINED_S2G),
            "ref": "BellAi_pt4_0036.wav",
            "speed": 1.0,
            "temperature": 1.0,
            "top_k": 15,
        }
        settings.update(read_json(SETTINGS_FILE, {}))
        if not os.path.exists(settings["gpt"]):
            settings["gpt"] = gpt[-1] if gpt else PRETRAINED_S1
        if not os.path.exists(settings["sovits"]):
            settings["sovits"] = sovits[-1] if sovits else PRETRAINED_S2G
        if settings["ref"] not in CLIP_DATA.by_name and CLIP_DATA.refs:
            settings["ref"] = CLIP_DATA.refs[0]["name"]
        return settings

    def save_settings(self):
        write_json(SETTINGS_FILE, self.settings)

    # ---- taking turns on the GPU
    def acquire(self, owner, wait=600.0):
        self._cleanup_token = None              # any new work cancels a pending cleanup
        if self.lock.acquire(timeout=0.02):
            self.owner = owner
            return True
        if owner == "speak" and self.owner == "speak" and self.tts is not None:
            self.tts.stop()                     # a new line interrupts the one still talking
        if self.lock.acquire(timeout=wait):
            self.owner = owner
            return True
        return False

    def release(self):
        self.owner = None
        try:
            self.lock.release()
        except RuntimeError:
            pass

    # ---- loading
    def start(self):
        threading.Thread(target=self._load, daemon=True).start()

    def _load(self):
        try:
            self.status = "Loading your voice..."
            from GPT_SoVITS.TTS_infer_pack.TTS import TTS, TTS_Config
            config = {"version": "v2", "custom": {
                "device": "cuda" if HAS_GPU else "cpu",
                "is_half": HAS_GPU,
                "version": "v2",
                "t2s_weights_path": self.settings["gpt"],
                "vits_weights_path": self.settings["sovits"],
                "bert_base_path": BERT_DIR,
                "cnhuhbert_base_path": HUBERT_DIR,
            }}
            self.acquire("load")
            try:
                self.tts = TTS(TTS_Config(config))
                # GPT-SoVITS clears GPU memory at the end of every line. Skip that, and
                # clean up once instead, when BellAi has finished talking.
                self._free = self.tts.empty_cache
                self.tts.empty_cache = lambda: None
                self.status = "Warming up..."
                self._warm_up()
            finally:
                self.release()
            self.ready = True
            self.status = "Ready"
            print(f"\nBellAi Studio is ready at http://localhost:{PORT}\n")
        except Exception as err:
            traceback.print_exc()
            self.status = f"Couldn't load the voice: {err}"

    def free_memory(self):
        """One memory cleanup. Call while holding the lock (or when nothing else runs)."""
        if self._free:
            self._free()

    def cleanup_when_idle(self, delay=4.0):
        """Clean up once BellAi has been quiet for a few seconds."""
        self._cleanup_token = token = object()

        def run():
            if self._cleanup_token is token and self.lock.acquire(blocking=False):
                self.owner = "cleanup"
                try:
                    self.free_memory()
                finally:
                    self.release()

        timer = threading.Timer(delay, run)
        timer.daemon = True
        timer.start()

    def _warm_up(self):
        for _ in self.tts.run(self.request("Hi there. Ready when you are.", fragment=False)):
            pass

    def request(self, text, fragment=True, seed=-1, ref=None):
        ref = ref or self.settings["ref"]
        info = CLIP_DATA.by_name.get(ref, {"text": ""})
        return {
            "text": text,
            "text_lang": "en",
            "ref_audio_path": str(CLIPS / ref),
            "prompt_text": info["text"],
            "prompt_lang": "en",
            "top_k": int(self.settings["top_k"]),
            "top_p": 1.0,
            "temperature": float(self.settings["temperature"]),
            "text_split_method": "cut5",           # split at punctuation, so the first piece is short
            "batch_size": 1,
            "batch_threshold": 0.75,
            "split_bucket": not fragment,
            "return_fragment": fragment,
            "speed_factor": float(self.settings["speed"]),
            "fragment_interval": 0.2,
            "seed": seed,
            "parallel_infer": True,
            "repetition_penalty": 1.35,
        }

    def use_models(self, gpt=None, sovits=None):
        """Switch weights. Call while holding the lock."""
        if gpt and gpt != self.tts.configs.t2s_weights_path:
            self.tts.init_t2s_weights(gpt)
        if sovits and sovits != self.tts.configs.vits_weights_path:
            self.tts.init_vits_weights(sovits)
            self.tts.prompt_cache["ref_audio_path"] = None   # reference features depend on SoVITS

    def synth(self, text, seed=1234, ref=None):
        """Whole-utterance synthesis for testing. Call while holding the lock."""
        sr, audio = next(self.tts.run(self.request(text, fragment=False, seed=seed, ref=ref)))
        return sr, np.asarray(audio, dtype=np.float32) / 32768.0


ENGINE = Engine()


# ---------------------------------------------------------------- scoring

class Judge:
    """Scores how much a voice sounds like you (speaker similarity) and how clearly it says
    the words (Whisper word accuracy)."""

    def __init__(self, log):
        import librosa
        from transformers import AutoFeatureExtractor, WavLMForXVector
        self.librosa = librosa
        self.device = "cuda" if HAS_GPU else "cpu"
        log("Loading the voice-similarity model...")
        self.extractor = AutoFeatureExtractor.from_pretrained("microsoft/wavlm-base-plus-sv")
        self.sv = WavLMForXVector.from_pretrained("microsoft/wavlm-base-plus-sv").to(self.device).eval()
        self.asr = None
        try:
            log("Loading Whisper to check pronunciation...")
            from faster_whisper import WhisperModel
            self.asr = WhisperModel("large-v3", device=self.device, compute_type="float16" if HAS_GPU else "int8")
        except Exception as err:
            log(f"Whisper isn't available ({err}); scoring on voice similarity only.")
        names = [name for name, _ in CLIP_DATA.rows]
        sample = random.Random(7).sample(names, min(30, len(names)))
        vectors = []
        for name in sample:
            audio, sr = sf.read(str(CLIPS / name), dtype="float32")
            vectors.append(self.embed(audio, sr))
        self.target = torch.nn.functional.normalize(torch.stack(vectors).mean(0), dim=-1)

    def to16k(self, audio, sr):
        if audio.ndim > 1:
            audio = audio.mean(1)
        return self.librosa.resample(audio, orig_sr=sr, target_sr=16000) if sr != 16000 else audio

    @torch.no_grad()
    def embed(self, audio, sr):
        audio = self.to16k(audio, sr)
        inputs = self.extractor(audio, sampling_rate=16000, return_tensors="pt").to(self.device)
        with torch_attention():
            vector = self.sv(**inputs).embeddings[0].float()
        return torch.nn.functional.normalize(vector, dim=-1).cpu()

    def accuracy(self, audio, sr, text):
        if self.asr is None:
            return None
        segments, _ = self.asr.transcribe(self.to16k(audio, sr), language="en", beam_size=5)
        heard = " ".join(s.text for s in segments)
        words = lambda s: re.sub(r"[^a-z0-9' ]+", " ", s.lower()).split()
        return difflib.SequenceMatcher(None, words(text), words(heard)).ratio()

    def score(self, clips):
        """clips: list of (sr, audio, text). Returns similarity, accuracy, overall score."""
        sims, accs = [], []
        for sr, audio, text in clips:
            sims.append(float(torch.dot(self.embed(audio, sr), self.target)))
            acc = self.accuracy(audio, sr, text)
            if acc is not None:
                accs.append(acc)
        sim = float(np.mean(sims))
        acc = float(np.mean(accs)) if accs else None
        overall = sim - (max(0.0, 0.92 - acc) if acc is not None else 0.0)
        return sim, acc, overall

    def close(self):
        del self.sv, self.asr


# ---------------------------------------------------------------- training + testing

class Trainer:
    STAGES = ["Prepare data", "Train SoVITS", "Train GPT", "Test & pick best"]

    def __init__(self):
        self.state = "idle"          # idle, running, done, failed, stopped
        self.stage = -1
        self.progress = 0.0
        self.message = ""
        self.log_lines = deque(maxlen=400)
        self.proc = None
        self.stop_requested = False
        saved = read_json(RESULTS_FILE, {})
        self.results = saved.get("results", [])
        self.summary = saved.get("summary", "")

    # ---- public
    def status(self):
        return {"state": self.state, "stage": self.stage, "stages": self.STAGES,
                "progress": round(self.progress, 3), "message": self.message,
                "log": list(self.log_lines)[-120:], "results": self.results, "summary": self.summary}

    def start(self, preset, test_only=False):
        if self.state == "running":
            raise HTTPException(409, "Training is already running.")
        if not ENGINE.ready:
            raise HTTPException(409, "Wait for the voice to finish loading first.")
        self.state, self.stage, self.progress, self.message = "running", -1, 0.0, "Starting..."
        self.stop_requested = False
        self.log_lines.clear()
        threading.Thread(target=self._run, args=(preset, test_only), daemon=True).start()

    def stop(self):
        self.stop_requested = True
        if self.proc and self.proc.poll() is None:
            self.log("Stopping...")
            if os.name == "nt":
                subprocess.run(["taskkill", "/PID", str(self.proc.pid), "/T", "/F"], capture_output=True)
            else:
                self.proc.kill()

    # ---- internals
    def log(self, line):
        line = line.rstrip()
        if line:
            self.log_lines.append(line)
            print("[train]", line)

    def set_stage(self, index, message):
        self.stage, self.message = index, message
        self.progress = index / len(self.STAGES)
        self.log(f"== {message}")

    def sub_progress(self, fraction):
        fraction = min(max(fraction, 0.0), 1.0)
        self.progress = (self.stage + fraction) / len(self.STAGES)

    def run_step(self, args, env_extra, epochs=None):
        env = dict(os.environ)
        env.update({"version": "v2", "is_half": str(HAS_GPU), "_CUDA_VISIBLE_DEVICES": "0",
                    "PYTHONUNBUFFERED": "1", "PYTHONIOENCODING": "utf-8"})
        env.update(env_extra)
        flags = subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0
        self.proc = subprocess.Popen([sys.executable] + args, cwd=str(SOVITS_DIR), env=env,
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                     encoding="utf-8", errors="replace", bufsize=1, creationflags=flags)
        for line in self.proc.stdout:          # text mode turns tqdm's \r updates into lines too
            self.log(line)
            if epochs:
                found = re.findall(r"Epoch[: ]+(\d+)", line)
                if found:
                    self.sub_progress(int(found[-1]) / epochs)
        code = self.proc.wait()
        self.proc = None
        if self.stop_requested:
            raise InterruptedError
        if code != 0:
            raise RuntimeError(f"{Path(args[0]).name} stopped with an error (code {code}). See the log.")

    def _run(self, preset, test_only):
        try:
            if test_only:
                run = run_of(ENGINE.settings["sovits"])
                if not run:
                    raise RuntimeError("The current SoVITS model isn't one you trained, so there's nothing to compare.")
                self.stage = 3
                self.evaluate(run)
            else:
                self.train(preset)
            if self.state == "running":
                self.state = "done"
        except InterruptedError:
            self.state, self.message = "stopped", "Stopped."
            self.log("Stopped.")
        except Exception as err:
            traceback.print_exc()
            self.state, self.message = "failed", str(err)
            self.log(f"Failed: {err}")

    def train(self, preset):
        sovits_epochs, gpt_epochs = PRESETS.get(preset, PRESETS["balanced"])
        run = time.strftime("bellai_%m%d_%H%M")
        opt_dir = f"logs/{run}"
        os.makedirs(opt_dir, exist_ok=True)

        # 1. prepare
        self.set_stage(0, "Preparing your clips")
        count = CLIP_DATA.write_training_list()
        self.log(f"Training list: {count} clips, {CLIP_DATA.minutes:.0f} minutes, run name {run}")
        common = {"inp_text": str(LIST_FILE), "inp_wav_dir": "", "exp_name": run, "opt_dir": opt_dir,
                  "i_part": "0", "all_parts": "1"}
        self.run_step(["GPT_SoVITS/prepare_datasets/1-get-text.py"], dict(common, bert_pretrained_dir=BERT_DIR))
        self._merge(f"{opt_dir}/2-name2text-0.txt", f"{opt_dir}/2-name2text.txt")
        self.sub_progress(0.4)
        self.run_step(["GPT_SoVITS/prepare_datasets/2-get-hubert-wav32k.py"], dict(common, cnhubert_base_dir=HUBERT_DIR))
        self.sub_progress(0.75)
        self.run_step(["GPT_SoVITS/prepare_datasets/3-get-semantic.py"],
                      dict(common, pretrained_s2G=PRETRAINED_S2G, s2config_path="GPT_SoVITS/configs/s2.json"))
        self._merge(f"{opt_dir}/6-name2semantic-0.tsv", f"{opt_dir}/6-name2semantic.tsv", header="item_name\tsemantic_audio")

        # 2. SoVITS
        self.set_stage(1, f"Training SoVITS ({sovits_epochs} epochs)")
        if ENGINE.acquire("load", wait=30):    # give training as much GPU memory as possible
            try:
                ENGINE.free_memory()
            finally:
                ENGINE.release()
        with open("GPT_SoVITS/configs/s2.json", encoding="utf-8") as f:
            s2 = json.load(f)
        os.makedirs(f"{opt_dir}/logs_s2_v2", exist_ok=True)
        s2["train"].update({"batch_size": 12 if HAS_GPU else 4, "epochs": sovits_epochs, "text_low_lr_rate": 0.4,
                            "pretrained_s2G": PRETRAINED_S2G, "pretrained_s2D": PRETRAINED_S2D,
                            "if_save_latest": True, "if_save_every_weights": True, "save_every_epoch": 4,
                            "gpu_numbers": "0", "grad_ckpt": False, "lora_rank": "32", "fp16_run": HAS_GPU})
        s2["model"]["version"] = "v2"
        s2["data"]["exp_dir"] = s2["s2_ckpt_dir"] = opt_dir
        s2.update({"save_weight_dir": SOVITS_ROOT, "name": run, "version": "v2"})
        os.makedirs("TEMP", exist_ok=True)
        write_json("TEMP/studio_s2.json", s2)
        self.run_step(["GPT_SoVITS/s2_train.py", "--config", "TEMP/studio_s2.json"], {}, epochs=sovits_epochs)

        # 3. GPT
        self.set_stage(2, f"Training GPT ({gpt_epochs} epochs)")
        import yaml
        with open("GPT_SoVITS/configs/s1longer-v2.yaml", encoding="utf-8") as f:
            s1 = yaml.load(f, Loader=yaml.FullLoader)
        os.makedirs(f"{opt_dir}/logs_s1", exist_ok=True)
        s1["train"].update({"batch_size": 12 if HAS_GPU else 4, "epochs": gpt_epochs, "save_every_n_epoch": 5,
                            "if_save_every_weights": True, "if_save_latest": True, "if_dpo": False,
                            "half_weights_save_dir": GPT_ROOT, "exp_name": run})
        if not HAS_GPU:
            s1["train"]["precision"] = "32"
        s1.update({"pretrained_s1": PRETRAINED_S1, "train_semantic_path": f"{opt_dir}/6-name2semantic.tsv",
                   "train_phoneme_path": f"{opt_dir}/2-name2text.txt", "output_dir": f"{opt_dir}/logs_s1_v2"})
        with open("TEMP/studio_s1.yaml", "w", encoding="utf-8") as f:
            yaml.dump(s1, f, default_flow_style=False)
        self.run_step(["GPT_SoVITS/s1_train.py", "--config_file", "TEMP/studio_s1.yaml"], {"hz": "25hz"},
                      epochs=gpt_epochs)

        # 4. test
        self.evaluate(run)

    @staticmethod
    def _merge(part, final, header=None):
        with open(part, encoding="utf-8") as f:
            lines = [l for l in f.read().strip("\n").split("\n") if l]
        if header:
            lines = [header] + lines
        with open(final, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        os.remove(part)

    def evaluate(self, run):
        self.set_stage(3, "Testing every saved version")
        sovits_list = sorted(glob.glob(f"{SOVITS_ROOT}/{run}_e*_s*.pth"), key=sovits_epoch)
        gpt_list = sorted(glob.glob(f"{GPT_ROOT}/{run}-e*.ckpt"), key=gpt_epoch)
        sovits_list = [p.replace("\\", "/") for p in sovits_list]
        gpt_list = [p.replace("\\", "/") for p in gpt_list]
        if not sovits_list or not gpt_list:
            raise RuntimeError(f"No saved models found for {run}.")

        out_dir = EVAL_DIR / run
        out_dir.mkdir(parents=True, exist_ok=True)
        judge = None
        before = dict(gpt=ENGINE.settings["gpt"], sovits=ENGINE.settings["sovits"], ref=ENGINE.settings["ref"])
        tried, rows = {}, []
        steps = 1 + len(sovits_list) + len(gpt_list) + 6
        done = [0]

        def trial(gpt, sovits, ref, lines, kind, label):
            key = (gpt, sovits, ref, len(lines))
            if key in tried:
                return tried[key]
            if self.stop_requested:
                raise InterruptedError
            ENGINE.use_models(gpt, sovits)
            clips = []
            for i, line in enumerate(lines):
                sr, audio = ENGINE.synth(line, ref=ref)
                clips.append((sr, audio, line))
                if i == 0:
                    sf.write(str(out_dir / f"{len(rows):02d}.wav"), audio, sr)
            sim, acc, overall = judge.score(clips)
            row = {"kind": kind, "label": label, "gpt": gpt, "sovits": sovits, "ref": ref,
                   "similarity": round(sim, 4), "accuracy": None if acc is None else round(acc, 3),
                   "score": round(overall, 4), "sample": f"{run}/{len(rows):02d}.wav"}
            rows.append(row)
            tried[key] = row
            done[0] += 1
            self.sub_progress(done[0] / steps)
            acc_text = "n/a" if acc is None else f"{acc:.0%}"
            self.log(f"{label}: similarity {sim:.3f}, words {acc_text}, score {overall:.3f}")
            return row

        if not ENGINE.acquire("test", wait=120):
            raise RuntimeError("The voice is busy. Try again in a moment.")
        try:
            judge = Judge(self.log)
            ref = before["ref"]
            # the voice you have now is the one to beat
            baseline = trial(before["gpt"], before["sovits"], ref, TEST_LINES, "current",
                             f"Current voice ({short_name(before['sovits'])} + {short_name(before['gpt'])})")
            # every SoVITS save with the last GPT save, then every GPT save with the best SoVITS
            best_s = max((trial(gpt_list[-1], s, ref, TEST_LINES, "sovits",
                                f"SoVITS epoch {sovits_epoch(s)}") for s in sovits_list),
                         key=lambda r: r["score"])["sovits"]
            best_model = max((trial(g, best_s, ref, TEST_LINES, "gpt",
                                    f"GPT epoch {gpt_epoch(g)} + SoVITS epoch {sovits_epoch(best_s)}")
                              for g in gpt_list), key=lambda r: r["score"])
            winner = best_model if best_model["score"] >= baseline["score"] else baseline

            # a few reference clips with the winning models
            self.message = "Trying reference clips"
            pool = [c for c in CLIP_DATA.refs if 4.5 <= c["seconds"] <= 9.0 and c["name"] != ref]
            candidates = random.Random(run).sample(pool, min(5, len(pool)))
            lines = TEST_LINES[:3]
            ref_rows = [trial(winner["gpt"], winner["sovits"], ref, lines, "ref", f"Reference {ref} (current)")]
            for c in candidates:
                ref_rows.append(trial(winner["gpt"], winner["sovits"], c["name"], lines, "ref", f"Reference {c['name']}"))
            best_ref = max(ref_rows, key=lambda r: r["score"])["ref"]

            ENGINE.use_models(winner["gpt"], winner["sovits"])
            ENGINE.settings.update(gpt=winner["gpt"], sovits=winner["sovits"], ref=best_ref)
            ENGINE.save_settings()
            ENGINE._warm_up()
        except BaseException:
            try:  # put the voice back the way it was
                ENGINE.use_models(before["gpt"], before["sovits"])
                ENGINE.settings.update(before)
            except Exception:
                traceback.print_exc()
            raise
        finally:
            if judge is not None:
                judge.close()
            ENGINE.free_memory()               # one cleanup, after all the testing
            ENGINE.release()

        if winner is baseline:
            picked = "Your previous voice still scored best, so the models weren't changed"
        else:
            picked = f"Now using SoVITS epoch {sovits_epoch(winner['sovits'])} + GPT epoch {gpt_epoch(winner['gpt'])}"
        ref_note = "kept the same reference clip" if best_ref == ref else f"switched the reference clip to {best_ref}"
        self.summary = f"Tested {len(rows)} versions. {picked}, and {ref_note}." 
        best_row = max((r for r in rows if r["ref"] == best_ref and r["gpt"] == winner["gpt"]
                        and r["sovits"] == winner["sovits"]), key=lambda r: r["score"])
        for r in rows:
            r["chosen"] = r is best_row
        self.results = rows
        write_json(RESULTS_FILE, {"results": rows, "summary": self.summary})
        self.progress, self.message = 1.0, "Done" 
        self.log(self.summary)


TRAINER = Trainer()


# ---------------------------------------------------------------- web server

app = FastAPI(title="BellAi Studio")


@app.get("/", response_class=HTMLResponse)
def page():
    return HTMLResponse(PAGE.read_text(encoding="utf-8"), headers={"Cache-Control": "no-store"})


@app.get("/api/status")
def status():
    gpt, sovits = list_weights()
    ref = CLIP_DATA.by_name.get(ENGINE.settings["ref"], {})
    return {
        "ready": ENGINE.ready, "status": ENGINE.status, "busy": ENGINE.owner,
        "gpu": torch.cuda.get_device_name(0) if HAS_GPU else "CPU",
        "settings": ENGINE.settings, "ref_text": ref.get("text", ""),
        "weights": {"gpt": gpt, "sovits": sovits},
        "dataset": {"clips": len(CLIP_DATA.rows), "minutes": round(CLIP_DATA.minutes, 1)},
        "last": ENGINE.last, "train": TRAINER.status(), "presets": PRESETS,
    }


@app.get("/api/refs")
def refs():
    return CLIP_DATA.refs


@app.get("/api/clip/{name}")
def clip(name: str):
    if name not in CLIP_DATA.by_name:
        raise HTTPException(404, "Unknown clip")
    return FileResponse(str(CLIPS / name), media_type="audio/wav")


@app.get("/api/eval/{run}/{name}")
def eval_audio(run: str, name: str):
    path = (EVAL_DIR / run / name).resolve()
    if EVAL_DIR.resolve() not in path.parents or not path.exists():
        raise HTTPException(404, "Not found")
    return FileResponse(str(path), media_type="audio/wav")


@app.post("/api/speak")
def speak(body: dict = Body(...)):
    text = clean_text(body.get("text", ""))[:1200]
    if not text:
        raise HTTPException(400, "Type something first.")
    if not ENGINE.ready:
        raise HTTPException(503, ENGINE.status)
    if ENGINE.owner == "test":
        raise HTTPException(409, "BellAi is busy testing voices. Try again when that finishes.")
    if not ENGINE.acquire("speak", wait=15):
        raise HTTPException(409, "BellAi is busy. Try again in a moment.")
    request = ENGINE.request(text)
    rate = int(ENGINE.tts.configs.sampling_rate)

    def stream():
        started, first, samples = time.time(), None, 0
        try:
            for _, chunk in ENGINE.tts.run(request):
                chunk = np.asarray(chunk)
                if chunk.dtype != np.int16:
                    chunk = (np.clip(chunk, -1, 1) * 32767).astype(np.int16)
                if first is None:
                    first = time.time() - started
                samples += len(chunk)
                yield chunk.tobytes()
        finally:
            ENGINE.release()
            ENGINE.cleanup_when_idle()         # one cleanup after she's done talking
            took = time.time() - started
            ENGINE.last = {"first": round(first or took, 3), "total": round(took, 2),
                           "seconds": round(samples / rate, 2)}

    return StreamingResponse(stream(), media_type="application/octet-stream",
                             headers={"X-Sample-Rate": str(rate), "Cache-Control": "no-store"})


@app.post("/api/settings")
def update_settings(body: dict = Body(...)):
    changed = {}
    for key, low, high in (("speed", 0.6, 1.6), ("temperature", 0.3, 1.5), ("top_k", 1, 50)):
        if key in body:
            value = min(max(float(body[key]), low), high)
            changed[key] = int(value) if key == "top_k" else round(value, 2)
    if "ref" in body:
        if body["ref"] not in CLIP_DATA.by_name:
            raise HTTPException(400, "That clip can't be used as a reference (it needs to be 3-10 seconds).")
        changed["ref"] = body["ref"]
    new_models = {k: body[k] for k in ("gpt", "sovits") if k in body}
    for key, path in new_models.items():
        if not os.path.exists(path):
            raise HTTPException(400, f"Can't find {path}")
    if (new_models or "ref" in changed) and ENGINE.ready:
        if not ENGINE.acquire("load", wait=30):
            raise HTTPException(409, "BellAi is busy. Try again in a moment.")
        try:
            ENGINE.use_models(new_models.get("gpt"), new_models.get("sovits"))
            ENGINE.settings.update(new_models)
            ENGINE.settings.update(changed)
            ENGINE._warm_up()                  # loads the new reference, so the next line is quick
            ENGINE.free_memory()               # let go of the old model's memory
        finally:
            ENGINE.release()
    else:
        ENGINE.settings.update(new_models)
        ENGINE.settings.update(changed)
    ENGINE.save_settings()
    return status()


@app.post("/api/train")
def train(body: dict = Body(...)):
    TRAINER.start(body.get("preset", "balanced"), test_only=bool(body.get("test_only")))
    return TRAINER.status()


@app.post("/api/train/stop")
def train_stop():
    TRAINER.stop()
    return TRAINER.status()


PACK_README = """BellAi voice pack
=================

This is BellAi's GPT-SoVITS voice, ready to plug into the app, the website or the Pi.

Files
  gpt.ckpt, sovits.pth   the trained voice
  reference.wav          the clip BellAi copies her tone from
  voice.json             settings (reference text, speed, expressiveness)
  bellai_voice_server.py the voice as a web API (POST /tts -> streaming WAV)
  pi_client_example.py   speaks through the server from a Pi or any other device

Run the server (needs GPT-SoVITS installed on that machine and an NVIDIA GPU for real-time speed)
  Windows:  "<GPT-SoVITS folder>\\runtime\\python.exe" bellai_voice_server.py --gpt-sovits "<GPT-SoVITS folder>"
  Linux:    python bellai_voice_server.py --gpt-sovits ~/GPT-SoVITS
  Add --host 0.0.0.0 --key SOME-SECRET to let other devices on the network use it.

Use it
  Browser test:  http://localhost:9880/tts?text=Hello%20there
  Any language:  POST http://<server>:9880/tts  with JSON {"text": "Hello!"}  -> audio/wav (streams)
                 header X-API-Key: SOME-SECRET  if the server was started with --key
  From a Pi:     python3 pi_client_example.py --server http://<server>:9880 "Hello!"
  Health check:  GET /health
"""


@app.post("/api/export")
def export_pack():
    gpt, sovits, ref = ENGINE.settings["gpt"], ENGINE.settings["sovits"], ENGINE.settings["ref"]
    info = CLIP_DATA.by_name.get(ref)
    if not info:
        raise HTTPException(400, "Pick a reference clip first.")
    PACKS_DIR.mkdir(parents=True, exist_ok=True)
    name = time.strftime("BellAi-voice-%Y%m%d-%H%M.zip")
    voice = {
        "name": "BellAi", "engine": "GPT-SoVITS", "version": "v2", "language": "en",
        "reference_text": info["text"], "speed": ENGINE.settings["speed"],
        "temperature": ENGINE.settings["temperature"], "top_k": ENGINE.settings["top_k"],
        "trained_from": {"gpt": Path(gpt).name, "sovits": Path(sovits).name, "reference": ref},
        "exported": time.strftime("%Y-%m-%d %H:%M"), "test_summary": TRAINER.summary,
    }
    partial = PACKS_DIR / (name + ".partial")
    with zipfile.ZipFile(partial, "w", zipfile.ZIP_STORED) as z:   # the models don't compress anyway
        z.write(gpt, "gpt.ckpt")
        z.write(sovits, "sovits.pth")
        z.write(str(CLIPS / ref), "reference.wav")
        z.writestr("voice.json", json.dumps(voice, indent=2))
        z.write(str(STUDIO_DIR / "bellai_voice_server.py"), "bellai_voice_server.py")
        z.write(str(STUDIO_DIR / "pi_client_example.py"), "pi_client_example.py")
        z.writestr("README.txt", PACK_README)
    partial.replace(PACKS_DIR / name)
    size = (PACKS_DIR / name).stat().st_size
    return {"name": name, "url": f"/api/packs/{name}", "mb": round(size / 1e6), "folder": str(PACKS_DIR)}


@app.get("/api/packs/{name}")
def download_pack(name: str):
    path = (PACKS_DIR / name).resolve()
    if path.parent != PACKS_DIR.resolve() or not path.exists() or path.suffix != ".zip":
        raise HTTPException(404, "Not found")
    return FileResponse(str(path), media_type="application/zip", filename=name)


@app.post("/api/reload-clips")
def reload_clips():
    CLIP_DATA.reload()
    return status()


# ---------------------------------------------------------------- start

def already_running():
    with socket.socket() as s:
        s.settimeout(0.3)
        return s.connect_ex(("127.0.0.1", PORT)) == 0


def main():
    url = f"http://localhost:{PORT}"
    if already_running():
        print(f"BellAi Studio is already running. Opening {url}")
        webbrowser.open(url)
        return
    print(f"Starting BellAi Studio on {url} ...")
    print(f"GPT-SoVITS folder: {SOVITS_DIR}")
    ENGINE.start()
    server = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=PORT, log_level="warning"))

    def open_browser():
        for _ in range(100):
            if server.started:
                webbrowser.open(url)
                return
            time.sleep(0.1)

    threading.Thread(target=open_browser, daemon=True).start()
    server.run()


if __name__ == "__main__":
    main()
