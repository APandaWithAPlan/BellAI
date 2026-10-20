# BellAi Voice Model

## Overview

**BellAi Voice** turns text into speech in Bella's voice. It runs a GPT-SoVITS v2 model fine-tuned on about 48 minutes (477 clips) of Bella's recordings, and it runs locally on an NVIDIA GPU. Orpheus 3B was also trained and tested but was not used.

Speech is generated one sentence at a time, so audio starts before the whole reply is finished. The voice can be used from the BellAi Studio page in a browser or from the voice API for the app and server. Generated speech can be saved as a .wav file.

## Getting Started

### Prerequisites

* Operating System: Windows 10 or 11.
* GPU: An NVIDIA GPU is needed for real-time speech. It was tested on an RTX 4500 Ada (24 GB). A CPU works but takes several seconds per sentence.
* GPT-SoVITS: Download the GPT-SoVITS Windows package (`GPT-SoVITS-v3lora-20250228`) and unzip it into the `GPT-SoVITS` folder, so that `GPT-SoVITS/GPT-SoVITS-v3lora-20250228/runtime/python.exe` exists.
* Model files: The trained model goes in the GPT-SoVITS weights folders (`GPT_weights_v2` and `SoVITS_weights_v2`). The chosen versions are saved in `studio/studio_settings.json`.
* Files:
  * `studio/bellai_studio.py` runs the studio page (speaking, training and testing), and `studio/index.html` is the page.
  * `studio/bellai_voice_server.py` is a small web API for the voice (`POST /tts` returns audio).
  * `dataset/prepare_dataset.py` cuts recordings into clips and transcribes them with Whisper.

### How to Enable / Access

1. Double-click `BellAi Studio.bat` in the Voice Training folder.
2. Wait for the window to say **Ready**. The first launch takes longer while the model loads onto the GPU.
3. Open **http://localhost:9890** in a browser.

## How to Use It

1. **Speak a sentence:** Type a sentence in the text box and press **Enter**. The voice starts playing as soon as the first sentence is ready.
2. **Check the speed:** The time to first sound is shown under the text box after every sentence. The goal is producing a sound under 2 seconds.
3. **Save the audio:** After the speech is generated, save it as a .wav file. WAV is used instead of MP3 so no time is spent converting file types.
4. **Find the best version:** Click **Find best settings** to test every saved model version and several reference clips on the same 5 sentences. Each version is scored on how similar it sounds to the real clips and how many words Whisper hears correctly. The audio from each test is kept in `studio/eval/`, so it can be checked by ear. In the latest test of 15 versions, the chosen model scored 0.979 speaker similarity and 98.7% words correct.
5. **Use it from the app or server:** Run `studio/bellai_voice_server.py` with GPT-SoVITS's Python, then send `POST /tts` with `{"text": "Hello!"}`. Audio comes back as a WAV stream.
6. **Handle an error:** If **Ready** never shows, check that the GPT-SoVITS folder is unzipped in the right place and that the NVIDIA drivers are installed, then launch `BellAi Studio.bat` again.

> 💡 **Tip:** End every sentence with a period, question mark or exclamation point. Text is split at sentence ends, not commas, because comma splits made sentences end early. Words ending in "s" were also being cut off; `dataset/fix_clips.py` and `dataset/fix_clip_endings.py` fixed the training clips, and the studio now holds the last sound slightly longer.