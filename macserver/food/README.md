# BellAi Food Server (Mac)

## Overview

**BellAi Food Server** turns a food photo, a typed description, or both into foods, portions and nutrition. Qwen2.5-VL 7B (4-bit) runs on MLX and names the foods and guesses their weight, then USDA FoodData Central supplies the nutrition. Simple text like "2 eggs and toast" skips the model. It works the same as `Food Model/server.py`, with MLX instead of CUDA.

It only accepts connections from this Mac. The app reaches it through the [voice server](../voice/README.md), which passes `/analyze` on, so the app doesn't need to know about this port.

## Getting Started

### Prerequisites

* Hardware: A Mac with Apple Silicon. It was tested on an M5 Pro with 24 GB.
* Software: `uv` (`brew install uv`). The script installs Python 3.11 and everything else into `.venv`.
* Disk: About 6 GB for the model, downloaded to `~/.cache/huggingface` on the first start.
* USDA key: A free key from https://fdc.nal.usda.gov/api-key-signup, set as `FDC_API_KEY` before starting. Without it, lookups use `DEMO_KEY`, which allows only a few requests an hour.

### How to Enable / Access

1. Run `./start_food.sh` in this folder. The first start downloads the model and takes a few minutes.
2. Wait for `Model ready.` in the log.
3. Open http://127.0.0.1:8002/health. It should show `"ready": true`.

## How to Use It

1. **Analyze a photo or text:** Send `multipart/form-data` to `POST /analyze` with `image` (JPEG, PNG or WEBP, max 10 MB), `text` (a meal description or a note about the photo, max 500 characters), or both. For example `curl -X POST http://127.0.0.1:8002/analyze -F "text=2 eggs and toast"`.
2. **Read the result:** The response has `status`, `summary`, `items` (each with `label`, `type`, `grams`, `nutrition`), `totals`, `source` and `timing_ms`. Errors come back as `{"detail": "..."}` with code 400 (bad input), 413 (image too big) or 503 (model still loading).
3. **Try it in a browser:** Open http://127.0.0.1:8002 for a page where you can upload a photo.
4. **Use a different model:** Set `FOOD_MODEL` to another MLX model, for example `mlx-community/Qwen2.5-VL-3B-Instruct-4bit` for less memory, before `./start_food.sh`. Set `HOST` or `PORT` to change where it listens, and `FOOD_URL` on the voice server if you change the port.
5. **Handle an error:** If `/analyze` through the voice server says `The food server isn't running`, start this one. If lookups fail or run out, check `FDC_API_KEY`.

> 💡 **Tip:** The Mac's 24 GB is shared with the chat model and the voice model. The 7B model uses about 6 GB, so if memory gets tight, switch to the 3B model.
