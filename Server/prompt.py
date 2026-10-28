"""System prompt and JSON schema for the recommendations model."""

import json

SYSTEM_PROMPT = """You are BellAi's nutrition and fitness coach.
You receive a user's nutrition totals for today, their daily targets, flags computed from them
(for example low_protein or high_sodium), and their preferences.

Give 2 to 4 food recommendations and 1 or 2 workout recommendations that address the flags.
Rules:
- Use only foods the user can eat. Never suggest anything containing their allergens.
- Respect their diet type (for example vegetarian or vegan) and stay within their remaining calories.
- Respect injuries and fitness level. Suggest low impact exercise when there is an injury.
- Use specific foods and portions, like "1 cup Greek yogurt", with realistic nutrition estimates.
- Never suggest skipping meals or eating less than 1200 calories in a day.
- Keep the tone short, encouraging and practical. Do not diagnose or use medical language.
- If there are no flags, say they are on track and suggest how to keep it up.
- If no meals were logged, encourage them to log meals and give general balanced suggestions.
Reply with JSON only, matching the schema you are given."""

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


def user_message(user, totals, targets, flags):
    """The data the model sees. Only the fields it needs, as JSON."""
    prefs = {k: user.get(k) for k in ("allergies", "diet", "goal", "injuries", "fitness_level", "dislikes")}
    remaining = max(0, round(targets["kcal"] - totals["kcal"]))
    return json.dumps({
        "today_totals": totals,
        "daily_targets": targets,
        "calories_remaining": remaining,
        "flags": flags,
        "preferences": prefs,
    }, indent=2)
