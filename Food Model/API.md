# Food API

## `POST /analyze`

Send `multipart/form-data` with at least one of:

- `image`: JPEG, PNG, or WEBP, max 10 MB. Convert HEIC first.
- `text`: a meal description, or a note about the photo. Max 500 characters.

Add `X-API-Key: <key>` if the server has `FOOD_API_KEY` set.

```bash
curl -X POST http://127.0.0.1:8000/analyze -H "X-API-Key: $KEY" -F "text=2 eggs and toast"
```

The response has `status`, `summary`, `items` (each with `label`, `type`, `grams`, `nutrition`), `totals`, `source`, and `timing_ms`. Interactive docs are at `/docs`.

Errors come back as `{"detail": "..."}` with codes 400 (bad input), 401 (bad key), 413 (image too big), or 503 (model still loading).

## `GET /health`

Returns `{"status": "ok", "ready": true}` once the server is up.
