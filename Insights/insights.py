# Builds food and workout recommendations from a user's meals and preferences.

import json
import os
import re
import time

import httpx

from limits import apply_limits, text_allowed

MODEL = os.environ.get("INSIGHTS_MODEL", "qwen3.5:4b-q4_K_M")   # same chat model as the AI server
MAX_SENTENCE_CHARS = 160   # longest model sentence kept in the summary
SUMMARY_FLAGS = 2          # how many flags the summary mentions

# nutrient keys shared with the food model and the database
NUTRIENTS = ["kcal", "protein_g", "carbs_g", "fat_g", "fiber_g", "sugar_g", "sodium_mg"]

# targets used when the user hasn't set their own
DEFAULTS = {
    "calorie_goal": 2000,     # kcal per day
    "sodium_limit_mg": 2300,  # FDA daily value
    "fiber_goal_g": 28,       # FDA daily value
    "sugar_limit_g": 100,     # total sugar (fruit, milk and added); the FDA 50 g limit is for added sugar only
}

CALORIE_FLOOR = 1200      # eating less than this is a health risk and always ranks first

# how much each flag matters when ranking them; fiber and sugar are minor next to the rest
FLAG_WEIGHT = {"under_calories": 1.5, "low_protein": 1.0, "high_sodium": 1.0,
               "over_calories": 1.0, "low_fiber": 0.6, "high_sugar": 0.6}

# how each flag is described in the summary
FLAG_TEXT = {
    "low_protein": "You're low on protein today",
    "high_sodium": "Sodium is high today",
    "over_calories": "You're over your calorie goal today",
    "under_calories": "You're well under your calorie goal so far",
    "low_fiber": "Fiber is low today",
    "high_sugar": "Sugar is high today",
}

# instructions the model reads before every request
SYSTEM_PROMPT = """You are BellAi's nutrition and fitness coach.
You receive a user's nutrition totals for today, their daily targets, flags computed from them
(for example low_protein or high_sodium), and their preferences. Flags are listed most important first.

Give 2 to 4 food recommendations and 1 or 2 workout recommendations that address the flags.
Rules:
- Use only foods the user can eat. Never suggest anything containing their allergens.
- Respect their diet type (for example vegetarian or vegan) and stay within their remaining calories.
- Respect injuries and fitness level. Suggest low impact exercise when there is an injury.
- Use specific foods and portions, like "1 cup Greek yogurt", with realistic nutrition estimates.
- Never suggest skipping meals or eating less than 1200 calories in a day.
- If the user is well under their calories, encourage a full, balanced meal rather than a snack.
- Keep the tone short, encouraging and practical. Do not diagnose or use medical language.
- If there are no flags, suggest how to keep it up.
- If no meals were logged, encourage them to log meals and give general balanced suggestions.
The "summary" is ONE short sentence (under 20 words) saying what to do next, like
"Adding a protein-rich snack this afternoon would round out your day."
- The app already shows the numbers, so the summary must contain no numbers.
- Never add up, total or calculate calories or nutrients anywhere in your reply.
- Do not say the user is on track when there are flags.
Reply with JSON only, matching the schema you are given."""

# Ollama forces the model's reply into this JSON shape
RESPONSE_SCHEMA = {
    "type": "object",
    "properties": {
        "summary": {"type": "string"},
        "food_recommendations": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "title": {"type": "string"},
                    "why": {"type": "string"},
                    "ingredients": {"type": "array", "items": {"type": "string"}},
                    "kcal": {"type": "number"},
                    "protein_g": {"type": "number"},
                    "sodium_mg": {"type": "number"},
                },
                "required": ["title", "why", "ingredients", "kcal"],
            },
        },
        "workout_recommendations": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "title": {"type": "string"},
                    "why": {"type": "string"},
                    "minutes": {"type": "number"},
                    "intensity": {"type": "string", "enum": ["light", "moderate", "hard"]},
                },
                "required": ["title", "why", "minutes", "intensity"],
            },
        },
    },
    "required": ["summary", "food_recommendations", "workout_recommendations"],
}


# --- Nutrition math ---

# Daily calorie target
def calorie_goal(user):
    return float(user.get("calorie_goal") or DEFAULTS["calorie_goal"])


# Daily protein target in grams
def protein_goal(user):
    if user.get("protein_goal_g"):
        return float(user["protein_goal_g"])
    if user.get("weight_kg"):
        return round(0.8 * float(user["weight_kg"]))
    return round(0.20 * calorie_goal(user) / 4)


# Sums nutrients across meals
def daily_totals(meals):
    total = {k: 0.0 for k in NUTRIENTS}
    for meal in meals:
        src = meal.get("totals", meal)
        for k in NUTRIENTS:
            total[k] += float(src.get(k) or 0)
    return {k: round(v, 1) for k, v in total.items()}


# Totals, targets and ranked flags
def compute_flags(user, meals):
    totals = daily_totals(meals)
    targets = {
        "kcal": calorie_goal(user),
        "protein_g": protein_goal(user),
        "sodium_mg": float(user.get("sodium_limit_mg") or DEFAULTS["sodium_limit_mg"]),
        "fiber_g": float(user.get("fiber_goal_g") or DEFAULTS["fiber_goal_g"]),
        "sugar_g": float(user.get("sugar_limit_g") or DEFAULTS["sugar_limit_g"]),
    }
    if not meals:
        return totals, targets, [{"type": "no_meals", "value": 0, "target": 0, "unit": ""}]

    checks = {
        "under_calories": ("kcal", "kcal", totals["kcal"] < 0.70 * targets["kcal"]),
        "low_protein": ("protein_g", "g", totals["protein_g"] < 0.8 * targets["protein_g"]),
        "high_sodium": ("sodium_mg", "mg", totals["sodium_mg"] > targets["sodium_mg"]),
        "over_calories": ("kcal", "kcal", totals["kcal"] > 1.10 * targets["kcal"]),
        "low_fiber": ("fiber_g", "g", totals["fiber_g"] < 0.6 * targets["fiber_g"]),
        "high_sugar": ("sugar_g", "g", totals["sugar_g"] > targets["sugar_g"]),
    }
    flags = []
    for kind, (key, unit, hit) in checks.items():
        if hit:
            flags.append({"type": kind, "value": totals[key], "target": targets[key], "unit": unit})
    flags.sort(key=lambda f: flag_rank(f, totals), reverse=True)
    return totals, targets, flags


# Scores how serious a flag is
def flag_rank(flag, totals):
    if flag["type"] == "under_calories" and totals["kcal"] < CALORIE_FLOOR:
        return float("inf")
    return abs(flag["value"] / flag["target"] - 1) * FLAG_WEIGHT[flag["type"]]


# --- Model ---

# Ollama address from OLLAMA_HOST
def ollama_url():
    host = os.environ.get("OLLAMA_HOST", "127.0.0.1:11434").strip().rstrip("/")
    if "://" not in host:
        host = "http://" + host
    return host.replace("//0.0.0.0", "//127.0.0.1")


OLLAMA_URL = ollama_url()


# JSON the model reads
def user_message(user, totals, targets, flags):
    prefs = {k: user.get(k) for k in ("allergies", "diet", "goal", "injuries", "fitness_level", "dislikes")}
    return json.dumps({
        "today_totals": totals,
        "daily_targets": targets,
        "calories_remaining": max(0, round(targets["kcal"] - totals["kcal"])),
        "flags": flags,
        "preferences": prefs,
    }, indent=2)


# Asks the model for recommendations
def ask_ollama(user_text, timeout=60):
    body = {
        "model": MODEL,
        "stream": False,
        "think": False,                      # skip the long thinking step on thinking models
        "format": RESPONSE_SCHEMA,
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


# --- Summary ---

# Fact sentence from real numbers
def fallback_summary(flags, totals, targets):
    if flags and flags[0]["type"] == "no_meals":
        return "No meals logged yet today. Log a meal to get personalized tips."
    if not flags:
        return f"You're on track today at {totals['kcal']:.0f} of {targets['kcal']:.0f} calories. Keep it up!"
    parts = []
    for i, f in enumerate(flags[:SUMMARY_FLAGS]):
        text = FLAG_TEXT.get(f["type"], f["type"])
        if i:                                # second flag continues the sentence
            text = text[0].lower() + text[1:]
        parts.append(f"{text} ({f['value']:.0f} {f['unit']}, target {f['target']:.0f} {f['unit']})")
    return ", and ".join(parts) + "."


# Model's tip, if it passes checks
def model_sentence(text, user):
    if not isinstance(text, str):
        return None
    text = re.sub(r"\s+", " ", text).strip()
    match = re.match(r"(.+?[.!?])(\s|$)", text)
    sentence = match.group(1) if match else text
    if (not sentence or len(sentence) > MAX_SENTENCE_CHARS or re.search(r"\d", sentence)
            or not text_allowed(sentence, user) or re.search(r"\bon track\b", sentence, re.I)):
        return None
    return sentence


# Facts plus the model's tip
def build_summary(ai_summary, flags, totals, targets, user):
    facts = fallback_summary(flags, totals, targets)
    advice = model_sentence(ai_summary, user)
    return f"{facts} {advice}" if advice else facts


# --- Main entry point ---

# Main entry: full insights reply
def generate_insights(user, meals, ask_model=ask_ollama):
    t0 = time.perf_counter()
    user, meals = user or {}, meals or []
    totals, targets, flags = compute_flags(user, meals)
    remaining = max(0, round(targets["kcal"] - totals["kcal"]))

    ai, error = None, None
    try:
        ai = ask_model(user_message(user, totals, targets, flags))
    except Exception as e:                   # model down or timed out; defaults are used
        error = str(e)[:200]
    source = "model" if ai else "defaults"

    foods, workouts, removed = apply_limits(ai, user, flags, remaining)
    summary = build_summary((ai or {}).get("summary"), flags, totals, targets, user)

    return {
        "type": "insights",
        "status": flags[0]["type"] if flags else "on_track",
        "summary": summary,
        "flags": flags,
        "totals": totals,
        "targets": targets,
        "calories_remaining": remaining,
        "food_recommendations": foods,
        "workout_recommendations": workouts,
        "removed_by_limits": removed,        # model suggestions dropped for breaking a limit
        "source": source,                    # "model" or "defaults"
        "model": MODEL if source == "model" else None,
        "error": error,
        "timing_ms": round((time.perf_counter() - t0) * 1000),
    }
