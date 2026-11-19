# BellAi HIL Testbed

## Overview

Checks that the BellAi code can talk to its camera and microphone on every push, first against virtual devices on any computer and then against the real ones on the Raspberry Pi. Scenarios describe a room and what happens in it (light, people walking by, the wake word, a cable being pulled). An AI model writes new scenarios, a small model of how the camera and mic behave decides what each scenario should produce, and the testbed plays every scenario through virtual webcams and USB mics that `homecam-motion.py` and `wake_listener.py` read the same way they read the real hardware.

## Features
* Virtual camera that answers on the same go2rtc addresses the Pi uses, and can be unplugged and plugged back in mid-scenario.
* Virtual microphone that shows up in `arecord -l` and plays the scenario like a live mic.
* Camera and mic play the same scenario together on one shared clock.
* Runs `homecam-motion.py` itself against the virtual camera and checks that it records motion.
* Device list in `devices.json`: the Razer Kiyo, the 360p lite stream, a 1080p webcam, the Razer mic and a generic USB mic. Every scenario runs on every device for its stage.
* Faults that are hard to cause on real hardware: unplugged, black, frozen or corrupt camera, silent or clipped mic.
* Scenarios written by the BellAi model through Ollama, then limited in code before they are used.
* Coverage of the device model, with built-in scenarios added for any step the files miss.
* Measurements on every run: time to first frame, frame rate and drops, reconnect time, brightness, sharpness, tone level and checks per minute.
* Every failure is marked as `environment`, `device`, `behavior` or `compatibility`.
* Comparison between devices and between the virtual and Pi runs, to show where they disagree.
* A GitHub Actions workflow that runs the virtual stage on a commit and the Pi stage only if the virtual stage passes.

## Getting Started

### Prerequisites

* Linux, WSL or macOS with Python 3.12 and `ffmpeg`. The virtual mic does not work in plain Windows, so use WSL there.
* `numpy` and `opencv-python-headless` for the camera tests.
* For the wake word check: the same packages as `wake_listener.py`, and one or more short clips of someone saying "BellAi" in `clips/wake`.
* For new AI scenarios: Ollama, or the BellAI server, with `qwen3.5:4b-q4_K_M`.
* For the Pi stage: the Pi with go2rtc running, the webcam, the Razer mic and a speaker.

### How to Enable / Access

1. Install: `pip install numpy opencv-python-headless onnxruntime scipy scikit-learn requests tqdm && pip install --no-deps openwakeword==0.6.0`.
2. Copy two or three wake word clips into `clips/wake`, or make one in the BellAi voice with `python scenarios.py --speak http://IP:9880`.
3. Run `python run_hil.py --stage virtual` from this folder.
4. For commits: copy `hil.yml` to `.github/workflows/hil.yml` at the top of the repo, then push the branch. On every push GitHub runs the quick virtual checks on the BellAi camera and mic.
5. For the Pi stage: add the Pi as a self-hosted runner with the label `bellai-pi` (repo Settings, Actions, Runners), run `uv pip install --python ~/bellai-env/bin/python opencv-python-headless` on the Pi, then set the repo variable `HIL_PI_READY` to `true`.

## How to Use It

1. **Run the virtual stage:** `python run_hil.py --stage virtual`. Each scenario prints its checks for each device as PASS, FAIL or SKIP. A full run takes about four minutes because the camera service runs in real time.
2. **Run faster:** `python run_hil.py --stage virtual --speed 4 --devices virtual-kiyo-720p virtual-seiren-mini` plays scenarios four times faster on just the BellAi devices. The camera service check is skipped at this speed.
3. **Make new scenarios with AI:** `python scenarios.py --generate 5 --server http://IP:11434`. The ones that pass the limits are added to `scenarios/generated.json`, with how many model steps they reach.
4. **Check coverage:** `python scenarios.py --coverage` lists the camera and mic model steps the scenario files miss. `run_hil.py` adds its own scenarios for those steps unless you pass `--no-model`.
5. **Run on the Pi:** `python run_hil.py --stage physical`. It checks the live camera through go2rtc, then plays each scenario's sound through the speaker and checks what the real mic heard. Use `--no-speaker` to skip the sound.
6. **Compare runs:** `python compare_runs.py results/virtual-....json results/physical-....json` lists the checks where the virtual and Pi runs disagree.
7. **Compare wake word models:** add `--wake-model "../Wake Word/models/BellAi_v2.onnx"` (any model next to `melspectrogram.onnx` and `embedding_model.onnx`) to test a newly trained model on the same scenarios.
8. **Read the results:** Each run saves a file in `results` and adds its rows to `results/history.csv` with the commit, device, check, result, failure type and measurement.
9. **Handle an error:** `environment` means something is missing on the test machine or it is too busy. `device` means the camera or mic is missing, black, frozen, silent or clipped. `behavior` means the device works but the code did not do what the scenario expects. `compatibility` means a device that is not BellAi's own failed, which does not fail the run.

**Tip:** On the Pi, stop the wake listener first with `sudo systemctl stop bellai-listener` so the mic is free, and start it again after the run.
