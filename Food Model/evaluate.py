"""Score the food model against a CSV answer key (image, true_kcal, true_foods).

Usage: python evaluate.py labels.csv [--limit N] [--lora DIR] [--target 90]

labels.csv columns: image, true_foods ("rice; chicken"), true_kcal (optional).
Use true_foods = none for trick photos with no food: they pass if the model finds no food.

Writes results/eval_<time>.csv (every photo) and results/eval_<time>.html (a report to show).
"""

import argparse
import csv
import html
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path

from analyze_food import MODEL_ID, RESULTS_DIR, analyze, load_model

HERE = Path(__file__).resolve().parent
NOT_FOOD = {"none", "no food", "not food", "-"}   # true_foods value for trick photos

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
    # whole dishes (Food-101 labels) that the model may describe by their parts
    "hamburger": {"hamburger", "burger", "beef", "patty", "bun", "cheeseburger"},
    "burger": {"burger", "hamburger", "patty", "bun", "cheeseburger"},
    "dog": {"dog", "hotdog", "sausage", "frankfurter", "wiener"},
    "chip": {"chip", "fry", "fries", "potato"},
    "fry": {"fry", "fries", "potato", "chip"},
    "donut": {"donut", "doughnut"},
    "sushi": {"sushi", "roll", "nigiri", "maki", "sashimi", "rice", "salmon", "tuna"},
    "sashimi": {"sashimi", "salmon", "tuna", "fish", "raw"},
    "taco": {"taco", "tortilla"},
    "ramen": {"ramen", "noodle", "soup"},
    "pho": {"pho", "noodle", "soup"},
    "macaroni": {"macaroni", "pasta", "noodle", "mac"},
    "spaghetti": {"spaghetti", "pasta", "noodle"},
    "lasagna": {"lasagna", "lasagne", "pasta"},
    "ravioli": {"ravioli", "pasta"},
    "gnocchi": {"gnocchi", "pasta", "dumpling"},
    "dumpling": {"dumpling", "gyoza", "potsticker", "wonton"},
    "gyoza": {"gyoza", "dumpling", "potsticker"},
    "nacho": {"nacho", "tortilla", "chip"},
    "guacamole": {"guacamole", "avocado"},
    "cupcake": {"cupcake", "cake", "muffin"},
    "cheesecake": {"cheesecake", "cake"},
    "pancake": {"pancake", "hotcake"},
    "waffle": {"waffle"},
    "omelette": {"omelette", "omelet", "egg"},
    "rib": {"rib", "pork", "beef"},
    "wing": {"wing", "chicken"},
    "calamari": {"calamari", "squid"},
    "scallop": {"scallop", "shellfish"},
    "mussel": {"mussel", "shellfish", "clam"},
    "oyster": {"oyster", "shellfish"},
    "edamame": {"edamame", "soybean", "bean"},
    "hummus": {"hummus", "chickpea"},
    "falafel": {"falafel", "chickpea"},
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
    """True if any word of the real food (or a synonym) appears in what the model said"""
    for w in _words(true_food):
        if w in predicted_words or (SYNONYMS.get(w, set()) & predicted_words):
            return True
    return False


def score_foods(true_foods, items):
    """> (found, total, list of missed foods)"""
    predicted = set()
    for item in items:
        predicted |= _words(item.get("label"))
        if item.get("usda"):
            predicted |= _words(item["usda"].get("fdc_description"))
    found = [f for f in true_foods if food_found(f, predicted)]
    missed = [f for f in true_foods if f not in found]
    return len(found), len(true_foods), missed


def summarize(rows):
    """Headline numbers from the per-photo rows"""
    s = {"photos": len(rows)}
    cal = [r for r in rows if r["true_kcal"] and r["pred_kcal"] is not None]
    if cal:
        errors = [abs(r["pred_kcal"] - r["true_kcal"]) / r["true_kcal"] for r in cal]
        s["calorie_photos"] = len(cal)
        s["mean_abs_pct_error"] = round(100 * sum(errors) / len(errors), 1)
        s["within_20pct"] = round(100 * sum(e <= 0.20 for e in errors) / len(errors), 1)
        s["within_10pct"] = round(100 * sum(e <= 0.10 for e in errors) / len(errors), 1)
    trick = [r for r in rows if r["kind"] == "not food"]
    if trick:
        s["trick_photos"] = len(trick)
        s["not_food_correct"] = round(100 * sum(r["foods_found"] for r in trick) / len(trick), 1)
    food = [r for r in rows if r["kind"] == "food" and r.get("foods_total")]
    if food:
        s["food_photos"] = len(food)
        s["food_id_accuracy"] = round(100 * sum(r["foods_found"] * 2 >= r["foods_total"] for r in food) / len(food), 1)
        s["food_recall"] = round(100 * sum(r["foods_found"] for r in food) / sum(r["foods_total"] for r in food), 1)
    return s


def write_report(path, rows, imgs, s, target, labels_path, model_id, minutes):
    """One self-contained HTML page: headline numbers, pass/fail vs target, every photo."""
    def pct(key):
        return f"{s[key]}%" if key in s else "n/a"
    ident = s.get("food_id_accuracy")
    passed = ident is not None and ident >= target
    verdict = "PASS" if passed else ("FAIL" if ident is not None else "NO FOOD LABELS")
    tiles = [("Food identification", pct("food_id_accuracy"), f"target {target}%"),
             ("Main foods found", pct("food_recall"), "of all main foods"),
             ("Calories within ±20%", pct("within_20pct"), "of photos"),
             ("Calories within ±10%", pct("within_10pct"), "of photos"),
             ("Average calorie error", pct("mean_abs_pct_error"), "lower is better")]
    if "not_food_correct" in s:
        tiles.insert(2, ("Not-food photos rejected", pct("not_food_correct"), f"{s['trick_photos']} trick photos"))
    tile_html = "".join(f'<div class="tile"><b>{v}</b><span>{html.escape(k)}</span><i>{html.escape(n)}</i></div>'
                        for k, v, n in tiles)
    body = []
    for r, img in zip(rows, imgs):
        ok = r["foods_total"] and r["foods_found"] * 2 >= r["foods_total"]
        err = r["kcal_error_pct"]
        err_cls = "good" if err is not None and abs(err) <= 20 else "bad"
        score = (("✓ no food" if ok else "✗ fooled") if r["kind"] == "not food"
                 else f'{r["foods_found"]}/{r["foods_total"]}' if r["foods_total"] else "—")
        true_kcal = "—" if r["true_kcal"] is None else f'{r["true_kcal"]:.0f}' 
        body.append(
            f'<tr><td><img src="{html.escape(img)}" loading="lazy" alt=""></td>'
            f'<td>{html.escape(r["true_foods"]) or "—"}</td>'
            f'<td>{html.escape(r["pred_foods"]) or "—"}'
            + (f'<div class="miss">missed: {html.escape(r["missed_foods"])}</div>' if r["missed_foods"] else "")
            + f'</td><td class="{"good" if ok else "bad"}">{score}</td>'
            f'<td class="num">{true_kcal}</td><td class="num">{r["pred_kcal"]}</td>'
            f'<td class="num {err_cls}">{"" if err is None else f"{err:+.0f}%"}</td></tr>')
    page = f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>BellAi Food Model Accuracy</title>
<style>
:root {{ --bg:#faf8f5; --card:#fff; --ink:#1f1d1a; --muted:#6b665f; --line:#e6e1da; --good:#2f7d4f; --bad:#b3261e; }}
@media (prefers-color-scheme: dark) {{ :root {{ --bg:#171614; --card:#211f1c; --ink:#f1ede7; --muted:#a59f96; --line:#35322d; --good:#5cc28a; --bad:#f07068; }} }}
body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 system-ui,Segoe UI,sans-serif; }}
main {{ max-width:1100px; margin:0 auto; padding:24px 16px 64px; }}
h1 {{ font-size:24px; margin:0 0 4px; }} .muted {{ color:var(--muted); font-size:13px; overflow-wrap:anywhere; }}
.verdict {{ display:inline-block; margin:16px 0 8px; padding:6px 14px; border-radius:8px; font-weight:700; color:#fff;
  background:{"var(--good)" if passed else "var(--bad)"}; }}
.tiles {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(170px,1fr)); gap:10px; margin:16px 0 24px; }}
.tile {{ background:var(--card); border:1px solid var(--line); border-radius:10px; padding:12px 14px; }}
.tile b {{ display:block; font-size:28px; font-variant-numeric:tabular-nums; }}
.tile span {{ display:block; font-weight:600; }} .tile i {{ color:var(--muted); font-style:normal; font-size:12px; }}
.wrap {{ overflow-x:auto; background:var(--card); border:1px solid var(--line); border-radius:10px; }}
table {{ width:100%; border-collapse:collapse; }} th,td {{ padding:8px 10px; border-bottom:1px solid var(--line); text-align:left; vertical-align:top; }}
th {{ font-size:12px; color:var(--muted); }} td.num {{ text-align:right; font-variant-numeric:tabular-nums; white-space:nowrap; }}
img {{ width:110px; height:82px; object-fit:cover; border-radius:6px; display:block; }}
.good {{ color:var(--good); font-weight:600; }} .bad {{ color:var(--bad); font-weight:600; }} .miss {{ color:var(--muted); font-size:12px; }}
</style></head><body><main>
<h1>BellAi Food Model Accuracy</h1>
<div class="muted">{datetime.now():%B %d, %Y %I:%M %p} · {len(rows)} photos · {html.escape(model_id)} · test set: {html.escape(str(labels_path))} · {minutes:.1f} min</div>
<div class="verdict">{verdict}: food identification {pct("food_id_accuracy")} (target ≥{target}%)</div>
<div class="tiles">{tile_html}</div>
<p class="muted">Food identification = photos where the model named at least half of the main foods
(ingredients that are at least 8% of the dish by weight). Calories are compared with the measured value;
a photo with no food found counts as 0 kcal. Trick photos (marked <code>none</code>) pass only if the model finds no food,
and are not counted in food identification or calories.</p>
<div class="wrap"><table><thead><tr><th>Photo</th><th>Actual foods</th><th>Model said</th><th>Foods</th>
<th class="num">Actual kcal</th><th class="num">Predicted</th><th class="num">Error</th></tr></thead>
<tbody>{"".join(body)}</tbody></table></div>
</main></body></html>"""
    path.write_text(page, encoding="utf-8")
    return verdict


def main():
    ap = argparse.ArgumentParser(description="Score the food model against an answer key.")
    ap.add_argument("labels_csv", help="CSV with columns image,true_kcal and optionally true_foods")
    ap.add_argument("--limit", type=int, help="only test the first N photos")
    ap.add_argument("--model", default=MODEL_ID)
    ap.add_argument("--lora", help="folder with a fine-tuned LoRA adapter")
    ap.add_argument("--target", type=float, default=90, help="food identification target in %% (default 90)")
    args = ap.parse_args()

    labels_path = Path(args.labels_csv)
    with open(labels_path, newline="", encoding="utf-8-sig") as f:  # utf-8-sig: Excel CSVs
        tests = list(csv.DictReader(f))[: args.limit]
    if not tests:
        sys.exit("No rows found in the CSV.")

    model, processor = load_model(args.model, args.lora)
    rows, imgs, start = [], [], time.perf_counter()
    for i, t in enumerate(tests, 1):
        image = Path(t["image"])
        if not image.is_absolute() and not image.exists():
            image = HERE / image  # paths in the CSV are relative to Food Model
        if not image.exists():
            print(f"[{i}/{len(tests)}] missing photo, skipped: {t['image']}")
            continue

        try:
            true_kcal = float(t.get("true_kcal") or 0) or None   # blank = calories not scored
        except ValueError:
            true_kcal = None
        raw_foods = (t.get("true_foods") or "").strip()
        if not raw_foods and not true_kcal:
            print(f"[{i}/{len(tests)}] {image.name}: not labeled yet, skipped (fill in true_foods)")
            continue

        result = analyze(model, processor, image, model_id=args.model, image_name=image.name)
        items = result["items"]
        # finding nothing (or garbled output) counts as 0 kcal - a miss
        pred = result["totals"]["kcal"] or 0
        if raw_foods.lower() in NOT_FOOD:
            kind, true_foods = "not food", []
            found, total, missed = (0 if items else 1), 1, []   # pass = model found nothing
            true_kcal = None
        else:
            kind = "food"
            true_foods = [x.strip() for x in raw_foods.split(";") if x.strip()]
            found, total, missed = score_foods(true_foods, items) if true_foods else (0, 0, [])

        row = {
            "image": t["image"],
            "kind": kind,
            "true_kcal": true_kcal,
            "pred_kcal": pred,
            "kcal_error_pct": round(100 * (pred - true_kcal) / true_kcal, 1) if true_kcal else None,
            "true_grams": t.get("true_grams", ""),
            "pred_grams": round(sum(x["grams"] for x in items), 1),
            "true_foods": "; ".join(true_foods) if kind == "food" else "(not food)",
            "pred_foods": "; ".join(f'{x["label"]} {x["grams"]}g' for x in items),
            "foods_found": found,
            "foods_total": total,
            "missed_foods": "; ".join(missed),
            "status": result["status"],
            "unmatched": "; ".join(result["unmatched_labels"]),
            "seconds": round(result["timing_ms"].get("total", 0) / 1000, 1),
        }
        rows.append(row)
        imgs.append(os.path.relpath(image.resolve(), RESULTS_DIR.resolve()).replace(os.sep, "/"))
        if kind == "not food":
            verdict = "correctly found no food" if found else f"FOOLED - said {row['pred_foods']}"
            print(f"[{i}/{len(tests)}] {image.name}: not food -> {verdict}")
        else:
            cal = (f"true {true_kcal:.0f} kcal / predicted {pred} ({row['kcal_error_pct']:+.0f}%)"
                   if true_kcal else f"predicted {pred} kcal")
            foods = f"  foods {found}/{total}" if total else ""
            print(f"[{i}/{len(tests)}] {image.name}: {cal}{foods}")

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
    if "not_food_correct" in s:
        print(f" Not-food photos:       {s['not_food_correct']}%  correctly rejected ({s['trick_photos']} trick photos)")
    if "mean_abs_pct_error" in s:
        print(f" Calories within +/-20%: {s['within_20pct']}%  of photos")
        print(f" Calories within +/-10%: {s['within_10pct']}%  of photos")
        print(f" Average calorie error: {s['mean_abs_pct_error']}%")
    partial = sum(r["status"] == "partial" for r in rows)
    if partial:
        print(f" ({partial} photos had a food with no USDA match, so their calories are likely too low)")
    report = out.with_suffix(".html")
    verdict = write_report(report, rows, imgs, s, args.target, labels_path, args.model, minutes)
    if "food_id_accuracy" in s:
        print(f" {verdict}: food identification {s['food_id_accuracy']}% vs target {args.target:g}%")
    print("=" * 52)
    print(f" Every photo's result: {out}")
    print(f" Report to show:       {report}")


if __name__ == "__main__":
    main()
