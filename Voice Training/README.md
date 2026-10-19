# BellAI Voice Training

Two voice engines trained on the same recordings: GPT-SoVITS (fast) and Orpheus (more expressive).

## GPT-SoVITS

1. Unzip GPT-SoVITS into `GPT-SoVITS/` so `GPT-SoVITS/GPT-SoVITS-v3lora-20250228/runtime/python.exe` exists.
2. Double-click `BellAi Studio.bat`. It opens http://localhost:9890.
3. Type a line to hear it, or use Training > Train new voice to retrain.

## Orpheus

Needs an NVIDIA GPU and [Ollama](https://ollama.com). Run everything from the `orpheus` folder.

```
pip install torch torchaudio transformers peft snac soundfile faster-whisper sounddevice scipy sentencepiece
python prepare_dataset.py
python tune_voice.py
python export_voice.py
python fast_speak.py
```

New recordings go in `voice_data/new_recordings`, then run `python prepare_dataset.py --add`.

## Files

| File | What it does |
|---|---|
| `studio/bellai_studio.py` | Web UI for GPT-SoVITS: speak, train, and pick the best version. |
| `orpheus/prepare_dataset.py` | Cuts recordings into clips and transcribes them with Whisper. |
| `orpheus/fix_clips.py` | Fixes clip start and end points. Used by `prepare_dataset.py`. |
| `orpheus/train_voice.py` | Fine-tunes Orpheus 3B with LoRA. |
| `orpheus/tune_voice.py` | Trains several epochs, scores each one, and keeps the best. |
| `orpheus/export_voice.py` | Converts the voice to GGUF and loads it into Ollama (`--q6`, `--q5`, `--fast` for smaller versions). |
| `orpheus/fast_speak.py` | Real-time streaming speech through Ollama. |
| `orpheus/speak.py` | Slower speech without Ollama. |
