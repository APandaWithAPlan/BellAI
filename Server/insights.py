"""Turn a user's meals and preferences into food and workout recommendations.

Steps: stats in code -> AI writes recommendations as JSON -> limiting script enforces preferences.
If the AI is down or returns something unusable, safe default recommendations are used instead.

Quick test without a server (needs Ollama running):
    python insights.py sample_request.json
"""

import json
import os
import re
import sys
import time

import httpx

from limits import apply_limits
from prompt import RESPONSE_SCHEMA, SYSTEM_PROMPT, user_message
from stats import compute_flags



def ollama_base():
    """Same OLLAMA_HOST setting as the voice server (default 127.0.0.1:11434)."""
    host = os.environ.get("OLLAMA_HOST", "127.0.0.1:11434").strip().rstrip("/")
    if "://" not in host:
        host = "http://" + host
    return host.replace("//0.0.0.0", "//127.0.0.1")


OLLAMA_URL = ollama_base()
MODEL = os.environ.get("INSIGHTS_MODEL", "qwen3.5:4b-q4_K_M")   # same chat model as the AI server

FLAG_TEXT = {
    "low_protein": "You're low on protein today",
    "high_sodium": "Sodium is high today",
    "over_calories": "You're over your calorie goal today",
    "under_calories": "You're well under your calorie goal so far",
    "low_fiber": "Fiber is low today",
    "high_sugar": "Sugar is high today",
}


def ask_ollama(user_text, timeout=60):
    """Ask the chat model for JSON that matches RESPONSE_SCHEMA. Returns a dict or None."""
    body = {
        "model": MODEL,
        "stream": False,
        "think": False,                      # skip the long thinking step on thinking models
        "format": RESPONSE_SCHEMA,           # forces the reply into this JSON shape
        "options": {"temperature": 0.3},
        "messages": [{"role": "system", "content": SYSTEM_PROMPT},
                     {"role": "user", "content": user_text}],
    }
    resp = httpx.post(f"{OLLAMA_URL}/api/chat", json=body, timeout=timeout)
    if resp.status_code == 400 and "think" in resp.text.lower():
        body.pop("think")                    # model doesn't support the think option
        resp = httpx.post(f"{OLLAMA_URL}/api/chat", json=body, timeout=timeout)
    resp.raise_for_status()
    content = resp.json().get("message", {}).get("content", "")
    content = re.sub(r"<think>.*?</think>", "", content, flags=re.S).strip()
    try:
        data = json.loads(content)
        return data if isinstance(data, dict) else None
    except json.JSONDecodeError:
        return None


def fallback_summary(flags, totals, targets):
    if flags and flags[0]["type"] == "no_meals":
        return "No meals logged yet today. Log a meal to get personalized tips."
    if not flags:
        return f"You're on track today at {totals['kcal']:.0f} of {targets['kcal']:.0f} calories. Keep it up!"
    f = flags[0]
    return f"{FLAG_TEXT.get(f['type'], f['type'])}: {f['value']:.0f} {f['unit']} vs a target of {f['target']:.0f} {f['unit']}."


def generate_insights(user, meals, ask_model=ask_ollama):
    """Main entry point. Always returns a complete JSON-ready dict."""
    t0 = time.perf_counter()
    user, meals = user or {}, meals or []
    totals, targets, flags = compute_flags(user, meals)
    remaining = max(0, round(targets["kcal"] - totals["kcal"]))

    ai, source, error = None, "model", None
    try:
        ai = ask_model(user_message(user, totals, targets, flags))
    except Exception as e:                    # model server down, timeout, ...
        error = str(e)[:200]
    if not ai:
        source = "defaults"

    foods, workouts, removed = apply_limits(ai, user, flags, remaining)
    summary = (ai or {}).get("summary") if source == "model" else None
    if not isinstance(summary, str) or not summary.strip():
        summary = fallback_summary(flags, totals, targets)

    status = "on_track" if not flags else flags[0]["type"]
    return {
        "type": "insights",
        "status": status,
        "summary": summary.strip(),
        "flags": flags,
        "totals": totals,
        "targets": targets,
        "calories_remaining": remaining,
        "food_recommendations": foods,
        "workout_recommendations": workouts,
        "removed_by_limits": removed,        # AI suggestions dropped for breaking a preference
        "source": source,                    # "model" or "defaults"
        "model": MODEL if source == "model" else None,
        "error": error,
        "timing_ms": round((time.perf_counter() - t0) * 1000),
    }


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("Usage: python insights.py request.json   (with {\"user\": {...}, \"meals\": [...]})")
    req = json.load(open(sys.argv[1], encoding="utf-8"))
    print(json.dumps(generate_insights(req.get("user"), req.get("meals")), indent=2))
