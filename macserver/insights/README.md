# BellAi Insights (Mac)

## Overview

**BellAi Insights** gives food and workout recommendations based on what the user ate today. You send it the user's meals and preferences and it sends back the biggest problems with their day, such as low protein or high sodium, a few food and workout ideas, and a short summary BellAi can read out loud. It is the `Insights` folder moved to the Mac, with its code unchanged. The app's Activity screen has a Recommendations card that uses it.

All the nutrition math is done in code. The [chat model](../llm/README.md) only writes the suggestions and one tip, and anything that breaks the user's allergies, diet, calorie budget or injuries is removed before it is sent back. If the model is down, it falls back to safe default suggestions.

It only accepts connections from this Mac. The app reaches it through the [voice server](../voice/README.md), which passes `/insights` on.

## Getting Started

### Prerequisites

* Software: `uv` (`brew install uv`). The script installs Python 3.11 and everything else into `.venv`.
* Chat model: The `llm` server on port `11434`. Insights asks it in Ollama's format, which the `llm` server understands.

### How to Enable / Access

1. Run `./start_insights.sh` in this folder, or run `../start.sh`.
2. Open http://127.0.0.1:8004/insights/health. It should show `"model_reachable": true`.
3. Open http://127.0.0.1:8004/docs to send test requests from the browser.

## How to Use It

1. **Send a request:** `POST /insights` with the user's preferences under `user` (calorie goal, allergies, diet, injuries, fitness level) and today's meals under `meals`. Any scenario in `tests/scenarios.json` works as an example.
2. **Read the reply:** `status` is the biggest problem, `summary` is the sentence to show or read out loud, and `food_recommendations` and `workout_recommendations` are the ideas.
3. **See what got removed:** `removed_by_limits` lists suggestions that broke one of the user's limits, and `source` says whether the model or the defaults answered.
4. **Run the tests:** `.venv/bin/python tests/run_scenarios.py` checks that the limits catch a fake reply that breaks every rule. Add `--live` to try the real model, or `--only <name>` to run one scenario.
5. **Change settings:** Set `OLLAMA_HOST` (where the chat model is), `INSIGHTS_MODEL`, `HOST` or `PORT` before `./start_insights.sh`. If you change the port, set `INSIGHTS_URL` on the voice server.

> 💡 **Tip:** The database part of the original (`db.py` and the PostgreSQL tables) is not here. The server never used it. The app keeps the meals it logs on the phone and sends today's with every request, along with the preferences from its Preferences screen, so the server stores nothing about the user.
