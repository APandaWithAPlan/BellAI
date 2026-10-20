# BellAi Food Model

## Overview

**BellAi Food Model** identifies what you're eating and estimates its nutrition. You send it a photo of a meal, a typed description like "2 eggs and a slice of toast", or both, and it returns each food with its nutrition facts. Food is identified by Qwen2.5-VL-7B running locally on an NVIDIA GPU, and nutrition values come from USDA FoodData Central for an accurate calorie numbers.

## Getting Started

### Prerequisites

* Operating System: Windows 10 or 11. The scripts are PowerShell.
* GPU: NVIDIA with about 20 GB of free memory for the 7B model, or about 9 GB for the 3B model (`-Small`).
* Python: `3.10` to `3.12`, with about 40 GB of free disk space. The model downloads about 16 GB on first start.
* API Keys: A free USDA key from https://fdc.nal.usda.gov/api-key-signup, saved as `FDC_API_KEY`. `FOOD_API_KEY` is optional and makes every request send an `X-API-Key` header.
* Development setup: From the `Food Model` folder in PowerShell, run `powershell -ExecutionPolicy Bypass -File setup.ps1` once. It creates `.venv`, installs the packages and saves your keys. See [API.md](API.md) for the request and response format.

### How to Enable / Access

1. Run `powershell -ExecutionPolicy Bypass -File start_server.ps1`. Add `-Small` for the 3B model or `-Lan` to allow the Pi and other devices on your network.
2. Wait for **Model ready.** in the terminal. It also prints how much GPU memory is free.
3. Open http://127.0.0.1:8000 in a browser to reach the test page.

## How to Use It

1. **Analyze a photo:** On the test page, upload a JPEG, PNG or WEBP photo and click **Analyze**. Add a note like "half portion" in the text box for extra context.
2. **Analyze a description:** Leave the photo empty, type a meal such as "2 eggs and a slice of toast", and click **Analyze**. The result shows whether the fast path or the AI model answered and how long it took.
3. **Read the results:** The summary, meal totals and a table of foods appear below. Open **Raw JSON** to see exactly what the app receives.
4. **Call it from the app or Pi:** Send `POST /analyze` with an `image` field, a `text` field, or both. Check that the server is up with `GET /health`.
5. **Test accuracy:** Stop the server, activate the environment with `.venv\Scripts\activate`, and run `python evaluate.py eval_data\real_world\labels.csv`. Open the `.html` report it saves in `results`. Use `python make_labels.py` to build a labels.csv for your own photos, and use `none` for photos with no food.
6. **Handle an error:** If you see `No module named 'qwen_vl_utils'`, the environment is not active. If everything slows down and the GPU sits at 99 percent, another model is using GPU memory. Close it (check with `ollama ps`) or restart with `-Small`.

> **Tip:** If foods come back with no nutrition, the USDA lookup is failing. Check that `echo $env:FDC_API_KEY` prints your key, then run `python nutrition.py "apple"` to test the connection. Each food is cached in `cache\fdc_cache_v2.json` after its first lookup.
