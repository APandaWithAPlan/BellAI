"""Daily nutrition totals and flags, computed in code (the AI never does the math).

A meal can be a food model result (with "totals") or a simple dict of nutrients:
    {"name": "lunch", "kcal": 650, "protein_g": 30, "sodium_mg": 900, ...}
"""

NUTRIENTS = ["kcal", "protein_g", "carbs_g", "fat_g", "fiber_g", "sugar_g", "sodium_mg"]

DEFAULTS = {
    "calorie_goal": 2000,     # kcal per day
    "sodium_limit_mg": 2300,  # FDA daily value
    "fiber_goal_g": 28,       # FDA daily value
    "sugar_limit_g": 50,      # FDA daily value for added sugar (we only have total sugar)
}


def protein_goal(user):
    """Grams per day: the user's own goal, else 0.8 g per kg, else 20% of calories."""
    if user.get("protein_goal_g"):
        return float(user["protein_goal_g"])
    if user.get("weight_kg"):
        return round(0.8 * float(user["weight_kg"]))
    return round(0.20 * calorie_goal(user) / 4)


def calorie_goal(user):
    return float(user.get("calorie_goal") or DEFAULTS["calorie_goal"])


def meal_nutrients(meal):
    src = meal.get("totals", meal)
    return {k: float(src.get(k) or 0) for k in NUTRIENTS}


def daily_totals(meals):
    total = {k: 0.0 for k in NUTRIENTS}
    for meal in meals:
        for k, v in meal_nutrients(meal).items():
            total[k] += v
    return {k: round(v, 1) for k, v in total.items()}


def compute_flags(user, meals):
    """-> (totals, targets, flags). Each flag: {type, value, target, unit}."""
    totals = daily_totals(meals)
    targets = {
        "kcal": calorie_goal(user),
        "protein_g": protein_goal(user),
        "sodium_mg": float(user.get("sodium_limit_mg") or DEFAULTS["sodium_limit_mg"]),
        "fiber_g": float(user.get("fiber_goal_g") or DEFAULTS["fiber_goal_g"]),
        "sugar_g": float(user.get("sugar_limit_g") or DEFAULTS["sugar_limit_g"]),
    }
    flags = []

    def add(kind, key, unit):
        flags.append({"type": kind, "value": totals[key], "target": targets[key], "unit": unit})

    if not meals:
        return totals, targets, [{"type": "no_meals", "value": 0, "target": 0, "unit": ""}]
    if totals["protein_g"] < 0.8 * targets["protein_g"]:
        add("low_protein", "protein_g", "g")
    if totals["sodium_mg"] > targets["sodium_mg"]:
        add("high_sodium", "sodium_mg", "mg")
    if totals["kcal"] > 1.10 * targets["kcal"]:
        add("over_calories", "kcal", "kcal")
    elif totals["kcal"] < 0.70 * targets["kcal"]:
        add("under_calories", "kcal", "kcal")
    if totals["fiber_g"] < 0.6 * targets["fiber_g"]:
        add("low_fiber", "fiber_g", "g")
    if totals["sugar_g"] > targets["sugar_g"]:
        add("high_sugar", "sugar_g", "g")
    return totals, targets, flags
