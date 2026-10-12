# Food Model — BellAi nutrition from food photos and descriptions

Takes a food photo (plus an optional note like "half portion"), or a typed description
like "2 eggs and a slice of toast", and returns cleaned-up food labels, food types,
portion sizes, and calories, protein, carbs, fat, fiber, sugar and sodium as JSON, plus
a one-sentence summary BellAi can show or say.

Simple text with amounts takes a **fast path** (`quick_parse.py`) that skips the AI model
and answers in well under a second. Vague text ("a big bowl of pasta") and photos go to
the model. The two aren't raced against each other: the fast path only answers when it
understood every part of the message, so a quick answer is never a worse answer. It works from the command line, or as a web API for the website.

**How it works**

```
website ──photo──► server.py (POST /analyze)
                        │
                        ▼
         Qwen2.5-VL-7B ──► {"name", "type", "grams", "confidence"} per food
                        │  parse + sanitize
                        ▼
         USDA FoodData Central lookup (nutrition per 100 g)
                        │  grams × value/100
                        ▼
website ◄──JSON── items + totals
```

The model only says *what* the food is and *how much*. Nutrition numbers always
come from USDA data, never from the model.

## Files

| File | What it does |
|---|---|
| `setup.ps1` | One-time setup on any Windows PC with an NVIDIA GPU |
| `start_server.ps1` | Starts the server (`-Lan` to allow other devices, `-Small` for the 3B model) |
| `server.py` | Web API the website calls (`POST /analyze`), plus a test page at `/` |
| `static/index.html` | The test page: upload a photo, see the results and the raw JSON |
| `API.md` | API reference for whoever builds the website |
| `test_api.py` | Sends a photo to the running server, the way the website will |
| `analyze_food.py` | The core logic; can also run from the command line: photo or text → JSON |
| `quick_parse.py` | Fast path for simple typed meals. Add common foods to `PORTIONS` to make more meals skip the model. |
| `nutrition.py` | Label cleanup + USDA lookup (cached in `cache/`) |
| `evaluate.py` | Scores calorie accuracy against photos with known calories |
| `requirements.txt` | Python packages |

## Quick setup on any computer

You need Windows, an NVIDIA GPU (24 GB for the 7B model; 12 GB or more works with
`-Small`), Python 3.10–3.12, Git, and about 40 GB of free disk space.

```powershell
git clone https://github.com/APandaWithAPlan/BellAI.git
cd "BellAI\Food Model"
powershell -ExecutionPolicy Bypass -File setup.ps1
powershell -ExecutionPolicy Bypass -File start_server.ps1
```

`setup.ps1` checks the GPU and Python, installs everything into `.venv`, asks for your
USDA key, creates a server API key (shown once — give it to the website person), and
offers to pre-download the model. Then open <http://127.0.0.1:8000>.

## Manual setup (what setup.ps1 does)

Run these in PowerShell. This folder gets its own Python environment so it can't
break the packages that Voice Training (Unsloth) depends on.

**1. Create and activate a virtual environment**

```powershell
cd "C:\Users\Bella Breaux\Documents\GitHub\BellAI\Food Model"
python -m venv .venv
.venv\Scripts\activate
```

If PowerShell blocks the activate script, run this once first:
`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

**2. Install PyTorch with CUDA (for the RTX 4500 Ada)**

```powershell
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu124
python -c "import torch; print(torch.cuda.is_available(), torch.cuda.get_device_name(0))"
```

This should print `True NVIDIA RTX 4500 Ada Generation`.

**3. Install the rest** (run this again whenever `requirements.txt` changes)

```powershell
pip install -r requirements.txt
```

**4. USDA API key**

Get a free key at <https://fdc.nal.usda.gov/api-key-signup>, then run:

```powershell
setx FDC_API_KEY "paste-your-key-here"
```

Open a new terminal and reactivate `.venv`. Check it works:

```powershell
python nutrition.py "white rice, cooked"
```

## Run the web API

```powershell
powershell -ExecutionPolicy Bypass -File start_server.ps1
```

You can also run `python server.py` with `.venv` active. Wait for `Model ready.`
The first run downloads the model, about 16 GB.

## Testing it, step by step

| # | Test | How | Passes if |
|---|---|---|---|
| 1 | USDA lookup | `python nutrition.py "white rice, cooked"` | Prints about 130 kcal per 100 g |
| 2 | Server is up | open <http://127.0.0.1:8000/health> | `"ready": true` |
| 3 | Full pipeline | open <http://127.0.0.1:8000>, upload a food photo | Foods, grams and totals appear; status is `ok` or `partial` |
| 4 | Same as the website | `python test_api.py photos\lunch.jpg` (second terminal) | `HTTP 200` and the JSON |
| 4b | Text, fast path | `python test_api.py --text "2 eggs and a slice of toast"` | `"source": "quick_parse"`, well under 1 s |
| 4c | Text, AI model | `python test_api.py --text "a big bowl of chicken alfredo"` | `"source": "model"` |
| 5 | Security | test page with the API key box empty (when `FOOD_API_KEY` is set) | `Error 401` |
| 6 | Bad input | upload a .txt file renamed to .jpg | `Error 400` |
| 7 | From another device | `start_server.ps1 -Lan`, then open `http://<PC's IP>:8000` on your phone on the same Wi-Fi | Same as test 3 |
| 8 | Accuracy | `python evaluate.py eval_data\labels.csv` | Mean error and % within ±20% are printed |

Tests 1–7 show that it works. Test 8 shows how *accurate* it is.

## Lock it with a key

Before letting anyone else reach the server, set a key. Make up a long random string:

```powershell
setx FOOD_API_KEY "some-long-random-string"
```

Open a new terminal. From then on, every request needs the header
`X-API-Key: some-long-random-string`. `test_api.py` sends it automatically.

## Letting the website reach it

By default the server only accepts connections from this computer (`127.0.0.1`).

- **Groupmate's site on this same computer:** nothing else to do. Add the site's
  address to `ALLOWED_ORIGINS` if it isn't `localhost:3000` or `localhost:5173`, e.g.
  `setx ALLOWED_ORIGINS "http://localhost:3000,http://localhost:8080"`.
- **Same Wi-Fi or LAN:** run `$env:HOST="0.0.0.0"; python server.py` and allow Python
  through Windows Firewall. The site then uses `http://<this PC's IP>:8000`.
- **Website hosted on the internet:** your PC needs a public HTTPS address. A tunnel
  such as Cloudflare Tunnel or ngrok can provide one. Always set `FOOD_API_KEY` first,
  and add the site's real origin to `ALLOWED_ORIGINS`.

## Command line (no server)

```powershell
python analyze_food.py photos\lunch.jpg --note "fried in butter, I ate half"
python analyze_food.py --text "2 eggs and a slice of toast"
python quick_parse.py "150 g rice and 6 oz chicken breast"     # just the fast-path parse
```

This prints the same JSON and saves it to `results\lunch.json`. The 7B model uses about
17–20 GB of your 24 GB of VRAM. If you run out of memory, use the 3B model:
`--model Qwen/Qwen2.5-VL-3B-Instruct`, or set `FOOD_MODEL` to that for the server.

## Measure accuracy

Make a CSV with columns `image,true_kcal` for photos where you know the real calories.
The overhead photos from Nutrition5k work well, and so do your own meals if you weigh them.

```powershell
python evaluate.py eval_data\labels.csv --limit 50
```

It reports the mean calorie error and the percentage of photos within ±20%.

## Fixing bad USDA matches

Matches are cached in `cache\fdc_cache_v2.json`. If a food keeps matching the wrong
entry, delete its line from that file and it will be looked up again. The old
`cache\fdc_cache.json` from the first version isn't used anymore and can be deleted.

## Next step: fine-tuning

Get a baseline with `evaluate.py` first. If accuracy is short of the target, fine-tune
a LoRA adapter on Nutrition5k (photo → foods + grams), save it to `food_lora/`, and run
with `--lora food_lora` (or `FOOD_LORA=food_lora` for the server).
