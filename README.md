# BellAI

## Overview

**BellAI** is a personal AI assistant for iOS that speaks in a custom voice. You chat with it by text, send it a photo of a meal to get a spoken nutrition summary, and keep a to-do list that BellAI knows about. Everything runs on your own hardware and is reached over Tailscale, with no cloud AI service.

## Repository layout

| Folder | What it is |
| --- | --- |
| [`iOS-App`](iOS-App/README.md) | The iOS App and it's components |
| `Server` | The "main" server. It streams Ollama's reply over a WebSocket (`/ws`) and returns each sentence as a wav clip. |
| [`Voice Training`](Voice%20Training/README.md) | The Voice Model |
| [`Food Model`](Food%20Model/README.md) | Meal Analysis|
| `RaspPI-Server` |FastAPI service for the Raspberry Pi that forwards prompts to the AI server and transcribes audio with whisper.cpp. |
| [`firebase`](firebase/README.md) | Firestore and Cloud Functions |

## How it fits together

```
iOS app ──Tailscale──▶ ai-server
                         ├─ :11434  Ollama (chat, qwen3.5:4b-q4_K_M)
                         └─ :8000   voice server + food model
                                      /ws       streamed reply + sentence audio
                                      /analyze  photo and/or text → summary, items, totals
                                      /speak    text → wav
iOS app ──────────────▶ Firebase (anonymous auth, encrypted task storage)
```

## Features

* **Chat:** Send a prompt from Home, then keep going with follow-ups. Replies stream in as they are written.
* **Spoken replies:** With the speaker on, each sentence is read aloud in the BellAI voice as soon as it is ready.
* **Photo analysis:** BellAi can analyze photos of food and relay information about that meal back to you
* **Tasks:** A to-do list saved to your Firebase account. BellAI sees your open tasks as context when you chat.
* **Placeholders:** The Home cards (Lights, Climate, Plan, Security) show sample values only, and the Activity and Settings tabs are empty, this was done to
