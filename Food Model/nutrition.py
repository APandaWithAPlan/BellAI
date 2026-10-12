"""
nutrition.py - turn food labels into calories, protein, carbs, fat and more using USDA FoodData Central.

The vision model only says WHAT the food is and HOW MANY GRAMS. This file looks the
food up in the USDA database and does the nutrition math, so the numbers always
come from real nutrition data instead of the model's imagination.

API key (free): sign up at https://fdc.nal.usda.gov/api-key-signup then, in a new terminal:
    setx FDC_API_KEY "your-key-here"
Without a key it uses DEMO_KEY, which only allows a few requests per hour.

Lookups are cached in cache/fdc_cache_v2.json, so each food is only fetched once.
If a food keeps matching the wrong USDA entry, delete its line from that file
(or the whole file) and it will be looked up again.

Quick test:
    python nutrition.py "white rice, cooked"
"""

import json
import os
import re
import sys
from pathlib import Path

import requests

HERE = Path(__file__).resolve().parent
CACHE_FILE = HERE / "cache" / "fdc_cache_v2.json"
FDC_SEARCH_URL = "https://api.nal.usda.gov/fdc/v1/foods/search"

# Survey (FNDDS) covers prepared dishes ("lasagna", "chicken burrito");
# Foundation and SR Legacy cover single ingredients. All report nutrients per 100 g.
DATA_TYPES = ["Survey (FNDDS)", "Foundation", "SR Legacy"]

# Energy in kcal: Energy, then the two Atwater values (some Foundation foods only have those)
ENERGY_NUTRIENT_IDS = [1008, 2047, 2048]

# output name -> (USDA nutrient id, unit)
NUTRIENTS = {
    "protein_g": (1003, "G"),
    "carbs_g":   (1005, "G"),
    "fat_g":     (1004, "G"),
    "fiber_g":   (1079, "G"),
    "sugar_g":   (2000, "G"),
    "sodium_mg": (1093, "MG"),
}
NUTRIENT_KEYS = ["kcal"] + list(NUTRIENTS)

# Words that usually mean "not what the photo shows" unless the label asked for them
ODD_WORDS = {"baby", "infant", "toddler", "glutinous", "dry", "dehydrated", "powder",
             "mix", "frozen", "canned", "raw", "unprepared", "formula", "imitation"}
ODD_WORDS = {w.rstrip("s") for w in ODD_WORDS}  # same normalization as _words()


def clean_label(text):
    """Lowercase, strip odd characters and extra spaces: ' Grilled  Chicken!! ' -> 'grilled chicken'."""
    text = str(text or "").lower()
    text = re.sub(r"[^a-z0-9 ,'()\-]", " ", text)
    text = re.sub(r"\s+", " ", text).strip(" ,-")
    return text[:80]


def _words(text):
    return [w.rstrip("s") for w in re.split(r"[^a-z0-9]+", text.lower()) if len(w) > 2]


def _load_cache():
    try:
        return json.loads(CACHE_FILE.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def _save_cache(cache):
    CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
    CACHE_FILE.write_text(json.dumps(cache, indent=2, sort_keys=True), encoding="utf-8")


def _nutrient_table(food):
    """{(nutrient id, UNIT): value} for one USDA search result."""
    table = {}
    for n in food.get("foodNutrients", []):
        nested = n.get("nutrient") or {}
        nid = n.get("nutrientId") or nested.get("id")
        unit = (n.get("unitName") or nested.get("unitName") or "").upper()
        value = n.get("value", n.get("amount"))
        if nid is not None and value is not None:
            table[(int(nid), unit)] = float(value)
    return table


def per_100g(food):
    """Nutrition per 100 g for one USDA result, or None if it has no calorie value."""
    table = _nutrient_table(food)
    kcal = next((table[(i, "KCAL")] for i in ENERGY_NUTRIENT_IDS if (i, "KCAL") in table), None)
    if kcal is None:
        return None
    values = {"kcal": round(kcal, 1)}
    for key, (nid, unit) in NUTRIENTS.items():
        v = table.get((nid, unit))
        values[key] = round(v, 2) if v is not None else None
    return values


def _best_match(label, foods):
    """
    Pick the USDA result that best fits the label:
      - it must contain every word of the label
      - fewer extra words is better ("rice, white, cooked" beats "rice, white, cooked, glutinous")
      - odd words like "baby food" or "dry" are heavily penalized unless the label used them
    Falls back to USDA's top result if nothing contains all the words.
    """
    want = set(_words(label))
    usable = [f for f in foods if per_100g(f) is not None]
    best, best_score = None, None
    for rank, food in enumerate(usable):
        have = set(_words(food.get("description", "")))
        if not want <= have:
            continue
        extra = have - want
        score = len(extra) + 5 * len(extra & ODD_WORDS) + 0.1 * rank
        if best_score is None or score < best_score:
            best, best_score = food, score
    return best or (usable[0] if usable else None)


def search_usda(label, api_key=None):
    """Ask the USDA API for a label. Returns the raw list of matching foods."""
    api_key = api_key or os.environ.get("FDC_API_KEY", "DEMO_KEY")
    resp = requests.post(
        FDC_SEARCH_URL,
        params={"api_key": api_key},
        json={"query": label, "dataType": DATA_TYPES, "pageSize": 25},
        timeout=20,
    )
    resp.raise_for_status()
    return resp.json().get("foods", [])


def lookup(label, use_cache=True):
    """
    Look up one cleaned label. Returns
        {"fdc_id": 168932, "fdc_description": "Rice, white, ... cooked",
         "usda_category": "Cereal Grains and Pasta",
         "per_100g": {"kcal": 130.0, "protein_g": 2.69, "carbs_g": 28.2, ...}}
    or None if USDA has nothing usable.
    """
    label = clean_label(label)
    if not label:
        return None
    cache = _load_cache() if use_cache else {}
    if label in cache:
        return cache[label]

    food = _best_match(label, search_usda(label))
    result = None
    if food:
        category = food.get("foodCategory")
        if isinstance(category, dict):
            category = category.get("description")
        result = {
            "fdc_id": food.get("fdcId"),
            "fdc_description": food.get("description"),
            "usda_category": category,
            "per_100g": per_100g(food),
        }
    if use_cache:
        cache[label] = result
        _save_cache(cache)
    return result


def scale(per_100, grams):
    """Nutrition for a given weight: per-100 g values x grams / 100."""
    out = {}
    for key in NUTRIENT_KEYS:
        v = per_100.get(key) if per_100 else None
        if v is None:
            out[key] = None
        else:
            out[key] = round(v * grams / 100) if key in ("kcal", "sodium_mg") else round(v * grams / 100, 1)
    return out


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print('Usage: python nutrition.py "food name"')
        sys.exit(1)
    print(json.dumps(lookup(" ".join(sys.argv[1:])), indent=2))
