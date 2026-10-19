# BellAI Food Model

Send a food photo or a description like "2 eggs and toast" and get back foods, portions, and nutrition. Qwen2.5-VL identifies the food, and the numbers come from USDA FoodData Central.

## Setup

Needs Windows, Python 3.10 to 3.12, an NVIDIA GPU (24 GB for 7B, 12 GB for 3B), and a free [USDA API key](https://fdc.nal.usda.gov/api-key-signup).

```powershell
cd "BellAI\Food Model"
powershell -ExecutionPolicy Bypass -File setup.ps1
powershell -ExecutionPolicy Bypass -File start_server.ps1
```

Open http://127.0.0.1:8000 once it says `Model ready.` Add `-Small` for the 3B model or `-Lan` to allow other devices.

Optional environment variables: `FDC_API_KEY`, `FOOD_API_KEY`, `ALLOWED_ORIGINS`, `FOOD_MODEL`, `FOOD_LORA`, `HOST`, `PORT`.

If it gets really slow, the GPU is out of memory. Close other models (`ollama ps`) or use `-Small`.

## Files

| File | What it does |
|---|---|
| `server.py` | The API (`/analyze`, `/health`) and test page. |
| `analyze_food.py` | Main logic: photo or text to foods to nutrition. Also works from the command line. |
| `quick_parse.py` | Handles simple text like "150 g rice" without the AI. |
| `nutrition.py` | USDA lookup and nutrition math. |
| `test_api.py` | Sends a test request to the server. |
| `get_eval_data.py` | Downloads Nutrition5k test photos. |
| `evaluate.py` | Scores accuracy against `labels.csv`. |

API details are in [API.md](API.md).
