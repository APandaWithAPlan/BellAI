"""
evaluate.py - measure how accurate the food model is.

Needs a CSV answer key. get_eval_data.py makes one from Nutrition5k, or write your own:
    image,true_kcal,true_foods
    eval_data/my_meals/breakfast.jpg,350,eggs; toast
    eval_data/my_meals/lunch.jpg,620,rice; chicken; broccoli
(true_foods is optional: separate foods with ";". Without it only calories are scored.)

Run (from the Food Model folder, with the .venv active; STOP server.py first - both need the GPU):
    python evaluate.py eval_data/nutrition5k/labels.csv
    python evaluate.py eval_data/nutrition5k/labels.csv --limit 10     quick check

What it reports
  Food identification   % of photos where the model named at least half of the main foods,
                        and % of all main foods it found
  Calories              average % error, and % of photos within +/-20% and +/-10% of the truth
Every photo's result is saved to results/eval_<time>.csv so you can see what it got wrong.

Food-name matching is word-based and forgiving ("grilled chicken breast" matches "chicken",
"salad greens" matches "mixed greens"), so check the CSV for borderline cases.
"""

import argparse
import csv
import re
import sys
import time
from datetime import datetime
from pathlib import Path

from analyze_food import MODEL_ID, RESULTS_DIR, analyze, load_model

HERE = Path(__file__).resolve().parent

# words that describe preparation, not the food itself
IGNORE_WORDS = {"cooked", "raw", "fresh", "grilled", "roasted", "baked", "fried", "steamed", "boiled",
                "sauteed", "plain", "whole", "sliced", "chopped", "diced", "mixed", "with", "and",
                "the", "piece", "pieces", "small", "large", "medium", "style", "homemade", "prepared"}
# a few names that mean the same thing on a plate
SYNONYMS = {
    "green": {"lettuce", "salad", "spinach", "arugula", "kale", "green"},
    "lettuce": {"green", "salad", "lettuce"},
    "salad": {"green", "lettuce", "salad"},
    "potato": {"potato", "fry", "fries", "hash"},
    "pasta": {"pasta", "spaghetti", "noodle", "penne", "macaroni"},
    "noodle": {"noodle", "pasta"},
    "egg": {"egg", "omelet", "omelette"},
    "beef": {"beef", "steak", "burger", "hamburger"},
    "steak": {"steak", "beef"},
}


def _words(text):
    out = set()
    for w in re.findall(r"[a-z]+", (text or "").lower()):
        if len(w) <= 2 or w in IGNORE_WORDS:
            continue
        if w.endswith("ies") and len(w) > 4:
            w = w[:-3] + "y"
        elif w.endswith(("oes", "ches", "shes")):
            w = w[:-2]
        elif w.endswith("s") and not w.endswith("ss"):
            w = w[:-1]
        out.add(w)
    return out


def food_found(true_food, predicted_words):
    """True if any word of the real food (or a synonym) appears in what the model said."""
    for w in _words(true_food):
        if w in predicted_words or (SYNONYMS.get(w, set()) & predicted_words):
            return True
    return False


def score_foods(true_foods, items):
    """-> (found, total, list of missed foods)"""
    predicted = set()
    for item in items:
        predicted |= _words(item.get("label"))
        if item.get("usda"):
            predicted |= _words(item["usda"].get("fdc_description"))
    found = [f for f in true_foods if food_found(f, predicted)]
    missed = [f for f in true_foods if f not in found]
    return len(found), len(true_foods), missed


def summarize(rows):
    """Headline numbers from the per-photo rows."""
    s = {"photos": len(rows)}
    cal = [r for r in rows if r["true_kcal"] > 0 and r["pred_kcal"] is not None]
    if cal:
        errors = [abs(r["pred_kcal"] - r["true_kcal"]) / r["true_kcal"] for r in cal]
        s["calorie_photos"] = len(cal)
        s["mean_abs_pct_error"] = round(100 * sum(errors) / len(errors), 1)
        s["within_20pct"] = round(100 * sum(e <= 0.20 for e in errors) / len(errors), 1)
        s["within_10pct"] = round(100 * sum(e <= 0.10 for e in errors) / len(errors), 1)
    food = [r for r in rows if r.get("foods_total")]
    if food:
        s["food_photos"] = len(food)
        s["food_id_accuracy"] = round(100 * sum(r["foods_found"] * 2 >= r["foods_total"] for r in food) / len(food), 1)
        s["food_recall"] = round(100 * sum(r["foods_found"] for r in food) / sum(r["foods_total"] for r in food), 1)
    return s


def main():
    ap = argparse.ArgumentParser(description="Score the food model against an answer key.")
    ap.add_argument("labels_csv", help="CSV with columns image,true_kcal and optionally true_foods")
    ap.add_argument("--limit", type=int, help="only test the first N photos")
    ap.add_argument("--model", default=MODEL_ID)
    ap.add_argument("--lora", help="folder with a fine-tuned LoRA adapter")
    args = ap.parse_args()

    labels_path = Path(args.labels_csv)
    with open(labels_path, newline="", encoding="utf-8") as f:
        tests = list(csv.DictReader(f))[: args.limit]
    if not tests:
        sys.exit("No rows found in the CSV.")

    model, processor = load_model(args.model, args.lora)
    rows, start = [], time.perf_counter()
    for i, t in enumerate(tests, 1):
        image = Path(t["image"])
        if not image.is_absolute() and not image.exists():
            image = HERE / image                      # paths in the CSV are relative to Food Model
        if not image.exists():
            print(f"[{i}/{len(tests)}] missing photo, skipped: {t['image']}")
            continue

        result = analyze(model, processor, image, model_id=args.model, image_name=image.name)
        items = result["items"]
        # finding nothing (or garbled output) counts as 0 kcal - a miss, not a skipped photo
        pred = result["totals"]["kcal"] or 0
        true_kcal = float(t["true_kcal"])
        true_foods = [x.strip() for x in (t.get("true_foods") or "").split(";") if x.strip()]
        found, total, missed = score_foods(true_foods, items) if true_foods else (0, 0, [])

        row = {
            "image": t["image"],
            "true_kcal": true_kcal,
            "pred_kcal": pred,
            "kcal_error_pct": round(100 * (pred - true_kcal) / true_kcal, 1) if pred is not None and true_kcal else None,
            "true_grams": t.get("true_grams", ""),
            "pred_grams": round(sum(x["grams"] for x in items), 1),
            "true_foods": "; ".join(true_foods),
            "pred_foods": "; ".join(f'{x["label"]} {x["grams"]}g' for x in items),
            "foods_found": found,
            "foods_total": total,
            "missed_foods": "; ".join(missed),
            "status": result["status"],
            "unmatched": "; ".join(result["unmatched_labels"]),
            "seconds": round(result["timing_ms"].get("total", 0) / 1000, 1),
        }
        rows.append(row)
        err = f"{row['kcal_error_pct']:+.0f}%" if row["kcal_error_pct"] is not None else "n/a"
        foods = f"  foods {found}/{total}" if total else ""
        print(f"[{i}/{len(tests)}] {image.name}: true {true_kcal:.0f} kcal / predicted {pred} ({err}){foods}")

    if not rows:
        sys.exit("No photos could be scored.")

    RESULTS_DIR.mkdir(exist_ok=True)
    out = RESULTS_DIR / f"eval_{datetime.now():%Y%m%d_%H%M%S}.csv"
    with open(out, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    s = summarize(rows)
    minutes = (time.perf_counter() - start) / 60
    print("\n" + "=" * 52)
    print(f" BellAi food model accuracy  ({s['photos']} photos, {minutes:.1f} min)")
    print("=" * 52)
    if "food_id_accuracy" in s:
        print(f" Food identification:   {s['food_id_accuracy']}%  of photos (named at least half the main foods)")
        print(f" Main foods found:      {s['food_recall']}%  of all main foods")
    if "mean_abs_pct_error" in s:
        print(f" Calories within +/-20%: {s['within_20pct']}%  of photos")
        print(f" Calories within +/-10%: {s['within_10pct']}%  of photos")
        print(f" Average calorie error: {s['mean_abs_pct_error']}%")
    partial = sum(r["status"] == "partial" for r in rows)
    if partial:
        print(f" ({partial} photos had a food with no USDA match, so their calories are likely too low)")
    print("=" * 52)
    print(f" Every photo's result: {out}")


if __name__ == "__main__":
    main()
