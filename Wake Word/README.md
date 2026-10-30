# BellAi Wake Word

## Overview

**BellAi Wake Word** is the small model that listens for "BellAi" so the Raspberry Pi (and the iOS app while it is open) can start recording a command without a button press. It is trained with [openWakeWord](https://github.com/dscripka/openWakeWord) using its automatic training process: thousands of synthetic "BellAi" clips from Piper TTS, clips from GPT-SoVITS and real recordings, near-miss words such as "Bella" so the model learns what *not* to wake on, and about 2,000 hours of general audio as negatives.

Training outputs `BellAi.onnx` and `BellAi.tflite` (a few hundred KB each) in `models/`.

## Getting Started

### Prerequisites

* Operating System: Windows 10 or 11 with WSL2 (Ubuntu). Training only runs on Linux, because Piper TTS does not support Windows.
* GPU: An NVIDIA GPU with the Windows driver installed. Running `nvidia-smi` inside WSL should list the GPU. Tested target: RTX 4500 Ada (24 GB).
* Disk: About 40 GB free in WSL for the training data.
* Files:
  * `bellai_model.yml` is the training config (target phrase, near misses, number of clips, training steps).
  * `setup.sh` installs everything (one time).
  * `download_data.sh` and `download_audio.py` download the training data (one time).
  * `train.sh` runs the training steps.
  * `import_clips.py` adds your own clips from `custom_clips/`.
  * `export_tflite.py` converts the model to .tflite if that step fails during training.

> 💡 **Where files go:** The Python environment and the ~30 GB of data live in WSL at `~/bellai-wakeword`, not in this folder. Reading tens of thousands of small clips through `/mnt/c` is very slow. This folder only keeps the config, scripts, your clips and the finished model. To use a different location, set `BELLAI_WW_DIR` before running the scripts.

### How to Enable / Access

Open **Ubuntu** (WSL) and go to this folder:

```bash
cd "/mnt/c/Users/Bella Breaux/Documents/GitHub/BellAI/Wake Word"
```

1. **Set up (one time, ~10 minutes):** `bash setup.sh`. Enter your WSL password when asked. At the end it should print `GPU found`.
2. **Download data (one time, ~30 GB):** `bash download_data.sh`. If the download stops, run it again and it picks up where it left off.
3. **Train:** `bash train.sh`. This runs every step in order (see below) and copies the finished model into `models/`.

## How to Use It

### Training steps

`bash train.sh` runs all of these. Each one can also be run alone, for example `bash train.sh augment`.

| Step | Command | What it does |
| --- | --- | --- |
| 1 | `generate` | Makes synthetic "bell ay eye" clips with Piper (many different voices), plus near-miss clips. |
| 2a | `split` | Cuts long takes in `recordings/` into one-word clips in `custom_clips/`. |
| 2b | `import` | Copies your clips from `custom_clips/` into the training folders as 16 kHz mono wav. |
| 3 | `augment` | Adds room echo and background noise to every clip and turns them into features. |
| 4 | `train` | Trains the model and saves `BellAi.onnx` and `BellAi.tflite`. |
| 5 | `export` | Copies the model and the two feature models it needs into `models/`. |

### Recording sessions

Put each person's long takes in `recordings/<person>/`, one file per part of the recording script: `close`, `mid`, `far` (BellAi), `nearmiss_close`, `nearmiss_mid` and `talk` (any audio format). List the 2 test speakers in `test_speakers.txt`, one folder name per line. `bash train.sh` (or `bash train.sh split`) cuts every take at the pauses into one-word clips in `custom_clips/` and prints how many it found per take; a count that doesn't match the script is flagged so you can listen and fix it. Raw takes are not committed to git.

### Adding your own clips

Put clips in `custom_clips/` before step 2 (or re-run `import`, `augment`, `train` and `export` after adding more):

* `positive_train/`: "BellAi" from the recordings and from GPT-SoVITS.
* `positive_test/`: "BellAi" from 2–3 people who are not in `positive_train`, so the test score reflects new voices.
* `negative_train/`: recorded near misses ("Bella", "hey Bella", "belly", "bell", "Bali").
* `negative_test/`: a few held-out near misses.

Each clip should be one word, 1–2 seconds long, with little silence. Record on the Pi's microphone when possible, since that is the mic the model will run on. Recordings of other people are not committed to git (see `.gitignore`).

### Changing what it listens for

Edit `bellai_model.yml`. `target_phrase` is spelled how it sounds ("bell ay eye") because Piper reads it literally. `custom_negative_phrases` lists words it must not wake on. After changing the phrase, delete `~/bellai-wakeword/my_custom_model` and run `bash train.sh` again.

### Handle an error

* **`GPU found` never shows:** update the NVIDIA driver on Windows, then run `wsl --shutdown` in PowerShell and open Ubuntu again.
* **Generation stopped partway:** run `bash train.sh generate` again. It continues until there are enough clips.
* **No `.tflite` file:** `bash train.sh export` retries the conversion. The `.onnx` model works on its own if the conversion still fails.
* **`pip` version conflict during setup:** the versions in `requirements.txt` follow the openWakeWord training notebook. Copy the error and adjust only the package it names.
