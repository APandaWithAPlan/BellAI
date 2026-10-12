# BellAi Food API — for the app, the Pi and the server

Send a food photo, a typed description ("2 eggs and a slice of toast"), or both. You get
back the foods, each with a food type, an estimated weight and its nutrition, plus totals
for the meal and a one-sentence `summary` the app can show and BellAi can say out loud.

- **Base URL:** whatever address the server runs on, e.g. `http://127.0.0.1:8000` when
  testing locally
- **Interactive docs:** `<base URL>/docs`
- **Test page:** `<base URL>/`

## `POST /analyze`

Request: `multipart/form-data`. Send at least one of these fields:

| Field | Notes |
|---|---|
| `image` | Food photo: JPEG, PNG or WEBP, max 10 MB. iPhone HEIC photos must be converted to JPEG first. Resizing to about 1024 px first makes uploads faster. |
| `text` | Without a photo: what the user ate, max 500 characters, e.g. `"2 eggs and a slice of toast"`. With a photo: a note, e.g. `"half portion, fried in butter"`. |

(`note` is still accepted as an older name for `text`.)

Header: `X-API-Key: <key>` if the server was started with `FOOD_API_KEY` set.

### How fast

| Request | Path | Typical time |
|---|---|---|
| Simple text with amounts: `"2 eggs and toast"`, `"150 g rice"`, `"a banana"` | Fast path (no AI model) | Well under 1 s |
| Vague text: `"a big bowl of pasta"`, `"some fries"` | AI model | A few seconds |
| Photo | AI model | A few seconds |

`source` in the reply says which path was used, and `timing_ms` shows where the time went.
The server handles one AI-model request at a time; fast-path requests don't wait for it.
Show a loading state, and use a timeout of at least 60 seconds.

### Example (JavaScript)

```js
async function analyzeFood({ file = null, text = "" }) {
  const form = new FormData();
  if (file) form.append("image", file);  // a File / Blob, JPEG recommended
  if (text) form.append("text", text);

  const resp = await fetch(`${API_BASE}/analyze`, {
    method: "POST",
    body: form,                          // don't set Content-Type; it's added automatically
    headers: { "X-API-Key": API_KEY },   // omit if the server has no key set
  });
  if (!resp.ok) {
    const err = await resp.json().catch(() => ({}));
    throw new Error(err.detail || `Food API error ${resp.status}`);
  }
  return resp.json();
}

analyzeFood({ text: "2 eggs and a slice of toast" });
analyzeFood({ file: photo, text: "half portion" });
```

Keep the API key off the phone: the app should call the Pi (or another backend), and
the Pi calls this API with the key.

### Response `200`

Example with made-up values:

```json
{
  "type": "food",
  "status": "ok",
  "summary": "That looks like eggs and toast: about 228 calories, 15 g protein, 15 g carbs and 12 g fat.",
  "input": "text",
  "source": "quick_parse",
  "image": null,
  "text": "2 eggs and a slice of toast",
  "note": null,
  "model": null,
  "items": [
    {
      "label": "eggs",
      "type": "protein",
      "grams": 100.0,
      "confidence": 1.0,
      "usda": {
        "fdc_id": 123456,
        "fdc_description": "Egg, whole, cooked, hard-boiled",
        "usda_category": "Eggs"
      },
      "nutrition": {
        "kcal": 155, "protein_g": 12.6, "carbs_g": 1.1, "fat_g": 10.6,
        "fiber_g": null, "sugar_g": null, "sodium_mg": null
      }
    },
    {
      "label": "toast",
      "type": "grain",
      "grams": 25.0,
      "confidence": 1.0,
      "usda": { "fdc_id": 234567, "fdc_description": "Bread, white, toasted", "usda_category": "Breads" },
      "nutrition": {
        "kcal": 73, "protein_g": 2.2, "carbs_g": 13.5, "fat_g": 1.0,
        "fiber_g": null, "sugar_g": null, "sodium_mg": null
      }
    }
  ],
  "totals": {
    "kcal": 228, "protein_g": 14.8, "carbs_g": 14.6, "fat_g": 11.6,
    "fiber_g": null, "sugar_g": null, "sodium_mg": null
  },
  "unmatched_labels": [],
  "raw_model_output": null,
  "timing_ms": { "quick_parse": 180, "total": 180 },
  "created_at": "2026-10-12T19:30:00+00:00"
}
```

### Fields

| Field | Meaning |
|---|---|
| `type` | Always `"food"`, so it fits a shared BellAi reply format |
| `status` | `ok` = every food matched. `partial` = some foods had no nutrition match; they're listed in `unmatched_labels` and left out of `totals`. `no_food_found` = no food found. `unparseable_model_output` = the AI's reply was garbled; ask the user to try again. |
| `summary` | One sentence for the chat bubble, the Pi screen, and BellAi's voice |
| `input` | `"image"` or `"text"` |
| `source` | `"quick_parse"` (fast path, no AI) or `"model"` |
| `items[].label` | Cleaned food name (lowercase) |
| `items[].type` | Always one of: `fruit`, `vegetable`, `grain`, `protein`, `dairy`, `fat_oil`, `sweet`, `snack`, `beverage`, `mixed_dish`, `condiment`, `other` |
| `items[].grams` | Estimated portion weight. Let the user edit it; it's the biggest source of error. |
| `items[].confidence` | 0–1, how sure the AI is about the food name (`1.0` when the user typed an exact amount) |
| `items[].usda` | The USDA FoodData Central entry used for the nutrition (`null` if unmatched) |
| `items[].nutrition` | Nutrition for this portion. Any value can be `null` if USDA doesn't list it. |
| `totals` | Sum over the matched items |
| `timing_ms` | Milliseconds per step: `quick_parse`, `model`, `nutrition`, `total` |

Nutrition values are scaled linearly with weight. If the user changes `grams`, the app
can recalculate on its own: `new_value = value × new_grams / old_grams`.

### Errors

Every error returns JSON shaped like `{"detail": "message"}`.

| Code | When |
|---|---|
| 400 | No photo and no text; text over 500 characters; not an image, a corrupt file, or an unsupported format |
| 401 | Missing or wrong `X-API-Key` |
| 413 | Image over 10 MB |
| 503 | The model is still loading after a server restart (simple text still works during this time) |

## `GET /health`

`{"status": "ok", "model": "...", "ready": true}` — use this to check the server is up.
