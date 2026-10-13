# BellAi Food Model

Tell BellAi what you ate by sending a **photo**, a **typed description**, or both. You get
back JSON with each food, its type, an estimated portion in grams, and calories,
protein, carbs, fat, fiber, sugar and sodium. There are totals for the meal and a
one-sentence summary BellAi can show on screen or say out loud.

```
photo / "2 eggs and a slice of toast"
        │
        ▼
  server.py  POST /analyze
        │
        ├── simple text with amounts ──► fast path (quick_parse.py, no AI)  ── < 1 s
        └── photo or vague text ───────► Qwen2.5-VL-7B AI model             ── a few s
                    │
                    ▼   foods + grams
        USDA FoodData Central ──► nutrition = grams × USDA values
                    │
                    ▼
        JSON: items, totals, summary
```

The AI only decides **what** the food is and **how much** there is. Every nutrition
number comes from the USDA database, never from the AI.

**Contents:**
[Requirements](#requirements) ·
[Setup](#setup) ·
[Start the server](#start-the-server) ·
[Using it](#using-it) ·
[Connecting BellAi to it](#connecting-bellai-to-it) ·
[Testing](#testing) ·
[Settings](#settings) ·
[Troubleshooting](#troubleshooting) ·
[Files](#files) ·
[Accuracy and next steps](#accuracy-and-next-steps)

---

## Requirements

| | |
|---|---|
| **OS** | Windows 10/11 (the scripts are PowerShell; the Python code also runs on Linux) |
| **GPU** | NVIDIA with **24 GB** of memory for the 7B model, or **12 GB+** for the smaller 3B model |
| **Python** | 3.10, 3.11 or 3.12 |
| **Disk** | About 40 GB free (the model is about 16 GB) |
| **Other** | Git, an internet connection, and a free [USDA API key](https://fdc.nal.usda.gov/api-key-signup) |

---

## Setup

Do this once per computer.

### Quick setup (recommended)

```powershell
git clone https://github.com/APandaWithAPlan/BellAI.git
cd "BellAI\Food Model"
powershell -ExecutionPolicy Bypass -File setup.ps1
```

`setup.ps1` does all of this:
1. Checks the GPU and Python version.
2. Creates a separate Python environment in `.venv`, so it can't break other BellAi projects.
3. Installs PyTorch (with GPU support) and the other packages.
4. Asks for your USDA API key and saves it.
5. Creates a server API key and shows it once. Share it privately with whoever connects to the server.
6. Offers to download the AI model now, so the first start is quick.

You can run it again at any time; it skips steps that are already done.

### Manual setup

If you'd rather do it by hand, run this in PowerShell from the `Food Model` folder:

```powershell
python -m venv .venv
.venv\Scripts\activate
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu124
pip install -r requirements.txt
setx FDC_API_KEY "your-usda-key"
```

- If PowerShell refuses to run `activate`, run this once:
  `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`
- `setx` only takes effect in **new** terminals. Open a new one and run
  `.venv\Scripts\activate` again.

Check that the GPU and the USDA lookup both work:

```powershell
python -c "import torch; print(torch.cuda.is_available(), torch.cuda.get_device_name(0))"
python nutrition.py "white rice, cooked"
```

The first should print `True` and your GPU's name. The second should show cooked rice
at about 130 kcal per 100 g.

---

## Start the server

```powershell
powershell -ExecutionPolicy Bypass -File start_server.ps1
```

1. Watch for the line `GPU memory free: XX of 24.0 GB`. If a **WARNING** box appears,
   something else is using the GPU; see [Troubleshooting](#troubleshooting).
2. Wait for `Model ready.` The first time, this includes downloading the model.
3. Open **<http://127.0.0.1:8000>**.

| Option | What it does |
|---|---|
| `start_server.ps1 -Small` | Uses the 3B model: about 8 GB of GPU memory instead of 17, a bit less accurate. Use it when another model, such as BellAi's voice, is also running. |
| `start_server.ps1 -Lan` | Lets other devices on the same network connect, and prints the address to use |
| `start_server.ps1 -Port 9000` | Uses a different port |

To stop the server, press **Ctrl+C**.

You can also run `python server.py` directly, with `.venv` activated.

---

## Using it

### Test page

Open <http://127.0.0.1:8000>. Upload a photo, type a meal, or do both, then click
**Analyze**. The text becomes a note when there's a photo (for example "half portion").
The page shows the summary, the totals, a table of foods, which path was used (fast path
or AI model), the time taken, and the raw JSON.

### From code (what the app and the Pi do)

`POST /analyze` with a `multipart/form-data` body:

| Field | |
|---|---|
| `image` | Food photo: JPEG, PNG or WEBP, up to 10 MB |
| `text` | A meal description (`"2 eggs and toast"`), or a note for the photo (`"half portion"`) |

Send at least one of them. Add the header `X-API-Key: <key>` if the server has a key set.

```powershell
python test_api.py --text "2 eggs and a slice of toast"
python test_api.py photos\lunch.jpg --text "half portion"
```

```bash
curl -X POST http://127.0.0.1:8000/analyze -H "X-API-Key: $KEY" -F "text=a banana and a cup of milk"
curl -X POST http://127.0.0.1:8000/analyze -H "X-API-Key: $KEY" -F "image=@lunch.jpg"
```

Short version of the reply (full reference in **[API.md](API.md)**):

```json
{
  "type": "food",
  "status": "ok",
  "summary": "That looks like eggs and toast: about 228 calories, 15 g protein, 15 g carbs and 12 g fat.",
  "source": "quick_parse",
  "items": [ { "label": "eggs", "type": "protein", "grams": 100.0, "nutrition": { "kcal": 155, "...": "..." } } ],
  "totals": { "kcal": 228, "protein_g": 14.8, "carbs_g": 14.6, "fat_g": 11.6 },
  "timing_ms": { "total": 180 }
}
```

### Command line (no server)

```powershell
python analyze_food.py photos\lunch.jpg --note "I ate half"
python analyze_food.py --text "a big bowl of chicken alfredo"
python quick_parse.py "150 g rice and 6 oz chicken breast"     # fast-path check only, no AI
```

The JSON is printed and also saved to `results\`.

---

## Connecting BellAi to it

```
iOS app ─┐
         ├──► Pi gateway ──X-API-Key──► Food server  POST /analyze
Pi mic  ─┘                                   │
                                             ▼
                     summary → chat bubble, Pi screen, BellAi's voice
                     items / totals → nutrition card, then saved as a meal
```

- **Keep the API key off the phone.** The app talks to the Pi, and only the Pi calls the food server with the key.
- **Send JPEG photos about 1024 px wide.** iPhones save HEIC by default, which the server won't accept, so convert first.
- **Let users fix the grams before saving a meal.** The portion size is the least accurate part. Every nutrition value scales with grams: `new = value × new_grams / old_grams`.
- **The food server doesn't save anything.** It only answers requests. Meals the user confirms should be saved by whoever owns the database.
- **To reach it from another machine,** start it with `-Lan` and use `http://<this PC's IP>:8000`. Add browser origins to `ALLOWED_ORIGINS` (see [Settings](#settings)).

---

## Testing

| # | Check | How | Passes if |
|---|---|---|---|
| 1 | USDA lookup | `python nutrition.py "white rice, cooked"` | About 130 kcal per 100 g |
| 2 | Server is up | <http://127.0.0.1:8000/health> | `"ready": true` |
| 3 | Photo | Test page: upload a food photo | Foods and totals appear; status `ok` or `partial` |
| 4 | Text, fast path | `python test_api.py --text "2 eggs and a slice of toast"` | `"source": "quick_parse"`, under 1 s |
| 5 | Text, AI model | `python test_api.py --text "a big bowl of chicken alfredo"` | `"source": "model"` |
| 6 | API key | Test page with the key box empty (when a key is set) | `Error 401` |
| 7 | Bad file | Upload a `.txt` renamed to `.jpg` | `Error 400` |
| 8 | Other device | `start_server.ps1 -Lan`, then open the printed address on a phone on the same Wi-Fi | Same as check 3 |
| 9 | Accuracy | `python evaluate.py eval_data\labels.csv` | Prints the average calorie error and the % within ±20% |

Checks 1–8 show that it **works**. Check 9 shows how **accurate** it is; see
[Accuracy and next steps](#accuracy-and-next-steps).

---

## Settings

All settings are optional environment variables. Set one permanently with
`setx NAME "value"`, then open a new terminal. Use `$env:NAME="value"` to set one for
the current terminal only.

| Variable | Default | What it does |
|---|---|---|
| `FDC_API_KEY` | `DEMO_KEY` (only a few requests per hour) | Your USDA API key |
| `FOOD_API_KEY` | none (no key required) | If set, every request must send `X-API-Key: <value>`. Always set it before letting other devices connect. |
| `ALLOWED_ORIGINS` | `http://localhost:3000,http://localhost:5173` | Websites allowed to call the server from a browser |
| `FOOD_MODEL` | `Qwen/Qwen2.5-VL-7B-Instruct` | AI model; `Qwen/Qwen2.5-VL-3B-Instruct` is the smaller one |
| `FOOD_LORA` | none | Folder with a fine-tuned adapter |
| `HOST` / `PORT` | `127.0.0.1` / `8000` | Where the server listens; `0.0.0.0` allows other devices |

---

## Troubleshooting

**Everything is extremely slow, the GPU is at 99%, and the PC lags.**
The GPU ran out of memory. On Windows this doesn't crash: the overflow goes into
regular RAM, which is far slower. Stop the server, then:
1. Run `nvidia-smi` and look for other `python.exe` or `ollama` processes.
2. Run `ollama ps`; unload anything listed with `ollama stop <name>`.
3. Close any other copy of the server.
4. Or start with `-Small`.

Optional: in NVIDIA Control Panel, go to **Manage 3D settings** and set
**CUDA - Sysmem Fallback Policy** to **Prefer No Sysmem Fallback**. Running out of
memory then gives a clear error instead of lag.

**`CUDA out of memory`**
Same cause as above. Free GPU memory or use `-Small`.

**`torch.cuda.is_available()` is `False`**
Either the NVIDIA driver is missing, or PyTorch was installed without GPU support.
Reinstall it with the `--index-url .../cu124` command from [Manual setup](#manual-setup).

**Foods are right but calories are way off**
Check the USDA description shown under each food. If it matched the wrong food, delete
that food's line in `cache\fdc_cache_v2.json`, and it will be looked up again next time.

**Foods show "no USDA match" or a `lookup_error` after a few requests**
You're probably using `DEMO_KEY`, which is limited to a few requests per hour. Set your
own `FDC_API_KEY`.

**`401 Missing or wrong X-API-Key`**
The server has `FOOD_API_KEY` set. Send the same value in the `X-API-Key` header, or
paste it into the key box on the test page.

**A browser site gets a CORS error**
Add the site's address (for example `http://localhost:8080`) to `ALLOWED_ORIGINS`, then
restart the server.

**`503 Model is still loading`**
The server was just started. Wait for `Model ready.` Simple fast-path text still works
during this time.

**Phone or Pi can't connect**
Start with `-Lan`, use the IP address it prints, make sure both devices are on the same
network, and allow Python through Windows Firewall on private networks.

**PowerShell says running scripts is disabled**
Use `powershell -ExecutionPolicy Bypass -File <script>.ps1`, as shown above.

---

## Files

| File | What it does |
|---|---|
| `setup.ps1` | One-time setup |
| `start_server.ps1` | Starts the server (`-Small`, `-Lan`, `-Port`) |
| `server.py` | The web API (`/analyze`, `/health`) and the test page at `/` |
| `analyze_food.py` | Core logic: photo or text → foods → nutrition → JSON. Also a command-line tool. |
| `quick_parse.py` | Fast path for simple typed meals. Add foods to `PORTIONS` so more meals skip the AI. |
| `nutrition.py` | Label cleanup, USDA lookup, nutrition math |
| `evaluate.py` | Accuracy scoring against photos with known calories |
| `test_api.py` | Sends a request the way the app or the Pi would |
| `static/index.html` | The test page |
| `API.md` | Full request/response reference for teammates |
| `requirements.txt` | Python packages |

These are created when it runs and are kept out of git:
- `.venv/`
- `cache/` (USDA lookups)
- `results/` (saved JSON)
- `photos/` and `eval_data/` (your images)

---

## Accuracy and next steps

**Measure it.** Make a CSV with the columns `image,true_kcal`, using photos where you
know the real calories. You can weigh your own meals, or use overhead photos from the
Nutrition5k dataset. Then run:

```powershell
python evaluate.py eval_data\labels.csv --limit 50
```

It prints the average calorie error and the percentage of photos within ±20% of the
true value.

**Known limits.** Food identification is usually right. Portion size is the hard part:
hidden oil, sauces, and food stacked on other food are where estimates miss most. Use
the `text` note ("cooked in butter") and let users edit grams.

**Fine-tuning (later).** If accuracy falls short of the target, train a LoRA adapter for
Qwen2.5-VL on Nutrition5k (photo → foods + grams), save it in `food_lora/`, and run with
`FOOD_LORA=food_lora`. The code already loads adapters.
