# BellAi Insights

## Overview

**BellAi Insights** gives food and workout recommendations based on what the user ate today. It takes the user's meals and preferences and returns JSON with flags (like low protein or high sodium), 2 to 4 food suggestions, 1 or 2 workout suggestions and a one sentence summary.

The numbers are computed in code. The chat model on the AI server (Ollama, `qwen3.5:4b-q4_K_M` by default) only writes the suggestions, and a limiting script removes anything that breaks the user's allergies, diet, calorie budget or injuries. If the model is down, safe default suggestions are returned instead.

## Getting Started

### Prerequisites

* Python: `3.10` or newer.
* Ollama: running on the AI server with the chat model pulled (`ollama pull qwen3.5:4b-q4_K_M`).
* Packages: `fastapi`, `uvicorn` and `httpx`, the same ones the AI server already uses (`pip install -r requirements.txt`).

### How to Enable / Access

1. **On the AI server:** in `Server/bell_voice_server.py`, add these two lines right after `app = FastAPI(...)`, then restart the server. `/insights` is then served on port `8000` next to the other endpoints.
```python
import sys; sys.path.insert(0, str(HERE.parent / "Insights")); from insights_server import router as insights_router
app.include_router(insights_router)
```
2. **On its own for testing:** run `python insights_server.py` from this folder. It listens on port `8001` and talks to Ollama at `OLLAMA_HOST` (default `127.0.0.1:11434`).
3. Check http://127.0.0.1:8001/insights/health (or port `8000` on the AI server) to confirm the model is reachable.

## How to Use It

1. **Send a request:** `POST /insights` with a JSON body containing `user` (calorie goal, allergies, diet, injuries, fitness level) and `meals` (food model results or simple nutrient totals). See `sample_request.json`.
2. **Read the reply:** `status` is the main flag (`low_protein`, `high_sodium`, `on_track`, `no_meals` and others), `summary` is the sentence to show, and `food_recommendations` and `workout_recommendations` are the suggestions.
3. **Check what was removed:** `removed_by_limits` lists AI suggestions that broke a preference, and `source` says whether the model or the defaults answered.
4. **Test without a server:** run `python insights.py sample_request.json`.

> **Tip:** Set `INSIGHTS_API_KEY` before letting other devices connect. Every request then needs the header `X-API-Key: <value>`.
