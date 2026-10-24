# BellAI Raspberry PI Dashboard

## Overview

The Raspberry PI acts as the user's home device hub for communicating with BellAI using audio or text prompts.

## Features
* Raspberry PI 400 interface running Linux Server 26.04.
* Communication with BellAI through text prompts.
* Communication with BellAI through audio prompts (.webm).
* Speech-to-text transcription with Whisper locally installed on the RaspPI.
* Input validation for prompts.
* Error handling for connection issues with BellAI.

## Getting Started

### Prerequisites

* Raspberry PI 400.
* [Raspberry PI Imager](https://www.raspberrypi.com/software/) Version: `v2.0.12` for installing the following OS on the RaspPI.
* Linux Server Version: `v26.04.1 LTS`.
* 32gb microSD card for imaging.
* [Whispercpp](https://github.com/ggml-org/whisper.cpp) Version: `v1.9.5` installed locally on the RaspPI.
* BellAI Server: A running Ollama server with the configured model available. The default model is `qwen3:8b`.
* The device must be on the same network as the BellAI server with access to port `11434`.

### How to Enable / Access

1. Download `api.py` and input IP and port for the BellAI server.
2. Change pathing to Whispercpp if needed.
2. On RaspPI, run `uvicorn api:app --host 0.0.0.0 --port 8000` and access the FastAPI doc: http<!-- -->://IP:8000/docs.

## How to Use It

1. **Start a conversation:** Enter a prompt using post /chat to submit a string and post /audio to submit a .webm.
2. **Read the response:** Wait for the assistant's reply beneath your message. Only one request can run at a time, and replies appear when the server finishes rather than streaming word by word.
