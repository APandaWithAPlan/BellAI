"""Parse simple meals like "150 g rice" or "2 eggs" without the vision model.
"""

import json
import re
import sys

WEIGHT_UNITS = {
    "g": 1, "gram": 1, "grams": 1, "gr": 1,
    "kg": 1000, "kilogram": 1000, "kilograms": 1000,
    "oz": 28.35, "ounce": 28.35, "ounces": 28.35,
    "lb": 453.6, "lbs": 453.6, "pound": 453.6, "pounds": 453.6,
}

# household units -> canonical name
OTHER_UNITS = {
    "cup": "cup", "cups": "cup",
    "tbsp": "tbsp", "tablespoon": "tbsp", "tablespoons": "tbsp",
    "tsp": "tsp", "teaspoon": "tsp", "teaspoons": "tsp",
    "slice": "slice", "slices": "slice",
    "piece": "each", "pieces": "each",
    "can": "can", "cans": "can",
    "bowl": "bowl", "bowls": "bowl",
    "glass": "cup", "glasses": "cup",
}

NUMBER_WORDS = {
    "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
    "seven": 7, "eight": 8, "nine": 9, "ten": 10, "half": 0.5, "a half": 0.5,
    "a couple": 2, "a couple of": 2, "couple": 2, "dozen": 12, "a dozen": 12,
}

# food keyword -> (type, USDA search text, {unit: grams})
PORTIONS = {
    "egg":            ("protein",   "egg, whole, cooked",          {"each": 50}),
    "banana":         ("fruit",     "banana, raw",                 {"each": 118}),
    "apple":          ("fruit",     "apple, raw",                  {"each": 182}),
    "orange":         ("fruit",     "orange, raw",                 {"each": 131}),
    "avocado":        ("fruit",     "avocado, raw",                {"each": 136}),
    "strawberry":     ("fruit",     "strawberries, raw",           {"cup": 152, "each": 12}),
    "blueberry":      ("fruit",     "blueberries, raw",            {"cup": 148}),
    "grape":          ("fruit",     "grapes, raw",                 {"cup": 151, "each": 5}),
    "carrot":         ("vegetable", "carrots, raw",                {"each": 61, "cup": 128}),
    "broccoli":       ("vegetable", "broccoli, cooked",            {"cup": 156}),
    "potato":         ("vegetable", "potato, baked",               {"each": 173}),
    "toast":          ("grain",     "bread, white, toasted",       {"slice": 25, "each": 25}),
    "bread":          ("grain",     "bread, white",                {"slice": 28, "each": 28}),
    "bagel":          ("grain",     "bagel, plain",                {"each": 105}),
    "tortilla":       ("grain",     "tortilla, flour",             {"each": 45}),
    "rice":           ("grain",     "rice, white, cooked",         {"cup": 158, "bowl": 240}),
    "pasta":          ("grain",     "pasta, cooked",               {"cup": 140, "bowl": 280}),
    "spaghetti":      ("grain",     "spaghetti, cooked",           {"cup": 140, "bowl": 280}),
    "oatmeal":        ("grain",     "oatmeal, cooked",             {"cup": 234, "bowl": 234}),
    "cereal":         ("grain",     "cereal, ready-to-eat",        {"cup": 30, "bowl": 40}),
    "chicken breast": ("protein",   "chicken breast, roasted",     {"each": 172}),
    "bacon":          ("protein",   "bacon, cooked",               {"slice": 8, "each": 8}),
    "milk":           ("dairy",     "milk, 2%",                    {"cup": 244}),
    "yogurt":         ("dairy",     "yogurt, plain",               {"cup": 245, "each": 170}),
    "cheese":         ("dairy",     "cheese, cheddar",             {"slice": 21, "each": 21}),
    "peanut butter":  ("fat_oil",   "peanut butter",               {"tbsp": 16, "tsp": 5}),
    "butter":         ("fat_oil",   "butter",                      {"tbsp": 14, "tsp": 5}),
    "olive oil":      ("fat_oil",   "olive oil",                   {"tbsp": 13.5, "tsp": 4.5}),
    "pizza":          ("mixed_dish","pizza, cheese",               {"slice": 107}),
    "donut":          ("sweet",     "doughnut, glazed",            {"each": 60}),
    "coffee":         ("beverage",  "coffee, brewed",              {"cup": 237}),
    "orange juice":   ("beverage",  "orange juice",                {"cup": 248, "each": 248}),
    "soda":           ("beverage",  "soft drink, cola",            {"can": 368, "cup": 248, "each": 368}),
    "beer":           ("beverage",  "beer",                        {"can": 356, "each": 356}),
}

# for weight-only foods we don't know: guess the type from the USDA
CATEGORY_TYPES = [
    (("fruit",), "fruit"),
    (("vegetable",), "vegetable"),
    (("cereal", "grain", "bread", "rice", "pasta", "baked"), "grain"),
    (("poultry", "chicken", "beef", "pork", "fish", "seafood", "egg", "legume", "sausage", "meat", "turkey"), "protein"),
    (("dairy", "milk", "cheese", "yogurt"), "dairy"),
    (("fats and oils", "oil", "butter"), "fat_oil"),
    (("sweet", "dessert", "candy", "cookie", "cake", "ice cream"), "sweet"),
    (("snack", "chip", "cracker"), "snack"),
    (("beverage", "drink", "juice", "coffee", "tea", "soda", "water"), "beverage"),
    (("pizza", "sandwich", "burrito", "taco", "mixed", "entree", "soup"), "mixed_dish"),
    (("condiment", "sauce", "dressing", "spread"), "condiment"),
]

SIZE_WORDS_RE = re.compile(r"\b(?:big|large|small|huge|giant|jumbo|mini|extra|double|triple|heaping|tiny)\b")
SPLIT_RE = re.compile(r"\s*(?:,|\+|;|\band\b|\bwith\b|\bplus\b|&)\s*")
FILLER_RE = re.compile(r"^(?:i\s+(?:had|ate|drank|just\s+had|just\s+ate)|for\s+\w+\s+i\s+had|had|ate)\s+", re.I)


def type_from_category(category):
    text = (category or "").lower()
    for words, food_type in CATEGORY_TYPES:
        if any(w in text for w in words):
            return food_type
    return "other"


def _singular(word):
    if word.endswith("ies") and len(word) > 4:
        return word[:-3] + "y"
    if word.endswith(("ches", "shes", "oes")):
        return word[:-2]
    if word.endswith("s") and not word.endswith("ss"):
        return word[:-1]
    return word


def _read_number(text):
    """Leading amount -> (number, rest of text)"""
    m = re.match(r"^(\d+(?:\.\d+)?)\s*/\s*(\d+)\s*(.*)$", text)  # 1/2
    if m:
        return float(m.group(1)) / float(m.group(2)), m.group(3)
    m = re.match(r"^(\d+(?:\.\d+)?)\s*(.*)$", text)  # 2, 1.5, 150g
    if m:
        return float(m.group(1)), m.group(2)
    for words in sorted(NUMBER_WORDS, key=len, reverse=True):  # "a couple of" before "a"
        if text == words or text.startswith(words + " "):
            return NUMBER_WORDS[words], text[len(words):].strip()
    return None, text


def _find_food(name):
    """Match a food name to a PORTIONS key"""
    words = [_singular(w) for w in re.findall(r"[a-z]+", name)]
    joined = " ".join(words)
    for key in sorted(PORTIONS, key=len, reverse=True):
        if re.search(rf"\b{re.escape(key)}\b", joined):
            return key
    return None


def parse_part(part):
    """One food phrase -> {"label", "grams", "type", "usda_query"} or None if unsure"""
    text = FILLER_RE.sub("", part.lower().strip(" .!?"))
    if not text:
        return None
    qty, rest = _read_number(text)
    if qty is None or qty <= 0:
        return None  # "some rice" - let the model guess
    rest = rest.strip()

    unit_word = None
    m = re.match(r"^([a-z]+)\b\.?\s*(?:of\s+)?(.*)$", rest)
    if m and (m.group(1) in WEIGHT_UNITS or m.group(1) in OTHER_UNITS):
        unit_word, rest = m.group(1), m.group(2)
    name = re.sub(r"^(?:of\s+)?(?:(?:a|an|the)\s+)?", "", rest).strip()
    if not name or len(name) > 60:
        return None

    if SIZE_WORDS_RE.search(name):
        return None  # "a big banana" - let the model judge the size
    key = _find_food(name)
    label = re.sub(r"\s+", " ", name)
    # bare food name ("rice", "eggs") -> our USDA search text
    bare = bool(key) and (_singular(label) == key or label == key)

    if unit_word in WEIGHT_UNITS:  # any food with a weight works
        grams = qty * WEIGHT_UNITS[unit_word]
        food_type = PORTIONS[key][0] if key else None  # filled from USDA category later
        query = PORTIONS[key][1] if bare else label
    else:
        if not key:
            return None  # "2 burritos" - unknown size, use the model
        food_type, default_query, units = PORTIONS[key]
        unit = OTHER_UNITS.get(unit_word, "each") if unit_word else "each"
        if unit not in units:
            return None  # "a cup of eggs" - not a known portion
        grams = qty * units[unit]
        query = default_query if bare else label

    if grams <= 0 or grams > 3000:
        return None
    return {"label": label, "grams": round(grams, 1), "type": food_type, "usda_query": query}


def parse(text):
    """Whole message -> list of parsed foods, or None if any part needs the AI model"""
    text = (text or "").strip()
    if not text or len(text) > 300:
        return None
    parts = [p for p in SPLIT_RE.split(FILLER_RE.sub("", text.lower())) if p and p.strip()]
    if not parts or len(parts) > 10:
        return None
    foods = []
    for part in parts:
        food = parse_part(part)
        if food is None:
            return None
        foods.append(food)
    return foods


if __name__ == "__main__":
    print(json.dumps(parse(" ".join(sys.argv[1:])), indent=2))
