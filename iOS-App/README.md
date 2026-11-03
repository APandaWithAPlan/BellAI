# BellAI iOS App

## Overview

**BellAI** is an iOS assistant designed to extend help beyond the home. You can type or speak to it, send it a photo of a meal, read the email it has sorted for you, and get food and workout suggestions based on what you ate. Replies can be read aloud in the BellAI voice.

The app talks to the Mac server in [`macserver`](../macserver/README.md), so the chat model, the voice, the food analysis and your saved data all stay on your own machines. The only outside service is Apple's, for the weather.

The Home screen shows live cards for Plan (your tasks) and Mail, and previews Lights, Climate and Security with static sample values; those three do not control devices yet. The Activity screen shows Apple Health totals, meal logging and recommendations, and Settings holds your profile and the server address.

## Getting Started

### Prerequisites

* Minimum App Version: `v1.0` (current development version, build `1`).
* Minimum iOS Version: `17.0`.
* Account Tier / Permissions needed: No BellAI account is needed. The device must be connected to your Tailscale network with access to `ai-server` on ports `11434`, `8000` and `8001`; allow local-network access if prompted. The app also asks for the microphone (voice input), the camera (meal photos), Apple Health (reading and saving nutrition) and your location (weather) the first time each is used.
* Signing: The target uses the HealthKit and WeatherKit capabilities (`BellAI/BellAI.entitlements`). WeatherKit needs a paid Apple Developer Program membership, see [weather](Config/README.md).
* Server: The Mac server in [`macserver`](../macserver/README.md) running as `ai-server`. It answers like Ollama on port `11434` (the model name in the app is ignored), runs the voice server on `8000` for spoken replies, voice input, food photos, recommendations and mail, and the data server on `8001` for tasks.
* Development setup: Open `BellAI.xcodeproj` in Xcode with support for the configured iOS target, select the BellAI app and a compatible device or simulator, then build and run. See [Ollama development configuration](Config/README.md) for model configuration and offline checks.

### How to Enable / Access

1. Open the app. The **Home** tab opens. Set the name BellAI greets you with from Settings > Profile.
2. Tap **What can I help with?** and type your first message, or tap the microphone and speak. No feature toggle is required.
3. Tap the **Send** arrow or the keyboard's **Send** key. The app opens **BellAI**, displays your message, and shows **Thinking…** while waiting for a reply.

## How to Use It

1. **Start a conversation:** From **Home**, enter a prompt such as “Help me plan my day” and send it.
2. **Read the response:** Wait for the assistant's reply beneath your message. Only one request can run at a time, and with the speaker on, the reply streams in as it is written and each sentence is spoken as soon as it is ready; with the speaker off (or if the voice server is unreachable) the reply appears when the server finishes.
3. **Ask a follow-up:** On the **BellAI** screen, tap the **keyboard** button, type another message, and tap the **Send** arrow or the keyboard's **Send** key. Previous user and assistant messages are included for context.
4. **Use your voice:** Tap the microphone on **Home** or **BellAI**, speak, and tap the stop button (or pause) to send. See [Voice input](#voice-input).
5. **Check your mail:** Tap the **Mail** row on **Home**. See [Mail](#mail).
6. **Log a meal and get suggestions:** Open **Activity**, send a photo of a meal, then tap **Get recommendations**. See [Meal photos](#meal-photos-and-apple-health) and [Recommendations](#recommendations).
7. **Move between screens:** Use the bottom navigation to switch tabs. Returning to **BellAI** preserves the current conversation while the app remains running; the close button returns you to **Home**.
8. **Start fresh:** Submit a new prompt from **Home** to replace the current conversation with a new session.
9. **Handle an error:** Validation problems appear in an alert; server or connection failures appear in the conversation. Check your Tailscale connection, server availability, and configured model, then send your message again.

> 💡 **Tip:** Keep each message to 1–4,000 characters after trimming surrounding whitespace. Conversation history is kept only in memory and is not saved across app launches; sending a valid new prompt from Home clears the previous conversation.

## Voice input

The microphone buttons on Home and BellAI record what you say on the phone and send it to the Mac, where Whisper (running on MLX) turns it into text. Nothing goes to Apple, and no Speech Recognition permission is needed, only the microphone.

* **Start:** Tap the microphone and grant the microphone permission the first time. The subtitle shows **Listening... tap to send**.
* **Finish:** Recording ends when you pause for about a second and a half, or when you tap the stop button, which sends what you have said so far. It also ends after 60 seconds, or after 8 seconds if nothing is said.
* **Transcribe:** The subtitle shows **Transcribing...** while the Mac works, which takes well under a second for a sentence. The text is then sent through the same chat flow as typed text. If nothing was heard, an alert says so.
* **Cancel:** Close the BellAI screen, switch tabs or tap the stop button while it says **Transcribing...** to throw the recording away. Recording also stops when the app goes to the background, when a call interrupts it, and before a request is sent.

> ⚠️ **Warning:** The voice server must be reachable, because the recording is transcribed there. If it is not, the app shows the connection error. The iOS Simulator's microphone can hang, so test voice input on a device.

## Mail

The **Mail** row on Home opens the emails the Mac's [mail watcher](../macserver/mail/README.md) has read: who they are from, a one sentence summary, what you need to do and any deadline, with the important ones marked. The row shows how many are important, or how many replies are waiting for your approval. Pull down to refresh. The list also refreshes when the app opens.

* **Read:** Tap an email to see the notes. The app only gets the sender, subject, date and the model's notes, never the email itself.
* **Reply:** Say what the reply should say, like “yes, Thursday works”, and tap **Write reply**. BellAI writes it on the Mac, which can take up to about a minute because it reads the original first.
* **New email:** Tap the pencil, enter an address and what to say, and tap **Write email**.
* **Approve:** The review screen shows **To**, **Subject** and the full text. An email is only sent when you press **Send**, and **Discard** throws it away. A draft can be sent once, so it cannot go out twice.
* **From Discord:** Drafts written from Discord wait under **Waiting for your approval**, and the other way round.
* **In chat:** BellAI knows about your important emails when you chat, the same way it knows your open tasks.

> ⚠️ **Warning:** An email can contain text written to trick an AI. Read the address and the text of every draft before you press Send, and don't rely on the summaries for anything where a mistake would cost you.

## Meal photos and Apple Health

Choose a photo with the **Log meal** button on Activity, the photo button on Home or the photo button next to the keyboard on BellAI. On a device with a camera, the photo buttons offer **Take Photo** or **Choose from Library** (the camera asks for permission the first time); without one they open the library. What you type before choosing the photo goes along as a note.

The result opens in a sheet over the screen you are on, not in the chat, and it is not read aloud. It shows the calories and protein.

* **Log meal:** Saves the calories and protein to Apple Health as they are. Apple Health asks for permission to save nutrition the first time.
* **Edit:** Lets you correct either number. Saving the correction logs the meal automatically.
* **Once only:** A logged meal can't be edited or logged again, so it can't be counted twice. To fix it afterwards, change it in the Health app.
* **Journal:** Each logged meal is also kept on the phone with everything the food model found (calories, protein, carbs, fat, fiber, sugar and sodium), because Apple Health only holds calories and protein. [Recommendations](#recommendations) are worked out from it. Meals are kept for 14 days.

If the model finds no food, the sheet says so and nothing is logged. If Apple Health is denied, the error says to allow it in the Health app, your edit stays, and **Log meal** can be tried again.

## Recommendations

The **Recommendations** card on Activity gives food and workout ideas for today. **Get recommendations** sends today's journal meals and your preferences to the Insights server on the Mac. It answers with a short summary of the biggest problem with your day (like low protein or too much sodium), a few foods to eat with their calories and protein, and a workout or two. It takes a few seconds.

* **Preferences:** The slider button opens calorie, protein and sodium targets, diet, goal, allergies, foods you dislike, fitness level and injuries. Leave a target empty to use the usual (2,000 calories, about 100 g of protein, 2,300 mg of sodium). Separate allergies, dislikes and injuries with commas. They are kept on the phone.
* **Limits:** Anything with an allergy or a disliked food, against your diet, over your calorie budget, or that would strain an injury is removed on the server before it comes back. If the chat model is down, safe default ideas are shown instead.
* **Saving:** Changing preferences clears the ideas on screen, because they no longer fit. Tap **Refresh** for new ones.
* **No meals:** With nothing logged, it asks you to log a meal and gives general ideas.
* **Sample days:** A debug build also has **Try a sample day** (low protein, high sodium or on track) to see it work without logging meals. It doesn't touch your journal.

> 💡 **Tip:** Only meals logged from a photo in this app are used. Meals logged in other apps, or typed in Apple Health, are not counted.

## Wellness and Apple Health

Activity opens Wellness. Tap **Connect Apple Health** (or the heart button) to request read-only access to steps, active energy, dietary water, dietary energy, protein, and workouts. The screen reads today's totals and latest workout; pull to refresh or return to the app to refresh. Values read from Apple Health stay on the phone. A dash means no readable samples, which may reflect missing data or unshared access, not a measured zero. Apple deliberately does not reveal whether read access was denied: https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data

The iOS target includes the HealthKit entitlement and Health usage descriptions for reading and for saving nutrition. Rebuild with a signing profile that supports HealthKit and verify the permission sheets and real data on a supported device. Other platforms show an unavailable state. The Nutrition card reads back the totals, including meals logged from a photo.

## Weather

The Agenda section on Home shows the current temperature, condition and today's high and low for your city, using Apple's WeatherKit. The app asks for your approximate location once, only while Agenda is open. There is no API key to set up, but WeatherKit needs a paid Apple Developer Program membership and the WeatherKit capability on the app, and the Apple Weather mark and a link to its legal page are shown under the card. See [Briefing weather](Config/README.md) for setup and troubleshooting.

## Server options

Settings > Server options sets where the app finds the Mac. The default, `ai-server`, is the Mac's name on Tailscale. To use NetBird or a local network instead, enter the Mac's IP address there (and change a port only if you changed it on the Mac), then tap **Save and test**. It shows whether the chat, voice and tasks servers answer. **Reset** goes back to the defaults. The settings are kept on the phone and apply right away, and tasks and mail are loaded again from the new server.

iOS only allows plain HTTP to IP addresses, short names (like `ai-server`) and `.local` names, so a longer name such as `mac.netbird.cloud` is blocked. Use the IP address for those.

## Login

There is no login. Being connected to your Tailscale network is the login, and the data server only answers devices on it. The name BellAI greets you with is kept on the phone (`ProfileViewModel`), and tasks are kept on the Mac (`HTTPUserDataService`, set by `DATA_SERVER_HOST` in `Config/Debug.xcconfig`, `ai-server:8001` if it is not set).

## App icon

The icon is `BellAi.png` in this folder, set up as the 1024 px `AppIcon` in `BellAI/Assets.xcassets/AppIcon.appiconset` with the transparency removed, because the App Store rejects icons that have any. Replace the image in that folder to change it. If the old icon still shows on a simulator, delete the app and run it again.

## Offline checks

Run `sh scripts/check-ollama.sh` for the chat, voice input, meal, mail, recommendation and settings checks, and `sh scripts/check-weather.sh` for the weather screen. They use mock responses and need no server, key or device.
