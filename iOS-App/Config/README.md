# Ollama development configuration

## Briefing weather

Agenda uses Core Location for a one-time approximate location and MapKit for the city name. Weather comes from OpenWeather's Current Weather and 5-day/3-hour Forecast endpoints. No WeatherKit entitlement or paid Apple Developer membership is required for weather access.

Create an OpenWeather account and get an active API key with access to those endpoints. Add this line to `BellAI/Config/Secrets.xcconfig` (ignored by Git; used by Debug and Release):

```xcconfig
OPENWEATHER_API_KEY = YOUR_OPENWEATHER_API_KEY
```

`Config/Secrets.xcconfig.example` is a template. Rebuild after setting the key. Missing or inactive keys show a configuration/access error. The key is bundled into the app for local development; for distribution, proxy requests through your backend to keep the provider credential off client devices. Never commit the populated secrets file.

The card shows current temperature, condition, and an SF Symbol mapped from OpenWeather's condition code and day/night icon. Temperatures follow device units. The lower row is labeled **Rest of today (est.)**: it uses current temperature and remaining 3-hour forecast temperatures on the location's local calendar day. It is not a full-day high/low; earlier temperatures are unavailable from this endpoint. If there are no remaining samples, the range shows dashes. OpenWeather's current `temp_min`/`temp_max` fields are not daily extremes and are not used.

Pull down or tap Try again to refresh. Each refresh makes two weather requests. In Simulator, select a simulated location; on a device, grant location access. Check city, condition icon, units, denied permission, missing/invalid key, and offline behavior. The console logs only error domains/codes, never request URLs or credentials.

Run offline checks with `sh scripts/check-weather.sh`.

The app connects to the OpenAI-compatible API at `http://ai-server:11434/v1/` without an API key or Authorization header. The device running BellAI must be connected to Tailscale with access to `ai-server` on port 11434.

`OLLAMA_MODEL` defaults to `qwen3.5:4b-q4_K_M`; it must match a model available on the server. Debug builds can override it in the ignored `BellAI/Config/Secrets.xcconfig` included by `Config/Debug.xcconfig`. No API key is required.

## Spoken replies

With the speaker on, the app sends the request over a WebSocket to the voice server (`ws://ai-server:8000/ws`). Text streams in as Ollama writes it, and each sentence comes back as a wav clip that `SpeechPlayer` plays in order. Change the host with `VOICE_SERVER_HOST` in `Config/Debug.xcconfig`. If the voice server can't be reached, the app falls back to the plain HTTP request and the reply is text only. Turning the speaker off stops any audio that's playing.

The app permits HTTP connections to local hostnames through `NSAllowsLocalNetworking` and includes a local-network permission description.

Home submission validates trimmed text (1–4,000 characters), starts a fresh conversation in memory, opens BellAI, and posts to `http://ai-server:11434/v1/chat/completions` with streaming disabled. Requests are not saved to disk. The returned model, completion status, and assistant text print in Xcode's console with an `[Ollama]` prefix. The reply or API error appears below the submitted prompt in BellAI. While the request runs, the avatar’s outer ring gently pulses; it stops on success, failure, or cancellation and respects Reduce Motion. Validation errors display an alert before navigation.

Run offline validation and HTTP checks with:

```sh
sh scripts/check-ollama.sh
```

These checks use a mock URLSession protocol; they verify the endpoint, absence of authentication, request body, response decoding, and error handling without contacting the server.

Manual check: run the Debug app, enter `Hello` on Home, and tap Send. BellAI should display the submitted prompt and a pulsing avatar ring. The console should print the server's reply (or an error if the server, model, or quota is unavailable). Returning Home during the request must not allow a duplicate submission. Empty or whitespace-only input should show a validation error without navigating.

The BellAI keyboard button opens a follow-up input. Send appends the user message, includes previous user/assistant messages in the API request, and appends the reply or error. Error notices stay in the UI but are excluded from API history. Switching tabs preserves the current conversation; a valid Home submission starts a new session and clears the previous messages. History is not persisted across app launches. Invalid submissions and attempts while a request is pending do not clear the session.
