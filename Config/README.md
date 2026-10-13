# Ollama development configuration

The Debug build includes `BellAI/Config/Secrets.xcconfig` through `Config/Debug.xcconfig`.
Keep the secrets file ignored by Git. It should define `OLLAMA_API_KEY` with your own key.
`OLLAMA_MODEL` defaults to `gemma4:31b`; override it in the secrets file if your account uses another cloud model.

Debug builds embed the key in their generated Info.plist for local testing. The raw secrets file is excluded from app resources. Release builds do not include Debug.xcconfig. Use a backend before distributing an app with a developer-owned API key.

Home submission validates trimmed text (1–4,000 characters), stores a single request in memory, opens Bell, and posts to `https://ollama.com/api/chat` with streaming disabled. Requests are not saved to disk. The returned model, completion status, and assistant text print in Xcode's console with an `[Ollama]` prefix. No assistant reply is added to the UI yet. API errors display an alert and retain the request in memory.

Run offline validation and HTTP checks with:

```sh
sh scripts/check-ollama.sh
```

These checks use a mock URLSession protocol and fake credentials; they do not contact Ollama.

Manual check: run the Debug app, enter `Hello` on Home, and tap Send. Bell should display the submitted prompt and a progress indicator. The console should print Ollama's reply (or an error if the key, model access, or quota is unavailable). Returning Home during the request must not allow a duplicate submission. Empty or whitespace-only input should show a validation error without navigating.
