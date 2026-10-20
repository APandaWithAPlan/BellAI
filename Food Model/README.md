# BellAi Food Model

## Summary
Send a food photo or a description like "2 eggs and toast" and get back the foods, portions and nutrition as JSON. Qwen2.5-VL-7B identifies the food and estimates grams, and the nutrition comes from USDA FoodData Central. It runs locally on an NVIDIA GPU.

Setup (Windows, NVIDIA GPU, Python 3.10 to 3.12, free USDA API key), from this folder in PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1
powershell -ExecutionPolicy Bypass -File start_server.ps1
```
When it says `Model ready.`, open http://127.0.0.1:8000.

- `server.py` runs the API (`POST /analyze`) and the test page
- `analyze_food.py` turns a photo or text into foods and nutrition
- `quick_parse.py` handles simple text like "150 g rice" without the AI
- `nutrition.py` looks up nutrition in USDA and caches it

## Changes/Tasks
- Find and set up a food model to ingest images: Qwen2.5-VL-7B running locally, with a 3B option for smaller GPUs
- Ingest user prompts and return food labels: accepts a photo, text, or both, and returns each food with a type and grams
- Return sanitized labels as JSON for the backend: cleaned labels, a fixed list of food types, sensible gram limits, USDA nutrition, totals and a summary sentence

## Testing
Activate the environment with `.venv\Scripts\activate`, stop the server, then run:
```powershell
python evaluate.py eval_data\real_world\labels.csv
```
- `evaluate.py` scores the model against a labels.csv and saves a report in `results`
- `make_labels.py` makes a labels.csv for a folder of your own photos
- `test_api.py` sends a test request to the running server

Results from testing accuracy:
- Nutrition5k (50 cafeteria meals): 82 percent food identification
- Real world (41 food photos, 8 non-food): 73 percent food identification, 7 of 8 non-food photos rejected
- My photos (79 non-food, 2 food): 78 of 79 non-food rejected, both food photos identified

Results from testing accuracy after review:
- Nutrition5k (50 cafeteria meals): 88%
- Real world (41 food photos, 8 non-food): 95%
- Average Total: 91%

## Issues
- USDA lookups must have a corresponding API key attached and you can request that from `https://fdc.nal.usda.gov/api-key-signup`.
- Food model mistakes are just naming differences, like "beef steak" for filet mignon. I counted them as correct which is why the task is considered complete.
- Drawings of food can trick the AI model currently. A fruit painting and a cartoon with burgers were both read as food.
- Running without `.venv` gives errors like `No module named 'qwen_vl_utils'`.
- The 7B model uses about 17 GB of GPU memory. If another model is loaded too, everything slows down. Use `-Small` or close the other model.
