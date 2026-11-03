# macserver

## Overview

**macserver** is the BellAI AI server rebuilt to run on a Mac (Apple Silicon) instead of the Windows PC and Firebase. Each folder replaces one part of the old setup. The iOS app, the Raspberry Pi and Insights ask for things the same way they always did, and `llm` answers them like Ollama.

There are no accounts. Anything on your Tailscale network can use the server, so being connected to Tailscale is the login. Install Tailscale on the Mac, the phone and the Pi, name the Mac `ai-server`, and keep the Mac's ports off the open internet. To use NetBird or the local network instead, set the address in the app under Settings > Server options (and `OLLAMA_HOST` on the Pi). Nothing on the Mac depends on Tailscale.

| Folder | What it replaces |
| --- | --- |
| [`llm`](llm/README.md) | Ollama: runs the chat model (Qwen3.5 4B) on MLX and answers like Ollama, on the same port (`11434`) the app, Insights and the Pi already use. |
| [`food`](food/README.md) | `Food Model`: reads a food photo or description and gives nutrition, using Qwen2.5-VL on MLX instead of CUDA. |
| [`voice`](voice/README.md) | `Server`: streams the chat reply and speaks it in Orpheus, which runs on MLX instead of GPT-SoVITS on an NVIDIA GPU. It also turns what you say into text with Whisper (new) and passes the app's food, insights and mail requests on to the other servers. |
| [`data`](data/README.md) | Firebase: keeps the app's saved data (tasks) in a local SQLite file. The app's Firebase login is gone. |
| [`insights`](insights/README.md) | `Insights`: food and workout suggestions from a day's meals, with the same code. The app's Recommendations card uses it. |
| [`mail`](mail/README.md) | New: reads your inboxes in the background, notes what matters, and writes drafts you approve before they are sent, from Discord or the app's Mail screen. |
| [`discord`](discord/README.md) | New: lets you talk to BellAI from Discord, in chat and with meal photos. |

## Setting up

Run `./setup.sh` once on the Mac that will host the servers. It checks the tools, then walks you through connecting a Discord bot and your email accounts, testing each login before it saves anything. Run `./setup.sh discord` or `./setup.sh email` to do one part, and run it again any time to change an answer. A blank answer skips a step.

* **Discord:** It shows how to make a bot, checks the token with Discord, and asks for the Discord user IDs that are allowed to talk to BellAI. Nobody else can.
* **Email:** It shows how to make an app password for Gmail, iCloud or Outlook (or takes any IMAP and SMTP server), checks the login, and asks how often to check for new mail. BellAI only reads on its own and needs your approval to send.
* **Where it saves:** Bot tokens and email passwords go in the macOS keychain (`bellai-discord`, `bellai-email`). The user IDs, email addresses, servers and the check interval go in `config/`, which is not in git.

The Discord settings are used by the [`discord`](discord/README.md) bridge, and the email settings by the [`mail`](mail/README.md) watcher.

## Running it

Run `./start.sh` to start everything. It starts `data`, `llm`, `food`, `insights` and `voice` in that order, then `mail` and `discord` if `./setup.sh email` and `./setup.sh discord` have been run, waits for each one to answer, and keeps the Mac awake while it runs. Logs are in `logs/`. Press Ctrl+C to stop all of them. If any one of them stops, the others are stopped too, so you can tell something is wrong. The first run downloads about 17 GB of models, so it takes a while.

| Port | Server | Reached by |
| --- | --- | --- |
| `11434` | `llm` | the app (text replies), the voice server, Insights, the Pi |
| `8000` | `voice` | the app (spoken replies, voice input, food photos, insights, mail) |
| `8001` | `data` | the app (tasks) |
| `8002` | `food` | the voice server only |
| `8003` | `mail` | the Discord bridge and the voice server (for the app) |
| `8004` | `insights` | the voice server only |

## Running it in the background

Run `./service.sh install` to have macOS start everything at login and keep it running. It uses a launchd agent (`~/Library/LaunchAgents/com.bellai.macserver.plist`) that runs `start.sh`, so if any one server stops, the whole set is stopped and started again about 30 seconds later.

* **Commands:** `./service.sh status` shows whether it is running and the voice server's health. `./service.sh logs` follows the main log, and `./service.sh logs llm` follows one server's log (`data`, `llm`, `food`, `voice`, `mail` or `discord`). `./service.sh restart` restarts it, and `./service.sh uninstall` stops it and removes the login item. Run `install` again after changing anything.
* **Where the repo lives:** macOS won't let background jobs read your Documents, Desktop, Downloads or iCloud Drive folders, so `install` refuses to run from there. Put the repo somewhere else, for example `git clone` it to `~/BellAI`, and run it from there. Or give `/bin/sh` Full Disk Access in System Settings > Privacy & Security and run `./service.sh install --anyway`. Granting Full Disk Access is your choice, since it lets every shell script read those folders.
* **After a restart:** The agent starts when you log in, not when the Mac boots. For a Mac that runs on its own, turn on automatic login in System Settings > Users & Groups. Automatic login isn't available with FileVault turned on, and the keychain needs the login to be unlocked.

Still to do: install Tailscale and name the Mac `ai-server`. The servers listen on every network interface, so the Tailscale login only holds if the Mac isn't reachable from other networks you don't trust, like a shared Wi-Fi.

## Menu bar status

[`menubar`](menubar) is a small 🐱 icon for the Mac's menu bar. Click it for two tabs. **Status** shows which servers are answering, in the same style as the status dot in the app, with a button to start or stop them all (it checks every 5 seconds and shows the mail server only while it is running). **Chat** talks to the chat model. With the speaker icon on, which it is to start with, the replies are also spoken through the voice server, and the chat waits until the audio has finished.

Run `cd menubar && swift build -c release && .build/release/BellMenu` to start it. To have it open at login, add `.build/release/BellMenu` in System Settings > General > Login Items & Extensions.
