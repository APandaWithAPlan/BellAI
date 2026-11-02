# Removes model suggestions that break the user's allergies, diet, calories or injuries.

import re

# allergen -> words that mean it is present
ALLERGENS = {
    "peanut": ["peanut", "satay", "groundnut"],
    "tree nut": ["almond", "walnut", "cashew", "pecan", "pistachio", "hazelnut", "macadamia", "nut butter", "pesto"],
    "nut": ["peanut", "almond", "walnut", "cashew", "pecan", "pistachio", "hazelnut", "macadamia", "nut butter", "pesto"],
    "dairy": ["milk", "cheese", "yogurt", "butter", "cream", "whey", "casein", "ghee", "kefir", "cottage"],
    "milk": ["milk", "cheese", "yogurt", "butter", "cream", "whey", "casein", "ghee", "kefir", "cottage"],
    "egg": ["egg", "omelet", "omelette", "mayo", "mayonnaise", "frittata"],
    "gluten": ["wheat", "bread", "pasta", "flour", "barley", "rye", "couscous", "seitan", "tortilla", "bagel", "toast", "cracker"],
    "wheat": ["wheat", "bread", "pasta", "flour", "couscous", "seitan", "tortilla", "bagel", "toast", "cracker"],
    "soy": ["soy", "tofu", "edamame", "tempeh", "miso"],
    "fish": ["fish", "salmon", "tuna", "cod", "tilapia", "sardine", "anchovy", "trout"],
    "shellfish": ["shrimp", "crab", "lobster", "prawn", "clam", "mussel", "oyster", "scallop"],
    "sesame": ["sesame", "tahini", "hummus"],
}

# foods each diet rules out
MEAT = ["chicken", "beef", "pork", "turkey", "ham", "bacon", "sausage", "steak", "lamb", "jerky", "salami"]
SEAFOOD = ALLERGENS["fish"] + ALLERGENS["shellfish"]
ANIMAL = MEAT + SEAFOOD + ALLERGENS["dairy"] + ALLERGENS["egg"] + ["honey", "gelatin"]
DIETS = {
    "vegetarian": MEAT + SEAFOOD + ["gelatin"],
    "pescatarian": MEAT,
    "vegan": ANIMAL,
    "halal": ["pork", "ham", "bacon", "beer", "wine"],
    "kosher": ["pork", "ham", "bacon", "shrimp", "crab", "lobster"],
}

# exercises to avoid for each injury
HIGH_IMPACT = ["run", "running", "jog", "sprint", "jump", "burpee", "plyometric", "hiit", "squat", "lunge", "box jump"]
KNEE_LOADING = ["leg press", "wall sit", "step-up", "step up", "leg extension", "stair", "pistol", "deep knee bend"]
INJURY_LIMITS = {"knee": HIGH_IMPACT + KNEE_LOADING, "ankle": HIGH_IMPACT + ["stair", "step-up", "step up", "calf raise"],
                 "back": ["deadlift", "squat", "crunch", "sit-up", "row"],
                 "shoulder": ["push-up", "pushup", "press", "pull-up", "pullup", "throw", "swim"]}

MAX_SNACK_KCAL = 700    # one suggestion should never be a huge meal
MIN_BUDGET_KCAL = 300   # even when over the goal, allow a light snack or two in total

# safe fallback foods per flag (checked against the same rules before use)
DEFAULT_FOODS = {
    "low_protein": [
        {"title": "Greek yogurt with berries", "ingredients": ["greek yogurt", "berries"], "kcal": 180, "protein_g": 17,
         "why": "An easy way to add about 17 g of protein."},
        {"title": "Lentil soup", "ingredients": ["lentils", "carrot", "onion"], "kcal": 230, "protein_g": 13,
         "why": "Plant protein plus fiber."},
        {"title": "Grilled chicken breast (4 oz)", "ingredients": ["chicken breast"], "kcal": 190, "protein_g": 35,
         "why": "Lean, high-protein option."},
        {"title": "Tofu stir fry", "ingredients": ["tofu", "vegetables", "rice"], "kcal": 350, "protein_g": 20,
         "why": "Plant protein for dinner."},
    ],
    "high_sodium": [
        {"title": "Fresh fruit and water", "ingredients": ["banana", "water"], "kcal": 110, "protein_g": 1,
         "why": "Potassium helps balance sodium, and water helps too."},
        {"title": "Home-cooked rice and vegetables", "ingredients": ["rice", "vegetables"], "kcal": 300, "protein_g": 7,
         "why": "Cooking at home keeps sodium much lower than takeout."},
    ],
    "low_fiber": [
        {"title": "Oatmeal with an apple", "ingredients": ["oats", "apple"], "kcal": 250, "protein_g": 6,
         "why": "About 8 g of fiber."},
        {"title": "Black bean bowl", "ingredients": ["black beans", "rice", "salsa"], "kcal": 380, "protein_g": 14,
         "why": "Beans are one of the best fiber sources."},
    ],
    "general": [
        {"title": "Vegetable and rice bowl", "ingredients": ["rice", "vegetables", "beans"], "kcal": 400, "protein_g": 14,
         "why": "A balanced meal with carbs, protein and fiber."},
        {"title": "Apple with water", "ingredients": ["apple", "water"], "kcal": 95, "protein_g": 0,
         "why": "A light snack that keeps you on track."},
    ],
}
# safe fallback workouts
DEFAULT_WORKOUTS = [
    {"title": "Brisk walk", "why": "Easy on the joints and good for daily activity.", "minutes": 20, "intensity": "light"},
    {"title": "Stretching and mobility", "why": "Helps recovery and flexibility.", "minutes": 15, "intensity": "light"},
    {"title": "Stationary bike", "why": "Low-impact cardio.", "minutes": 25, "intensity": "moderate"},
]


# Searchable text of a suggestion
def _text(rec):
    return " ".join([str(rec.get("title", "")), str(rec.get("why", ""))] +
                    [str(i) for i in rec.get("ingredients", [])]).lower()


# Whole-word match
def _has_word(text, words):
    return any(re.search(rf"\b{re.escape(w)}(s|es)?\b", text) for w in words)


# Words the user can't have
def blocked_words(user):
    words = []
    for allergy in user.get("allergies") or []:
        a = str(allergy).lower().strip().rstrip("s")
        words += ALLERGENS.get(a, [a])
    words += DIETS.get(str(user.get("diet") or "").lower().strip(), [])
    words += [str(d).lower() for d in user.get("dislikes") or []]
    return words


# Checks one food
def food_allowed(rec, user, calories_remaining):
    text = _text(rec)
    if _has_word(text, blocked_words(user)):
        return False
    kcal = float(rec.get("kcal") or 0)
    if kcal <= 0 or kcal > MAX_SNACK_KCAL:
        return False
    # suggestions shouldn't push far past the goal (small snacks are fine even when over)
    return kcal <= max(calories_remaining, 250)


# Checks one workout
def workout_allowed(rec, user):
    text = _text(rec)
    for injury in user.get("injuries") or []:
        for part, words in INJURY_LIMITS.items():
            if part in str(injury).lower() and _has_word(text, words):
                return False
    if str(user.get("fitness_level") or "").lower() == "beginner" and rec.get("intensity") == "hard":
        return False
    minutes = float(rec.get("minutes") or 0)
    return 5 <= minutes <= 90


# Checks free text like the summary
def text_allowed(text, user):
    return not _has_word(str(text).lower(), blocked_words(user))


# Filters suggestions, adds safe defaults
def apply_limits(ai, user, flags, calories_remaining, want_foods=3, want_workouts=2):
    removed = []
    foods = []
    # all suggestions together must fit what's left today (or a light snack or two when over)
    budget = max(calories_remaining, MIN_BUDGET_KCAL)
    used = 0.0

    # Fits the calorie budget
    def fits(rec):
        return used + float(rec.get("kcal") or 0) <= budget

    for rec in (ai or {}).get("food_recommendations", []) or []:
        if isinstance(rec, dict) and food_allowed(rec, user, calories_remaining) and fits(rec):
            foods.append(rec)
            used += float(rec.get("kcal") or 0)
        else:
            removed.append(str(rec.get("title", "?")) if isinstance(rec, dict) else "?")
    workouts = []
    for rec in (ai or {}).get("workout_recommendations", []) or []:
        if isinstance(rec, dict) and workout_allowed(rec, user):
            workouts.append(rec)
        else:
            removed.append(str(rec.get("title", "?")) if isinstance(rec, dict) else "?")

    # top up with safe defaults for the user's flags
    have = {f["title"].lower() for f in foods}
    pools = [f["type"] for f in flags if f["type"] in DEFAULT_FOODS] + ["general"]
    for pool in pools:
        for rec in DEFAULT_FOODS[pool]:
            if len(foods) >= want_foods:
                break
            if rec["title"].lower() not in have and food_allowed(rec, user, calories_remaining) and fits(rec):
                foods.append(dict(rec, source="default")); have.add(rec["title"].lower())
                used += rec["kcal"]
    for rec in DEFAULT_WORKOUTS:
        if len(workouts) >= want_workouts:
            break
        if rec["title"] not in {w.get("title") for w in workouts} and workout_allowed(rec, user):
            workouts.append(dict(rec, source="default"))
    return foods[:4], workouts[:2], removed
