# BellAI Raspberry PI Dashboard

## Overview

The Raspberry PI acts as the user's home device hub for communicating with BellAI using audio or text prompts.

## Features
### Backend
* Raspberry PI 400 interface running Linux Server 26.04.
* Communication with BellAI through text prompts.
* Communication with BellAI through audio prompts (.webm).
* Speech-to-text transcription with Whisper locally installed on the RaspPI.
* Input validation for prompts.
* Error handling for connection issues with BellAI.
* Integration with Home Assistant.
### Frontend
* Dashboard with Home, Devices, Life, and BellAI tabs.
    * Home: Displays general information at a glance such as the date, time, weather, and location.
    * Devices: Displays devices connected with Home Assistant and allows the user to control their state.
    * Life: Displays calendar events, important emails, a to-do list, and upcoming deliveries.
    * BellAI: Displays conversation history between the user and BellAI (currently non-persistant) and allows the user to send messages or audio recordings.

## Getting Started

### Prerequisites

* Raspberry PI 400.
* [Raspberry PI Imager](https://www.raspberrypi.com/software/) Version: `v2.0.12` for installing the following OS on the RaspPI.
* Linux Server Version: `v26.04.1 LTS`.
* 32gb microSD card for imaging.
* [Whispercpp](https://github.com/ggml-org/whisper.cpp) Version: `v1.9.5` installed locally on the RaspPI.
* [Home Assistant Core](https://pypi.org/project/homeassistant/) via `pip install homeassistant`.
* BellAI Server: The Mac server in [`macserver`](../macserver/README.md), which answers like Ollama on port `11434`. Set `OLLAMA_HOST=ai-server:11434` for the backend. The model name in `api.py` is ignored, because the Mac runs one model.
* The device must be on your Tailscale network with access to `ai-server` on port `11434`.
* A browser and graphical interface to display the dashboard. Tested: `Chromium` with `Xorg`.

### How to Enable / Access

1. Clone the repository and set `OLLAMA_HOST=ai-server:11434` for the BellAI server.
2. Change pathing to Whispercpp, Home Assistant if needed.
3. Include your Home Assistant token in a .env.
4. Run `uvicorn api:app --host 127.0.0.1 --port 8000` to start the FastAPI backend.
5. Run `hass -c /homeassistant/config` to start the Home Assistant backend.
6. Build the dashboard with `npm run build` to a folder called dashboard.
7. Start the browser with `startx`.

## How to Use It

For now, the dashboard is mainly for display and contains placeholder values, but you can:
1. **Start a conversation:** Enter a prompt to BellAI by typing and sending a message in the chat or recording one. 
2. **Read the response:** Wait for the assistant's reply beneath your message. Only one request can run at a time, and replies appear when the server finishes rather than streaming word by word.