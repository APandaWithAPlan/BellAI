# BellAI for Mac

A native SwiftUI chat app for macOS, in pink, with the BellAI fox as its icon. It works like ChatGPT or Claude: a sidebar of conversations grouped by day, replies that stream in as they are written, Markdown and code blocks, and light and dark appearances.

It talks to any OpenAI-compatible server, so it works with the [`macserver`](../macserver/README.md) chat model, Ollama, and similar. Conversations are saved on your Mac, in `~/Library/Application Support/BellAI/conversations.json`.

## What it has

The same features as the iOS app, on the same servers, plus the Mac's own:

* **Chat** with spoken replies and voice input (click the microphone, speak, and it sends when you pause). BellAI knows your open tasks and important emails when you chat.
* **Tasks**, kept on the data server, so they are the same ones as on the phone.
* **Mail** the Mac's mail watcher has read, with replies and new emails written by BellAI. Nothing is sent until you press Send on the review screen.
* **Meals:** drop in a photo of a meal for calories and protein, correct them, add the meal to today's journal, and get food and exercise recommendations within your food preferences.
* **Captures:** the home camera's earlier clips by day, played in the app.
* **Servers:** start, stop and watch macserver, and read its logs.
* **Recorder:** a step-by-step guide to wiring, building, flashing and testing the clip-on recorder (Pico W), with each command ready to copy and the wiring shown. The pinout is in [`Recorder/PINOUT.md`](../Recorder/PINOUT.md).

Left out because they belong to the phone: Apple Health (meals are kept in the journal only), the weather briefing (WeatherKit), the Recorder's Wi-Fi setup, and the Lights, Climate and Security cards, which only show sample values in the iOS app anyway.

The iOS app's models, services and view models are built into this app from `../iOS-App/BellAI`, not copied, so a fix there applies here too. They are listed in `project.yml`.

## Run it

Needs Xcode and macOS 14 or later.

```sh
open BellAI.xcodeproj   # then press Run
```

or build it from the terminal:

```sh
xcodebuild -project BellAI.xcodeproj -scheme BellAI -configuration Release build
```

The app isn't sandboxed, because it has to run `start.sh`, and the first time it reads the repo in Documents macOS asks you to allow it. It is signed to run on this Mac only. To share it, set your team under Signing & Capabilities.

## Use it

* **Voice:** replies are read aloud in BellAI's voice, a sentence at a time as they are written, through the voice server on port 8000 of the same Mac as the chat server. The speaker button in the toolbar turns it on or off, and the arrow becomes a stop button while a reply is being written or spoken. If the voice server isn't answering, replies come as text and a note says so.
* **⌘N** starts a new chat. Return sends. The arrow becomes a stop button while a reply is being written.
* **Servers:** the row at the bottom of the sidebar shows whether macserver is up. Click it to see each server (chat model, voice, data, food, insights, mail), start or stop them all, and follow any server's log. Starting runs `macserver/start.sh`, the same as the terminal or the menu bar app, and stopping ends it. The app finds the `macserver` folder of the checkout it was built from, or you can choose another with Choose Folder. If you installed the launchd service (`./service.sh install`), stop it with `./service.sh uninstall` instead, because launchd starts the servers again.
* **⌘,** opens Settings: where macserver is (`localhost` on this Mac, or its name on Tailscale like `ai-server`) and the port of each server, and optionally a model name. Without one, the app uses the first model the server lists.

## Files

| Path | What it is |
| --- | --- |
| `project.yml` | [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec. Edit it and run `xcodegen generate` to rebuild `BellAI.xcodeproj` and `Info.plist`. |
| `BellAIMac/ChatClient.swift` | `GET /v1/models` and the streamed `POST /v1/chat/completions` for text. Spoken replies use the iOS app's voice client. |
| `BellAIMac/Features.swift` | The tasks, mail, meals and captures view models, shared with iOS, and what chat is told about them. |
| `BellAIMac/Views/RecorderSetupView.swift` | The Recorder setup guide. |
| `BellAIMac/ServerController.swift` | Starts, stops and checks macserver, and reads its logs. |
| `BellAIMac/ChatStore.swift` | Conversations, the open one, the reply being written, and saving. |
| `BellAIMac/Theme.swift` | The pink palette, light and dark. |
| `BellAIMac/Views` | The window, sidebar, chat, messages and Settings. |
| `BellAIMac/Assets.xcassets` | The app icon, the chat avatar, and the accent color. |
