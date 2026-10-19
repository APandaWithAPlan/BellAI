# Ollama development configuration

The app connects to the OpenAI-compatible API at `http://ai-server:11434/v1/` without an API key or Authorization header. The device running BellAI must be connected to Tailscale with access to `ai-server` on port 11434.

`OLLAMA_MODEL` defaults to `qwen3:8b`; it must match a model available on the server. Debug builds can override it in the ignored `BellAI/Config/Secrets.xcconfig` included by `Config/Debug.xcconfig`. No API key is required.

The app permits HTTP connections to local hostnames through `NSAllowsLocalNetworking` and includes a local-network permission description.

Home submission validates trimmed text (1–4,000 characters), starts a fresh conversation in memory, opens Bell, and posts to `http://ai-server:11434/v1/chat/completions` with streaming disabled. Requests are not saved to disk. The returned model, completion status, and assistant text print in Xcode's console with an `[Ollama]` prefix. The reply or API error appears below the submitted prompt in Bell. While the request runs, the avatar’s outer ring gently pulses; it stops on success, failure, or cancellation and respects Reduce Motion. Validation errors display an alert before navigation.

Run offline validation and HTTP checks with:

```sh
sh scripts/check-ollama.sh
```

These checks use a mock URLSession protocol; they verify the endpoint, absence of authentication, request body, response decoding, and error handling without contacting the server.

Manual check: run the Debug app, enter `Hello` on Home, and tap Send. Bell should display the submitted prompt and a pulsing avatar ring. The console should print the server's reply (or an error if the server, model, or quota is unavailable). Returning Home during the request must not allow a duplicate submission. Empty or whitespace-only input should show a validation error without navigating.

The Bell keyboard button opens a follow-up input. Send appends the user message, includes previous user/assistant messages in the API request, and appends the reply or error. Error notices stay in the UI but are excluded from API history. Switching tabs preserves the current conversation; a valid Home submission starts a new session and clears the previous messages. History is not persisted across app launches. Invalid submissions and attempts while a request is pending do not clear the session.
