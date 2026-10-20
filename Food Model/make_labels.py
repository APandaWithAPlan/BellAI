"""Make a labels.csv for your own test photos, ready to fill in.

Usage:
    python make_labels.py                       uses eval_data/my_photos
    python make_labels.py eval_data/other_folder

1. Put photos (jpg, jpeg, png, webp) in the folder: real meals, messy plates, takeout,
   and trick photos with no food (your pet, a keyboard, a toy, a picture of food on a screen).
2. Run this. It lists every photo in labels.csv and keeps anything you already filled in.
3. Open labels.csv in Excel or a text editor and fill in:
     true_foods  what's really there, separated by ";"   e.g.  rice; chicken; broccoli
                 or  none  for a photo with no food
     true_kcal   real calories if you know them (weighed or from the label); leave blank if not
4. Run:  python evaluate.py eval_data/my_photos/labels.csv
"""

import csv
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PHOTO_TYPES = {".jpg", ".jpeg", ".png", ".webp"}
COLUMNS = ["image", "true_foods", "true_kcal"]


def main():
    folder = (HERE / (sys.argv[1] if len(sys.argv) > 1 else "eval_data/my_photos")).resolve()
    folder.mkdir(parents=True, exist_ok=True)
    labels = folder / "labels.csv"

    existing = {}
    if labels.exists():
        with open(labels, newline="", encoding="utf-8-sig") as f:
            for row in csv.DictReader(f):
                existing[row.get("image", "")] = row

    photos = sorted(p for p in folder.iterdir() if p.suffix.lower() in PHOTO_TYPES)
    if not photos:
        print(f"No photos in {folder} yet. Add some (jpg/png/webp) and run this again.")
        return

    rows, new = [], 0
    for p in photos:
        key = p.relative_to(HERE).as_posix()
        if key in existing:
            rows.append({c: existing[key].get(c, "") for c in COLUMNS})
        else:
            rows.append({"image": key, "true_foods": "", "true_kcal": ""})
            new += 1

    with open(labels, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=COLUMNS)
        writer.writeheader()
        writer.writerows(rows)

    blank = sum(1 for r in rows if not r["true_foods"].strip())
    print(f"{labels}: {len(rows)} photos ({new} new).")
    if blank:
        print(f"Fill in true_foods for {blank} photo(s) - foods separated by ';', or 'none' if there's no food.")
    print(f"Then run:  python evaluate.py {labels.relative_to(HERE).as_posix()}")


if __name__ == "__main__":
    main()
