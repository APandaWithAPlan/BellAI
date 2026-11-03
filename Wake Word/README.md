# BellAi Wake Word

## Overview

**BellAi Wake Word** is the small model that listens for "BellAi" so the Raspberry Pi can start recording a command without a button press. It is trained with openWakeWord on about 50,000 synthetic clips from Piper TTS, 1,800 clips in the BellAi voice (GPT-SoVITS), and real recordings from Bella and Jo. Near-miss words such as "Bella", "belly" and "bell" are included so the model learns what not to wake on.

Training runs in WSL on an NVIDIA GPU and outputs `BellAi.onnx` (about 200 KB), which the Pi listener in `RaspPI-Server/wake_listener` uses.

## Getting Started

### Prerequisites

* Operating System: Windows 10 or 11 with WSL2 (Ubuntu).
* GPU: An NVIDIA GPU, with `nvidia-smi` working in WSL. It was trained on an RTX 4500 Ada (24 GB).
* Disk: About 40 GB free in WSL. The training environment and data are kept in `~/bellai-wakeword`, not in this folder.
* Files:
  * `setup.sh` installs everything and downloads the training data.
  * `train.py` cuts the recordings into clips, trains the model and copies it into `models/`.
  * `make_sovits_clips.py` makes "BellAi" and near-miss clips in the BellAi voice through BellAi Studio.
  * `bellai_model.yml` holds the training settings (the target phrase, near-miss words and number of clips).
* Dataset:
  * `recordings/<person>/` holds each person's takes from the recording script, one per part, named `close`, `mid`, `far`, `nearmiss_close`, `nearmiss_mid`, and `nearmiss_far`.
  * `custom_clips/` holds the one-word clips: `positive_train` ("BellAi"), `negative_train` (near misses and talking), and `positive_test` / `negative_test` for test speakers. Clips are named by person, take, and number, e.g. `Bella_far_000.wav`.

### How to Enable / Access

1. Open Ubuntu (WSL) and go to this folder: `cd "/mnt/c/Users/Bella Breaux/Documents/GitHub/BellAI/Wake Word"`.
2. Run `bash setup.sh` once. It ends with **GPU found** when everything is ready.
3. Run `source ~/bellai-wakeword/.venv/bin/activate` each time a new Ubuntu window is opened.

## How to Use It

1. **Make BellAi voice clips:** Open BellAi Studio, then run `python make_sovits_clips.py` in PowerShell.
2. **Add recordings:** Put each person's takes in `recordings/<person>/`. Any audio format works.
3. **Train:** Run `python train.py`. It runs these steps in order, skipping work that is already done:
   * `generate` makes the synthetic Piper clips.
   * `prepare` cuts the recordings into one-word clips and gets every clip in `custom_clips` ready for training.
   * `augment` adds room echo and background noise to the clips.
   * `train` trains the model.
   * `export` copies the finished model into `models/`.

   To run only one step, add its name, EX: `python train.py prepare` to cut new recordings and check the clip counts before training, or `python train.py export` if the model was trained but not copied.
4. **Check the clips:** `prepare` prints how many "BellAi" clips it cut from each take (20 close, 15 mid, 15 far). If a count is off, listen to that take's clips in `custom_clips` and delete any that are not "BellAi". Deleted clips stay deleted.
5. **Use the model:** The finished model is saved in `models/`. Copy the three `.onnx` files to the Pi listener.
6. **Handle an error:** If a step stops, run the same step again; it continues where it left off. If `setup.sh` does not show **GPU found**, update the NVIDIA driver on Windows and run `wsl --shutdown` in PowerShell.

> 💡 **Tip:** Training takes a few hours. Keep the PC from sleeping (Settings → System → Power & battery) and leave the Ubuntu window open; locking the screen is fine.
