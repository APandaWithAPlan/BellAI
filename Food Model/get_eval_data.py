"""
get_eval_data.py - download a ready-made accuracy test set from Nutrition5k.

Nutrition5k (Google Research, CC BY 4.0) has overhead photos of real cafeteria meals,
each with lab-measured calories and the weight of every ingredient. This script
downloads a random sample from its official TEST split and writes the answer key.

Run once (from the Food Model folder, with the .venv active; needs internet):
    python get_eval_data.py                  50 dishes (default)
    python get_eval_data.py --count 100      more dishes = a more reliable accuracy number

It creates:
    eval_data/nutrition5k/dish_XXXX.png      the photos
    eval_data/nutrition5k/labels.csv         answer key: image, true_kcal, true_grams, true_foods
    eval_data/nutrition5k/SOURCE.txt         dataset credit

Then score the model (stop server.py first - both need the GPU):
    python evaluate.py eval_data/nutrition5k/labels.csv
"""

import argparse
import csv
import random
import sys
from pathlib import Path

import requests

HERE = Path(__file__).resolve().parent
BASE = "https://storage.googleapis.com/nutrition5k_dataset/nutrition5k_dataset"
METADATA = [f"{BASE}/metadata/dish_metadata_cafe1.csv", f"{BASE}/metadata/dish_metadata_cafe2.csv"]
SPLIT = f"{BASE}/dish_ids/splits/rgb_test_ids.txt"
PHOTO = BASE + "/imagery/realsense_overhead/{dish}/rgb.png"

DISH_FIELDS = 6         # dish_id, total_calories, total_mass, total_fat, total_carb, total_protein
INGREDIENT_FIELDS = 7   # ingr_id, name, grams, calories, fat, carb, protein

# An ingredient counts as a "main food" the model should be able to see if it is at least
# this share of the dish's weight (oil, salt and spices are left out - nobody can see those).
MAIN_FOOD_SHARE = 0.08
MAIN_FOOD_MIN_GRAMS = 10


def fetch(url, session, binary=False):
    resp = session.get(url, timeout=60)
    if resp.status_code == 404:
        return None
    resp.raise_for_status()
    return resp.content if binary else resp.text


def parse_metadata(text):
    """CSV text -> {dish_id: {"kcal", "grams", "ingredients": [(name, grams), ...]}}"""
    dishes = {}
    for row in csv.reader(text.splitlines()):
        if len(row) < DISH_FIELDS or not row[0].startswith("dish_"):
            continue
        try:
            kcal, grams = float(row[1]), float(row[2])
        except ValueError:
            continue
        ingredients = []
        rest = row[DISH_FIELDS:]
        for i in range(0, len(rest) - INGREDIENT_FIELDS + 1, INGREDIENT_FIELDS):
            name, ing_grams = rest[i + 1].strip(), rest[i + 2]
            try:
                ingredients.append((name, float(ing_grams)))
            except ValueError:
                pass
        dishes[row[0]] = {"kcal": kcal, "grams": grams, "ingredients": ingredients}
    return dishes


def main_foods(dish):
    """The visible ingredients: big enough share of the dish, merged by name, heaviest first."""
    merged = {}
    for name, grams in dish["ingredients"]:
        merged[name] = merged.get(name, 0) + grams
    threshold = max(MAIN_FOOD_MIN_GRAMS, MAIN_FOOD_SHARE * dish["grams"])
    foods = [n for n, g in sorted(merged.items(), key=lambda x: -x[1]) if g >= threshold]
    if not foods and merged:                      # always keep at least the heaviest one
        foods = [max(merged, key=merged.get)]
    return foods


def main():
    ap = argparse.ArgumentParser(description="Download a Nutrition5k accuracy test set.")
    ap.add_argument("--count", type=int, default=50, help="how many dishes (default 50)")
    ap.add_argument("--out", default="eval_data/nutrition5k")
    ap.add_argument("--seed", type=int, default=7, help="random seed, so the same dishes come back each time")
    args = ap.parse_args()

    out = (HERE / args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    session = requests.Session()

    print("Downloading the answer key (dish metadata) ...")
    dishes = {}
    for url in METADATA:
        text = fetch(url, session)
        if text is None:
            sys.exit(f"Couldn't download {url}")
        dishes.update(parse_metadata(text))
    print(f"  {len(dishes)} dishes with measured nutrition")

    split = fetch(SPLIT, session)
    if split is None:
        sys.exit(f"Couldn't download {SPLIT}")
    ids = [d.strip() for d in split.splitlines() if d.strip() in dishes]
    ids = [d for d in ids if dishes[d]["kcal"] > 0 and dishes[d]["grams"] > 0]
    random.Random(args.seed).shuffle(ids)
    print(f"  {len(ids)} usable dishes in the test split; downloading {args.count} photos ...")

    rows, missing = [], 0
    for dish_id in ids:
        if len(rows) >= args.count:
            break
        path = out / f"{dish_id}.png"
        if not path.exists():
            data = fetch(PHOTO.format(dish=dish_id), session, binary=True)
            if not data:
                missing += 1
                continue
            path.write_bytes(data)
        dish = dishes[dish_id]
        rows.append({
            "image": path.relative_to(HERE).as_posix(),
            "true_kcal": round(dish["kcal"], 1),
            "true_grams": round(dish["grams"], 1),
            "true_foods": "; ".join(main_foods(dish)),
            "dish_id": dish_id,
        })
        print(f"  [{len(rows)}/{args.count}] {dish_id}: {rows[-1]['true_kcal']} kcal - {rows[-1]['true_foods']}")

    if not rows:
        sys.exit("No photos could be downloaded. Check your internet connection and try again.")

    labels = out / "labels.csv"
    with open(labels, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    (out / "SOURCE.txt").write_text(
        "Photos and nutrition values from Nutrition5k (Google Research), licensed CC BY 4.0.\n"
        "Thames et al., 'Nutrition5k: Towards Automatic Nutritional Understanding of Generic Food', CVPR 2021.\n"
        "https://github.com/google-research-datasets/Nutrition5k\n"
        f"Sample: {len(rows)} dishes from the official RGB test split, random seed {args.seed}.\n",
        encoding="utf-8")

    print(f"\nSaved {len(rows)} photos and the answer key to {labels}")
    if missing:
        print(f"({missing} dishes skipped because they have no overhead photo)")
    print("\nNext: stop server.py if it's running, then run")
    print(f"    python evaluate.py {labels.relative_to(HERE).as_posix()}")


if __name__ == "__main__":
    main()
