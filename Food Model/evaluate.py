"""
evaluate.py - measure how close the calorie estimates are to the real numbers.

You need a CSV of test photos with known calories, e.g. eval_data/labels.csv:
    image,true_kcal
    eval_data/dish_001.png,412
    eval_data/dish_002.png,655

(Nutrition5k is the best public source: its overhead dish photos come with measured
calories. Your own meals work too if you weigh the food and look it up.)

Run (from the Food Model folder):
    python evaluate.py eval_data/labels.csv
    python evaluate.py eval_data/labels.csv --limit 50

It prints the numbers for the acceptance criteria:
  - mean absolute % error of total calories
  - share of photos within +/-20% of the true calories
and writes every prediction to results/eval_<time>.csv.
"""

import argparse
import csv
import sys
from datetime import datetime
from pathlib import Path

from analyze_food import MODEL_ID, RESULTS_DIR, analyze, load_model

TOLERANCE = 0.20  # "within 20%" target from the user story


def summarize(rows):
    """rows: list of dicts with true_kcal and pred_kcal. Returns the headline numbers."""
    scored = [r for r in rows if r["true_kcal"] > 0 and r["pred_kcal"] is not None]
    if not scored:
        return {"photos": 0}
    errors = [abs(r["pred_kcal"] - r["true_kcal"]) / r["true_kcal"] for r in scored]
    return {
        "photos": len(scored),
        "mean_abs_pct_error": round(100 * sum(errors) / len(errors), 1),
        "within_20pct": round(100 * sum(e <= TOLERANCE for e in errors) / len(errors), 1),
    }


def main():
    ap = argparse.ArgumentParser(description="Score calorie estimates against known values.")
    ap.add_argument("labels_csv", help="CSV with columns image,true_kcal")
    ap.add_argument("--limit", type=int, help="only test the first N photos")
    ap.add_argument("--model", default=MODEL_ID)
    ap.add_argument("--lora", help="folder with a fine-tuned LoRA adapter")
    args = ap.parse_args()

    with open(args.labels_csv, newline="", encoding="utf-8") as f:
        tests = list(csv.DictReader(f))[: args.limit]
    if not tests:
        sys.exit("No rows found in the CSV.")

    model, processor = load_model(args.model, args.lora)
    rows = []
    for i, t in enumerate(tests, 1):
        result = analyze(model, processor, t["image"], model_id=args.model, image_name=t["image"])
        pred = result["totals"]["kcal"] if result["status"] == "ok" else None
        rows.append({
            "image": t["image"],
            "true_kcal": float(t["true_kcal"]),
            "pred_kcal": pred,
            "labels": "; ".join(f'{x["label"]} {x["grams"]}g' for x in result["items"]),
            "unmatched": "; ".join(result["unmatched_labels"]),
        })
        print(f"[{i}/{len(tests)}] {t['image']}: true {t['true_kcal']} / predicted {pred}")

    RESULTS_DIR.mkdir(exist_ok=True)
    out = RESULTS_DIR / f"eval_{datetime.now():%Y%m%d_%H%M%S}.csv"
    with open(out, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    s = summarize(rows)
    skipped = len(rows) - s["photos"]
    print("\n=== Results ===")
    if s["photos"]:
        print(f"Photos scored:            {s['photos']}  (skipped {skipped} with unmatched foods)")
        print(f"Mean abs. calorie error:  {s['mean_abs_pct_error']}%")
        print(f"Within +/-20% of truth:   {s['within_20pct']}%")
    else:
        print("No photos could be scored.")
    print(f"Details: {out}")


if __name__ == "__main__":
    main()
