"""
analyze_food.py - turn a food photo OR a typed description into food labels plus nutrition, as JSON.

Run (from the Food Model folder, with the .venv active):
    python analyze_food.py photos/lunch.jpg
    python analyze_food.py photos/lunch.jpg --note "half portion, fried in butter"
    python analyze_food.py --text "2 eggs and a slice of toast"
    python analyze_food.py --text "a big bowl of chicken alfredo"

For the website/app, run server.py instead - it uses the same code behind a web API.

How it works
  Photo:  Qwen2.5-VL looks at the photo (plus an optional note) and lists each food
          with a type and an estimated weight in grams.
  Text:   FAST PATH first (quick_parse.py): simple text like "2 eggs and toast" or
          "150 g rice" is understood without the AI model, in well under a second.
          If any part is vague ("a big bowl of pasta", "some fries") the AI model handles it.
  Both:   Labels are sanitized, matched to USDA FoodData Central (nutrition.py), and
          calories/protein/carbs/fat/fiber/sugar/sodium = grams x USDA values per gram.
          The model never makes up nutrition numbers.

The first model run downloads the model (about 16 GB) into your Hugging Face cache.

Options
    --model Qwen/Qwen2.5-VL-3B-Instruct   smaller, faster, less accurate (default is 7B)
    --lora food_lora                      use a fine-tuned adapter once you've trained one
"""

import argparse
import json
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import quick_parse
from nutrition import NUTRIENT_KEYS, clean_label, lookup, scale

HERE = Path(__file__).resolve().parent
RESULTS_DIR = HERE / "results"
MODEL_ID = "Qwen/Qwen2.5-VL-7B-Instruct"

# Image size the model sees (Qwen works in 28x28 patches). Bigger = more detail but more VRAM.
MIN_PIXELS = 256 * 28 * 28
MAX_PIXELS = 1024 * 28 * 28

MAX_GRAMS = 3000      # anything bigger than 3 kg for one item is treated as a model mistake
MAX_TEXT_CHARS = 500  # longest typed description accepted

# The only food types the API will ever return; anything else becomes "other"
FOOD_TYPES = ["fruit", "vegetable", "grain", "protein", "dairy", "fat_oil", "sweet",
              "snack", "beverage", "mixed_dish", "condiment", "other"]

SYSTEM_PROMPT = (
    "You are BellAi's nutrition assistant. You identify foods and drinks from photos or "
    "descriptions and estimate how much of each there is. You always answer with JSON only."
)

ITEM_RULES = """For each one give:
- "name": a plain, generic food name as it would appear in a nutrition database, including how it was cooked if known (for example "white rice, cooked", "chicken breast, grilled", "broccoli, steamed"). No brand names.
- "type": exactly one of: """ + ", ".join(FOOD_TYPES) + """. Use "mixed_dish" for things like pizza, burritos, lasagna or salads with many ingredients.
- "grams": {grams_rule}
- "confidence": a number from 0 to 1 for how sure you are about the name.

Reply with JSON only, in exactly this shape:
{{"items": [{{"name": "...", "type": "...", "grams": 0, "confidence": 0.0}}]}}
If there is no food or drink, reply {{"items": []}}."""

PHOTO_PROMPT = "Look at this photo and list every distinct food or drink you can see.\n" + ITEM_RULES.format(
    grams_rule="your best estimate of the edible weight in grams. Use the plate, bowl, utensils, "
               "hands or packaging for scale.")

TEXT_PROMPT = ("The user described what they ate or drank. List every distinct food or drink in "
               "their description. Split combined meals into parts when they name them "
               "(\"burger and fries\" is two items).\n" + ITEM_RULES.format(
                   grams_rule="the edible weight in grams. Use the amount they give; if they don't "
                              "give one, use a typical single US serving. Adjust for words like "
                              "\"big\", \"small\", \"half\" or \"two\"."))


class ModelNotLoaded(Exception):
    """Text was too vague for the fast path, and the AI model isn't loaded (yet)."""


# ---------------------------------------------------------------- model

def load_model(model_id=MODEL_ID, lora_dir=None):
    """Load Qwen2.5-VL onto the GPU in bfloat16 (7B needs about 17 GB of VRAM)."""
    import torch
    from transformers import AutoProcessor, Qwen2_5_VLForConditionalGeneration

    if not torch.cuda.is_available():
        print("Warning: no CUDA GPU found - this will be extremely slow on CPU.", file=sys.stderr)
    else:
        check_gpu_memory(model_id)

    model =Qwen2_5_VLForConditionalGeneration.from_pretrained(
        model_id, torch_dtype=torch.bfloat16, device_map="auto", attn_implementation="sdpa"
    )
    if lora_dir:
        from peft import PeftModel
        model = PeftModel.from_pretrained(model, str(lora_dir))
    model.eval()
    processor = AutoProcessor.from_pretrained(model_id, min_pixels=MIN_PIXELS, max_pixels=MAX_PIXELS)
    return model, processor


def open_image(image):
    """Accept a file path or an already-open PIL image; return an upright RGB image."""
    from PIL import Image, ImageOps
    if not isinstance(image, Image.Image):
        image = Image.open(image)
    # exif_transpose fixes phone photos that would otherwise appear sideways
    return ImageOps.exif_transpose(image).convert("RGB")


def ask_model(model, processor, image=None, note=None, text=None, max_new_tokens=768):
    """
    Ask the model about a photo (path or PIL image, with an optional note) or a typed
    description (text, no image). Returns the model's raw text answer.
    """
    import torch
    from qwen_vl_utils import process_vision_info

    if image is not None:
        prompt = PHOTO_PROMPT
        if note:
            prompt += f"\n\nExtra details from the person who took the photo: {note.strip()[:300]}"
        content = [{"type": "image", "image": open_image(image)}, {"type": "text", "text": prompt}]
    else:
        prompt = TEXT_PROMPT + f"\n\nWhat the user said:\n\"\"\"{(text or '').strip()[:MAX_TEXT_CHARS]}\"\"\""
        content = [{"type": "text", "text": prompt}]

    messages = [
        {"role": "system", "content": [{"type": "text", "text": SYSTEM_PROMPT}]},
        {"role": "user", "content": content},
    ]
    chat = processor.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
    image_inputs, video_inputs = process_vision_info(messages)
    inputs = processor(text=[chat], images=image_inputs, videos=video_inputs,
                       padding=True, return_tensors="pt").to(model.device)

    with torch.inference_mode():
        out = model.generate(**inputs, max_new_tokens=max_new_tokens, do_sample=False)
    new_tokens = out[:, inputs.input_ids.shape[1]:]
    return processor.batch_decode(new_tokens, skip_special_tokens=True)[0]


# ---------------------------------------------------------------- parsing + sanitizing

def parse_model_json(text):
    """Pull the JSON object out of the model's reply (handles ```json fences and chatter)."""
    text = re.sub(r"```(?:json)?", "", text or "")
    start, end = text.find("{"), text.rfind("}")
    if start == -1 or end <= start:
        return None
    try:
        return json.loads(text[start:end + 1])
    except json.JSONDecodeError:
        return None


def _to_float(value, default=None):
    try:
        return float(str(value).lower().replace("g", "").strip())
    except (TypeError, ValueError):
        return default


def _food_type(value):
    value = re.sub(r"[^a-z_]", "_", str(value or "").lower().strip()).strip("_")
    return value if value in FOOD_TYPES else "other"


def sanitize_items(parsed):
    """Keep only well-formed items: clean label, known type, grams in 1..MAX_GRAMS, confidence 0..1."""
    items = parsed.get("items", []) if isinstance(parsed, dict) else []
    clean = []
    for item in items if isinstance(items, list) else []:
        if not isinstance(item, dict):
            continue
        label = clean_label(item.get("name") or item.get("label"))
        grams = _to_float(item.get("grams"))
        if not label or grams is None or grams <= 0:
            continue
        confidence = _to_float(item.get("confidence"), 0.5)
        clean.append({
            "label": label,
            "type": _food_type(item.get("type")),
            "grams": round(min(grams, MAX_GRAMS), 1),
            "confidence": round(max(0.0, min(confidence, 1.0)), 2),
        })
    return clean


def add_nutrition(items):
    """Attach the USDA match and scaled nutrition to each item. Returns (items, unmatched_labels)."""
    unmatched = []
    for item in items:
        query = item.pop("usda_query", None) or item["label"]
        match = None
        try:
            match = lookup(query)
        except Exception as e:  # network/API problem - keep going, flag the item
            item["lookup_error"] = str(e)[:200]
        if match and match.get("per_100g"):
            item["usda"] = {k: match.get(k) for k in ("fdc_id", "fdc_description", "usda_category")}
            item["nutrition"] = scale(match["per_100g"], item["grams"])
            if not item.get("type"):
                item["type"] = quick_parse.type_from_category(match.get("usda_category"))
        else:
            item["usda"] = None
            item["nutrition"] = scale(None, item["grams"])
            item["type"] = item.get("type") or "other"
            unmatched.append(item["label"])
    return items, unmatched


def totals(items):
    """Sum each nutrient over the matched items (None-valued nutrients are skipped)."""
    out = {}
    for key in NUTRIENT_KEYS:
        values = [i["nutrition"][key] for i in items if i["nutrition"][key] is not None]
        if not values:
            out[key] = None
            continue
        total = sum(values)
        out[key] = round(total) if key in ("kcal", "sodium_mg") else round(total, 1)
    return out


def make_summary(items, total, status):
    """One friendly sentence for the chat bubble and for BellAi to say out loud."""
    if status == "unparseable_model_output":
        return "Sorry, I couldn't work out what that was. Could you try again?"
    if not items:
        return "I couldn't find any food or drink in that."
    names = [i["label"].split(",")[0] for i in items]
    foods = names[0] if len(names) == 1 else ", ".join(names[:-1]) + " and " + names[-1]
    if total.get("kcal") is None:
        return f"That looks like {foods}, but I couldn't find its nutrition info."
    parts = [f"about {total['kcal']} calories"]
    for key, word in (("protein_g", "protein"), ("carbs_g", "carbs"), ("fat_g", "fat")):
        if total.get(key) is not None:
            parts.append(f"{round(total[key])} g {word}")
    sentence = f"That looks like {foods}: " + ", ".join(parts[:-1]) + " and " + parts[-1] + "." \
        if len(parts) > 1 else f"That looks like {foods}: {parts[0]}."
    if status == "partial":
        sentence += " Some items couldn't be matched, so the real total is a bit higher."
    return sentence


def finish_result(items, unmatched, *, parsed_ok, input_kind, source, model_id, note=None,
                  text=None, image_name=None, raw_text=None, timing=None):
    """Everything the backend needs, in one JSON-ready dict."""
    if not parsed_ok:
        status = "unparseable_model_output"
    elif not items:
        status = "no_food_found"
    elif unmatched:
        status = "partial"        # some foods had no USDA match; totals exclude them
    else:
        status = "ok"
    total = totals(items)
    return {
        "type": "food",
        "status": status,
        "summary": make_summary(items, total, status),
        "input": input_kind,                        # "image" or "text"
        "source": source,                           # "model" or "quick_parse"
        "image": Path(str(image_name)).name if image_name else None,
        "text": text,
        "note": note,
        "model": model_id if source == "model" else None,
        "items": items,
        "totals": total,
        "unmatched_labels": unmatched,
        "raw_model_output": None if parsed_ok else (raw_text or "")[:2000],
        "timing_ms": timing or {},
        "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }


def build_result(image_name, raw_text, model_id, note=None, text=None, timing=None):
    """Model answer -> result dict (used for both photo and text requests that went to the model)."""
    t0 = time.perf_counter()
    parsed = parse_model_json(raw_text)
    items, unmatched = add_nutrition(sanitize_items(parsed))
    timing = dict(timing or {})
    timing["nutrition"] = round((time.perf_counter() - t0) * 1000)
    return finish_result(items, unmatched, parsed_ok=parsed is not None,
                         input_kind="image" if image_name else "text", source="model",
                         model_id=model_id, note=note, text=text, image_name=image_name,
                         raw_text=raw_text, timing=timing)


# ---------------------------------------------------------------- entry points

def analyze(model, processor, image, note=None, model_id=MODEL_ID, image_name=None):
    """Photo (path or PIL image) -> result dict."""
    t0 = time.perf_counter()
    raw = ask_model(model, processor, image=image, note=note)
    model_ms = round((time.perf_counter() - t0) * 1000)
    name = image_name or getattr(image, "name", None) or str(image)
    result = build_result(name, raw, model_id, note=note, timing={"model": model_ms})
    result["timing_ms"]["total"] = round((time.perf_counter() - t0) * 1000)
    return result


def try_quick_path(text):
    """Fast path for simple text. Returns a finished result, or None if the model is needed."""
    t0 = time.perf_counter()
    foods = quick_parse.parse(text)
    if not foods:
        return None
    items = [{"label": clean_label(f["label"]), "type": f["type"], "grams": f["grams"],
              "confidence": 1.0, "usda_query": f["usda_query"]} for f in foods]
    items, unmatched = add_nutrition(items)
    if unmatched or any("lookup_error" in i for i in items):
        return None        # let the model rephrase foods USDA didn't recognise
    ms = round((time.perf_counter() - t0) * 1000)
    return finish_result(items, unmatched, parsed_ok=True, input_kind="text", source="quick_parse",
                         model_id=None, text=text, timing={"quick_parse": ms, "total": ms})


def analyze_text(model, processor, text, model_id=MODEL_ID, get_model_lock=None):
    """
    Typed description -> result dict. Tries the fast path first; uses the model only if needed.
    get_model_lock: optional context manager (the server's GPU lock) taken only for the model.
    """
    text = (text or "").strip()[:MAX_TEXT_CHARS]
    t0 = time.perf_counter()
    quick = try_quick_path(text)
    if quick:
        return quick
    tried_ms = round((time.perf_counter() - t0) * 1000)

    if model is None:
        raise ModelNotLoaded("The AI model isn't loaded, and the text was too vague for the fast path.")
    t1 = time.perf_counter()
    if get_model_lock is not None:
        with get_model_lock:
            raw = ask_model(model, processor, text=text)
    else:
        raw = ask_model(model, processor, text=text)
    model_ms = round((time.perf_counter() - t1) * 1000)
    result = build_result(None, raw, model_id, text=text,
                          timing={"quick_parse": tried_ms, "model": model_ms})
    result["timing_ms"]["total"] = round((time.perf_counter() - t0) * 1000)
    return result


# ---------------------------------------------------------------- command line

def main():
    ap = argparse.ArgumentParser(description="Estimate foods and nutrition from a photo or a description.")
    ap.add_argument("image", nargs="?", help="path to a food photo (jpg/png)")
    ap.add_argument("--text", help='describe the meal instead of a photo, e.g. "2 eggs and toast"')
    ap.add_argument("--note", help='extra context for a photo, e.g. "half portion" or "cooked in oil"')
    ap.add_argument("--out", help="where to save the JSON (default: results/<photo or 'text'>.json)")
    ap.add_argument("--model", default=MODEL_ID)
    ap.add_argument("--lora", help="folder with a fine-tuned LoRA adapter")
    args = ap.parse_args()

    if not args.image and not args.text:
        ap.error("give a photo path or --text")

    if args.text and not args.image:
        result = try_quick_path(args.text)
        if result is None:
            print(f"Loading {args.model} ...", file=sys.stderr)
            model, processor = load_model(args.model, args.lora)
            result = analyze_text(model, processor, args.text, args.model)
        stem = "text"
    else:
        image_path = Path(args.image)
        if not image_path.is_file():
            sys.exit(f"Can't find the photo: {image_path}")
        print(f"Loading {args.model} ...", file=sys.stderr)
        model, processor = load_model(args.model, args.lora)
        result = analyze(model, processor, image_path, args.note or args.text, args.model, image_path.name)
        stem = image_path.stem

    out = Path(args.out) if args.out else RESULTS_DIR / f"{stem}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    print(f"\nSaved to {out}", file=sys.stderr)


if __name__ == "__main__":
    main()
