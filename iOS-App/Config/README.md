# Server development configuration

## Briefing weather

Agenda uses Core Location for a one-time approximate location, MapKit for the city name, and Apple's WeatherKit for the weather. There is no API key to set up. Apple recognizes the app by its signature, so the app needs the **WeatherKit** capability, which is already in `BellAI/BellAI.entitlements`.

WeatherKit needs a paid Apple Developer Program membership. In Xcode, check that the BellAI target's Signing & Capabilities tab lists WeatherKit and that signing succeeds. Registering it for the App ID can take up to 30 minutes to take effect. If it hasn't, or the account isn't a paid one, the card says Apple Weather isn't enabled for this build. Weather does not work in an unsigned or ad-hoc signed build, like the checks and the simulator builds used for testing the rest of the app.

The card shows the current temperature, the condition, an SF Symbol from WeatherKit, and today's high and low from the daily forecast. Temperatures follow device units. Apple requires its Apple Weather mark and a link to its legal page next to the weather, and they are shown under the card. WeatherKit includes 500,000 calls a month, and a refresh makes one weather call.

Pull down or tap Try again to refresh. In Simulator, select a simulated location; on a device, grant location access. Check city, condition icon, units, denied location permission, and offline behavior. The console logs only error domains and codes.

Run offline checks with `sh scripts/check-weather.sh`. They cover the screen's states and error messages, not WeatherKit itself, which can't be called without a signed app.

The app connects to the OpenAI-compatible API at `http://ai-server:11434/v1/` without an API key or Authorization header. The device running BellAI must be connected to Tailscale with access to `ai-server` on port 11434.

`OLLAMA_MODEL` defaults to `qwen3.5:4b-q4_K_M`; it must match a model available on the server. Debug builds can override it in the ignored `BellAI/Config/Secrets.xcconfig` included by `Config/Debug.xcconfig`. No API key is required.

## Spoken replies

With the speaker on, the app sends the request over a WebSocket to the voice server (`ws://ai-server:8000/ws`). Text streams in as Ollama writes it, and each sentence comes back as a wav clip that `SpeechPlayer` plays in order. Change the host with `VOICE_SERVER_HOST` in `Config/Debug.xcconfig`. If the voice server can't be reached, the app falls back to the plain HTTP request and the reply is text only. Turning the speaker off stops any audio that's playing.

## Voice input

The microphone records 16 kHz mono audio on the phone and posts it as a wav file to `http://ai-server:8000/transcribe` on the voice server, which runs Whisper on MLX and answers `{"text": "..."}`. It uses the same address as spoken replies (`VOICE_SERVER_HOST`, or the address set in Settings > Server options). Only the microphone permission is needed, set by `INFOPLIST_KEY_NSMicrophoneUsageDescription` in the project; the Speech Recognition permission is not used.

## Mail, recommendations and meals

The Mail screen and the Recommendations card use the same voice server address: `GET /mail`, `GET` and `POST /drafts` and `POST /drafts/<id>/send` and `/discard` are passed on to the mail watcher, and `POST /insights` to the Insights server. Meals logged from a photo are kept in the app (`MealJournal`, 14 days) and food and workout preferences in `UserDefaults` (`FoodPreferencesStore`), so nothing about you is stored on the server for these. The project includes the camera, microphone, Health read and Health update usage descriptions, which iOS requires or the app is stopped when it asks for the permission.

The app permits HTTP connections to local hostnames through `NSAllowsLocalNetworking` and includes a local-network permission description.

Home submission validates trimmed text (1–4,000 characters), starts a fresh conversation in memory, opens BellAI, and posts to `http://ai-server:11434/v1/chat/completions` with streaming disabled. Requests are not saved to disk. The returned model, completion status, and assistant text print in Xcode's console with an `[Ollama]` prefix. The reply or API error appears below the submitted prompt in BellAI. While the request runs, the avatar’s outer ring gently pulses; it stops on success, failure, or cancellation and respects Reduce Motion. Validation errors display an alert before navigation.

Run offline validation and HTTP checks with:

```sh
sh scripts/check-ollama.sh
```

These checks use a mock URLSession protocol; they verify the endpoint, absence of authentication, request body, response decoding, and error handling without contacting the server.

Manual check: run the Debug app, enter `Hello` on Home, and tap Send. BellAI should display the submitted prompt and a pulsing avatar ring. The console should print the server's reply (or an error if the server, model, or quota is unavailable). Returning Home during the request must not allow a duplicate submission. Empty or whitespace-only input should show a validation error without navigating.

The BellAI keyboard button opens a follow-up input. Send appends the user message, includes previous user/assistant messages in the API request, and appends the reply or error. Error notices stay in the UI but are excluded from API history. Switching tabs preserves the current conversation; a valid Home submission starts a new session and clears the previous messages. History is not persisted across app launches. Invalid submissions and attempts while a request is pending do not clear the session.
