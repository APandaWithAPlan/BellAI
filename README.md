# BellAI

## Overview

**BellAI** is a personal AI assistant for iOS that speaks in a custom voice. You chat with it by text or by voice, send it a photo of a meal to get a nutrition summary, get food and workout suggestions from what you ate, read and answer your email with BellAI's help, and keep a to-do list that BellAI knows about. You are the cloud, you hold your own data.

## Repository layout

| Folder | What it is |
| --- | --- |
| [`iOS-App`](iOS-App/README.md) | The iOS App and it's components |
| [`macserver`](macserver/README.md) | The AI server, which runs on a Mac with Apple Silicon: chat model, voice, food analysis, insights, saved data, and the Discord and email helpers |
| [`Voice Training`](Voice%20Training/README.md) | The Voice Model |
| [`Insights`](Insights/README.md) | Food and workout suggestions, the original version (the Mac one is in `macserver/insights`) |
| `RaspPI-Server` |FastAPI service for the Raspberry Pi that forwards prompts to the AI server and transcribes audio with whisper.cpp, and the home dashboard. |
| `Server`, [`Food Model`](Food%20Model/README.md) | The first versions of the voice server and meal analysis, for a Windows PC with an NVIDIA GPU. `macserver` replaces them. |
| [`firebase`](firebase/README.md) | The old Firestore and Cloud Functions backend. The app no longer uses it, because tasks are saved by `macserver/data`. |

## How it fits together

```
iOS app ──Tailscale──▶ ai-server (a Mac)
                         ├─ :11434  chat model (Qwen3.5 4B on MLX, answers like Ollama)
                         ├─ :8000   voice server
                         │            /ws          streamed reply + sentence audio (Orpheus on MLX)
                         │            /transcribe  recording → text (Whisper on MLX)
                         │            /analyze     photo and/or text → summary, items, totals
                         │            /insights    meals and goals → food and workout ideas
                         │            /mail        emails the mail watcher has read
                         │            /drafts      replies waiting for your approval
                         │            /speak       text → wav
                         └─ :8001   data server (tasks, in a SQLite file)
Raspberry Pi ──Tailscale──▶ ai-server :11434
Discord, email ◀────────▶ ai-server (bot and mail watcher, optional)
```

There are no accounts. Being on your Tailscale network is the login, so nothing is stored outside your own machines.

## Features

* **Chat:** Send a prompt from Home, then keep going with follow-ups. Replies stream in as they are written.
* **Spoken replies:** With the speaker on, each sentence is read aloud in the BellAI voice as soon as it is ready.
* **Voice input:** Tap the microphone and speak. The phone records and Whisper on the Mac turns it into text, so nothing is sent to Apple.
* **Photo analysis:** Take or choose a photo of a meal. BellAI shows the calories and protein in a sheet, lets you correct them, and logs the meal to Apple Health.
* **Recommendations:** From the meals you log and your preferences (calorie goal, diet, allergies, injuries), BellAI suggests foods and workouts. Anything that breaks your limits is removed on the Mac before you see it.
* **Mail:** The Mac reads your inboxes, notes what matters, and shows it in the app. BellAI can write a reply or a new email, and it is only sent when you press Send.
* **Weather:** The Agenda screen shows the weather for your city from Apple WeatherKit.
* **Tasks:** A to-do list saved on your Mac. BellAI sees your open tasks and important emails as context when you chat.
* **Server options:** Change the Mac's address in Settings to use Tailscale, NetBird or your local network.
* **Placeholders:** The Lights, Climate and Security cards on Home show sample values only and do not control anything yet.
