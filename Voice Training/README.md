# BellAI
Home Assistant That Extends Beyond the Home

## Voice Training

This folder holds BellAi's voice: your recordings and two ways of turning them into a voice.

| Folder / file | What it is |
|---|---|
| `BellAi Studio.bat` | **Start here.** Opens BellAi Studio (the GPT-SoVITS voice website): type a line and hear it, train, and pick the best version. |
| `voice_data/` | Your recordings and the clips both voices learn from. |
| `orpheus/` | Everything for the Orpheus voice (scripts, models, test audio). |
| `studio/` | The BellAi Studio website (code, settings and test results). |
| `GPT-SoVITS/` | The GPT-SoVITS program and your trained GPT-SoVITS voice. See `READ ME - BellAi.txt` inside. |
| `_to_delete/` | Files no longer needed. Safe to delete. |

### voice_data/

| Folder | What it is |
|---|---|
| `raw/` | Your first recording. |
| `new_recordings/` | Later recordings, added with `prepare_dataset.py --add`. |
| `clips/` | The cut-up training clips and `metadata.csv` (what's said in each one). |
| `gpt_sovits/` | The training list GPT-SoVITS reads (made automatically). |
| `removed_clips/` | Clips and transcripts taken out of training, plus backups. |
| `unused_recordings/` | Recordings not used for training. |

### orpheus/

Run these from inside the `orpheus` folder (`cd orpheus` first).

| Script | What it does |
|---|---|
| `prepare_dataset.py` | Cuts recordings into clips and transcribes them (feeds both voices). |
| `tune_voice.py` | Trains the Orpheus voice and keeps the best epoch. |
| `export_voice.py` | Puts the trained voice into Ollama (`--q6` for a faster 6-bit copy). |
| `fast_speak.py` | Type a line, hear it in real time. |
| `speak.py` | Slower, no Ollama needed. |
| `train_voice.py`, `fix_clips.py` | Helpers used by the scripts above. |

| Folder | What it is |
|---|---|
| `models/` | The trained Orpheus voice (`bella_voice_lora`), the merged model, the 8-bit and 6-bit GGUF files and their Modelfiles. |
| `outputs/` | Training checkpoints (`training_runs`), and each epoch's test audio (`tune_outputs`). |
| `tools/` | llama.cpp converter (downloaded automatically by `export_voice.py`). |

### Common tasks

- **Hear the GPT-SoVITS voice:** double-click `BellAi Studio.bat`.
- **Hear the Orpheus voice:** `cd orpheus` then `python fast_speak.py` (Ollama must be running).
- **Add a new recording:** put it in `voice_data/new_recordings`, then `cd orpheus` and `python prepare_dataset.py --add`.
- **Retrain GPT-SoVITS:** BellAi Studio, Training, Train new voice.
- **Retrain Orpheus:** `cd orpheus`, `python tune_voice.py`, then `python export_voice.py`.
- **Where the GPT-SoVITS voice lives:** `GPT-SoVITS/GPT-SoVITS-v3lora-20250228/SoVITS_weights_v2/bellai_1012_2137_e16_s1040.pth` and `GPT_weights_v2/bellai_1012_2137-e30.ckpt`, plus the reference clip named in `studio/studio_settings.json`.
