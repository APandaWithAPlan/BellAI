# BellAI Wake Word Listener

## Overview

Listens for "BellAi" on the Raspberry PI microphone, records the command that follows, and sends it to `api.py` for transcription and a reply.

## Features
* Hands-free wake word detection with the trained BellAi model.
* Records the command until the speaker stops talking.
* Sends the command to `api.py` (`POST /audio`) as a .webm.
* Says "connection dropped" if the wake word is heard while the BellAI server is offline, using `connection_dropped.wav` recorded in the BellAi voice.

## Getting Started

### Prerequisites

* Raspberry PI with `api.py` running.
* USB microphone (Razer).
* [uv](https://docs.astral.sh/uv/) for installing Python 3.12.
* `BellAi.onnx`, `melspectrogram.onnx` and `embedding_model.onnx` in this folder or in `Wake Word/models`.
* Optional: `wake.wav` (chime) and `connection_dropped.wav` in this folder. Without `wake.wav` a built-in chime plays.

### How to Enable / Access

1. Install: `sudo apt install ffmpeg alsa-utils`, then `uv venv --python 3.12 ~/bellai-env`, `source ~/bellai-env/bin/activate` and `uv pip install onnxruntime numpy scipy scikit-learn requests tqdm && uv pip install --no-deps openwakeword==0.6.0`.
2. In BellAi Studio, speak `Connection dropped.`, save the audio and put it in this folder as `connection_dropped.wav`.
3. Run `python wake_listener.py --server http://IP:11434` using the BellAI server's IP.

## How to Use It

1. **Wake it:** Say "BellAi" and wait for the chime.
2. **Ask:** Say the command. Recording stops after 1 second of quiet.
3. **Read the response:** The reply prints in the terminal.
4. **Mic volume:** The mic is boosted 5x by default (`--gain 5`). Use a lower `--gain` if close-up speech sounds distorted.
5. **Test the model:** Run with `--scores` to see how sure the model is (0 to 1) each time it hears something, without sending anything.
6. **Handle an error:** If BellAi wakes up by mistake, raise `--threshold` (default `0.5`). If the mic isn't found, run `--list-mics` and pass part of its name with `--mic`.
