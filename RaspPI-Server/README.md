# BellAI Raspberry PI Dashboard

## Overview

The Raspberry PI acts as the user's home device hub for communicating with BellAI using audio or text prompts.

## Features
### Backend
* Raspberry PI 400 interface running Linux Server 26.04.
* Communication with BellAI through text prompts.
* Communication with BellAI through audio prompts (.webm).
* Real-time audio and text streaming of BellAI's responses
* Speech-to-text transcription with Whisper locally installed on the RaspPI.
* Input validation for prompts.
* Error handling for connection issues with BellAI.
* Integration with Home Assistant for devices (lights) and Spotify.
### Frontend
* Dashboard with Home, Devices, Life, and BellAI tabs.
    * Home: Displays general information at a glance such as the date, time, weather, and location. Also displays devices playing Spotify with Pause/Play, Forward, and Backward controls
    * Devices: Displays devices connected with Home Assistant and allows the user to control their state. Currently only works with lights and toggle on/off actions.
    * Life: Displays calendar events, important emails, a to-do list, and upcoming deliveries pulled from /mail and /data on the server.
    * BellAI: Displays (non-persistent) conversation history between the user and BellAI (currently non-persistant) and allows the user to send messages or audio recordings.

## Getting Started

### Prerequisites

* Raspberry PI 400.
* [Raspberry PI Imager](https://www.raspberrypi.com/software/) Version: `v2.0.12` for installing the following OS on the RaspPI.
* Linux Server Version: `v26.04.1 LTS`.
* 32gb microSD card for imaging.
* [Whispercpp](https://github.com/ggml-org/whisper.cpp) Version: `v1.9.5` installed locally on the RaspPI.

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
1. **Control Spotify** Press play, pause, skip forward, and skip backward buttons on the dashboard to control music being played on your Spotify account
2. **Control Smart Home Devices** Toggle on and off matter-enabled smart light-bulbs connected to Home Assistant.
3. **View Upcoming Events, Important Emails, and Tasks** View upcoming calendar events, important emails, and tasks displayed on the Life page.
3. **Start a conversation:** Enter a prompt to BellAI by typing and sending a message in the chat or recording one. 
4. **Read the response:** Wait for the assistant's reply beneath your message. Only one request can run at a time, and replies are streamed with text and audio.