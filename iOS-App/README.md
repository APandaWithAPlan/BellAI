# BellAI iOS App

## Overview

**BellAI** is an iOS assistant designed to extend help beyond the home. The current app lets you send text prompts to an Ollama server, read replies, and continue a conversation with follow-up questions.

The Home screen also previews Lights, Climate, Plan, and Security with static sample values; these cards do not control devices or manage tasks yet. Activity and Settings are placeholder screens, voice input is disabled, and the speaker button currently changes its icon without producing spoken responses.

## Getting Started

### Prerequisites

* Minimum App Version: `v1.0` (current development version, build `1`).
* Minimum iOS Version: `27.0`, as currently configured in the Xcode project.
* Account Tier / Permissions needed: No in-app account, paid tier, or API key is currently required. The device must have Tailscale access to `ai-server` on port `11434`; allow local-network access if prompted.
* Server: A running Ollama server with the configured model available. The default model is `qwen3:8b`.
* Development setup: Open `BellAI.xcodeproj` in Xcode with support for the configured iOS target, select the BellAI app and a compatible device or simulator, then build and run. See [Ollama development configuration](Config/README.md) for model configuration and offline checks.

### How to Enable / Access

1. Open the app to the **Home** tab.
2. Tap **What can I help with?** and type your first message. No feature toggle is required.
3. Tap the **Send** arrow or the keyboard's **Send** key. The app opens **BellAI**, displays your message, and shows **Thinking…** while waiting for a reply.

## How to Use It

1. **Start a conversation:** From **Home**, enter a prompt such as “Help me plan my day” and send it.
2. **Read the response:** Wait for the assistant's reply beneath your message. Only one request can run at a time, and replies appear when the server finishes rather than streaming word by word.
3. **Ask a follow-up:** On the **BellAI** screen, tap the **keyboard** button, type another message, and tap the **Send** arrow or the keyboard's **Send** key. Previous user and assistant messages are included for context.
4. **Move between screens:** Use the bottom navigation to switch tabs. Returning to **BellAI** preserves the current conversation while the app remains running; the close button returns you to **Home**.
5. **Start fresh:** Submit a new prompt from **Home** to replace the current conversation with a new session.
6. **Handle an error:** Validation problems appear in an alert; server or connection failures appear in the conversation. Check your Tailscale connection, server availability, and configured model, then send your message again.

> 💡 **Tip:** Keep each message to 1–4,000 characters after trimming surrounding whitespace. Conversation history is kept only in memory and is not saved across app launches; sending a valid new prompt from Home clears the previous conversation.
