# BellAI iOS App

## Overview

**BellAI** is an iOS assistant designed to extend help beyond the home. The current app lets you send text prompts to an Ollama server, read replies, and continue a conversation with follow-up questions.

The Home screen also previews Lights, Climate, Plan, and Security with static sample values; these cards do not control devices or manage tasks yet. The Tasks tab is a to-do list: add, check off and swipe to delete. It is saved to your Firebase account (encrypted, anonymous sign-in) and loads again on launch. Activity and Settings are placeholder screens, and voice input is available from the microphone buttons. Grant microphone and speech recognition permissions on first use. Five seconds without new recognized speech ends capture; a nonempty transcript is sent through the same chat flow as typed text. Tap the stop button to cancel. Recording stops before a request is sent and stays off during the reply. The speaker button turns spoken replies on or off: when on, replies stream in word by word and are read aloud in the BellAI voice by the voice server, which runs separately from this app.

## Getting Started

### Prerequisites

* Minimum App Version: `v1.0` (current development version, build `1`).
* Minimum iOS Version: `27.0`, as currently configured in the Xcode project.
* Account Tier / Permissions needed: No in-app account, paid tier, or API key is currently required. The device must have Tailscale access to `ai-server` on port `11434`; allow local-network access if prompted.
* Server: A running Ollama server with the configured model available. The default model is `qwen3.5:4b-q4_K_M`. For spoken replies, also run the voice server on the same machine; it listens on port `8000`, which must be reachable over Tailscale.
* Development setup: Open `BellAI.xcodeproj` in Xcode with support for the configured iOS target, select the BellAI app and a compatible device or simulator, then build and run. See [Ollama development configuration](Config/README.md) for model configuration and offline checks.

### How to Enable / Access

1. Open the app to the **Home** tab.
2. Tap **What can I help with?** and type your first message. No feature toggle is required.
3. Tap the **Send** arrow or the keyboard's **Send** key. The app opens **BellAI**, displays your message, and shows **Thinking…** while waiting for a reply.

## How to Use It

1. **Start a conversation:** From **Home**, enter a prompt such as “Help me plan my day” and send it.
2. **Read the response:** Wait for the assistant's reply beneath your message. Only one request can run at a time, and with the speaker on, the reply streams in as it is written and each sentence is spoken as soon as it is ready; with the speaker off (or if the voice server is unreachable) the reply appears when the server finishes.
3. **Ask a follow-up:** On the **BellAI** screen, tap the **keyboard** button, type another message, and tap the **Send** arrow or the keyboard's **Send** key. Previous user and assistant messages are included for context.
4. **Move between screens:** Use the bottom navigation to switch tabs. Returning to **BellAI** preserves the current conversation while the app remains running; the close button returns you to **Home**.
5. **Start fresh:** Submit a new prompt from **Home** to replace the current conversation with a new session.
6. **Handle an error:** Validation problems appear in an alert; server or connection failures appear in the conversation. Check your Tailscale connection, server availability, and configured model, then send your message again.

> 💡 **Tip:** Keep each message to 1–4,000 characters after trimming surrounding whitespace. Conversation history is kept only in memory and is not saved across app launches; sending a valid new prompt from Home clears the previous conversation.

## Wellness and Apple Health

Activity opens Wellness. Tap **Connect Apple Health** (or the heart button) to request read-only access to steps, active energy, dietary water, dietary energy, protein, and workouts. The screen reads today's totals and latest workout; pull to refresh or return to the app to refresh. No HealthKit values are sent to BellAI's server or written back to Health. A dash means no readable samples, which may reflect missing data or unshared access—not a measured zero. Apple deliberately does not reveal whether read access was denied: https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data

The iOS target includes the HealthKit entitlement and a Health read-access usage description. Rebuild with a signing profile that supports HealthKit and verify the permission sheet and real data on a supported device. Other platforms show an unavailable state.

The meal-photo tile and Log meal action reuse Home's JPEG picker and `submitHomePhoto` flow: selection opens BellAI and uploads the photo to the existing food-analysis server. These actions analyze the photo; they do not write a meal to Apple Health. Camera roll load failures show an alert.
