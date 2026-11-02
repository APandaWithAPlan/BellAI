# BellAi Insights

## Overview

**BellAi Insights** gives food and workout recommendations based on what the user ate today. You send it the user's meals and preferences and it sends back the biggest problems with their day (like low protein or high sodium), a few food and workout ideas, and a short summary BellAi can read out loud.

All the nutrition math is done in code. The chat model on the AI server (`qwen3.5:4b-q4_K_M` on Ollama) only writes the suggestions and one tip, and anything that breaks the user's allergies, diet, calorie budget or injuries gets removed before it's sent back. If the model is down, it falls back to safe default suggestions.

## Getting Started

### Prerequisites

* Python: `3.10` or newer.
* Ollama: running on the AI server with the chat model pulled (`ollama pull qwen3.5:4b-q4_K_M`).
* Packages: run `pip install -r requirements.txt`. `psycopg` is only needed for the database.
* Database: PostgreSQL 14 or newer, with `DATABASE_URL` set to its address.

### How to Enable / Access

1. **On the AI server:** add these two lines to `Server/bell_voice_server.py` right after `app = FastAPI(...)` and restart it. `/insights` then runs on port `8000` with the other endpoints.
```python
import sys; sys.path.insert(0, str(HERE.parent / "Insights")); from insights_server import router as insights_router
app.include_router(insights_router)
```
2. **On its own for testing:** run `python insights_server.py` from this folder. It runs on port `8001`.
3. Open http://127.0.0.1:8001/docs (or port `8000` on the AI server) to send test requests from the browser.
4. **Database:** run `psql -d bellai -f setup/schema.sql` once to create the tables.

## How to Use It

1. **Send a request:** `POST /insights` with the user's preferences under `user` (calorie goal, allergies, diet, injuries, fitness level) and today's meals under `meals`. Any scenario in `tests/scenarios.json` works as an example.
2. **Read the reply:** `status` is the biggest problem, `summary` is the sentence to show or read out loud, and `food_recommendations` and `workout_recommendations` are the ideas.
3. **See what got removed:** `removed_by_limits` lists suggestions that broke one of the user's limits, and `source` says whether the model or the defaults answered.
4. **Use the database:** `load_insights_request(conn, user_id)` in `db.py` gets a user's preferences and today's meals, and `save_meal(conn, user_id, analysis)` saves a meal from `/analyze`.
5. **Run the tests:** `python tests/run_scenarios.py` checks that the limits catch a fake reply that breaks every rule. Add `--live` to try the real model, or `--only <name>` to run one scenario.
6. **Add test users:** run `psql -d bellai -f tests/seed_test_data.sql` to load 9 test users with a week of meals. Remove them with `DELETE FROM users WHERE id >= 9001;`.

> **Tip:** Set `INSIGHTS_API_KEY` before letting other devices connect, then send it in the `X-API-Key` header. When loading from the database, get the `user_id` from the signed-in user's token, not the request body.
