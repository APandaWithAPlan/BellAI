# Runs every test scenario through the insights pipeline and checks the replies.

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))   # import the real files from the Insights folder

from insights import generate_insights  # noqa: E402
from limits import MIN_BUDGET_KCAL, food_allowed, text_allowed, workout_allowed  # noqa: E402

# a fake model reply that breaks every rule at once, to prove the limits remove it
BAD_REPLY = {
    "summary": "You're on track! Try peanut butter toast and shrimp tacos for about 150 calories.",
    "food_recommendations": [
        {"title": "Peanut butter toast", "why": "Protein.", "ingredients": ["peanut butter", "bread"], "kcal": 300},
        {"title": "Shrimp tacos", "why": "Lean protein.", "ingredients": ["shrimp", "tortilla"], "kcal": 420},
        {"title": "Grilled chicken salad", "why": "High protein.", "ingredients": ["chicken", "lettuce"], "kcal": 350},
        {"title": "Giant pasta feast", "why": "Energy.", "ingredients": ["pasta"], "kcal": 1400},
    ],
    "workout_recommendations": [
        {"title": "5k run", "why": "Cardio.", "minutes": 30, "intensity": "hard"},
        {"title": "Box jumps", "why": "Power.", "minutes": 15, "intensity": "moderate"},
        {"title": "Wall sits", "why": "Leg strength.", "minutes": 10, "intensity": "light"},
    ],
}


# Problems with one reply
def check_reply(scenario, out):
    user = scenario["user"]
    problems = []
    if out["status"] != scenario["expect_status"]:
        problems.append(f"status is {out['status']}, expected {scenario['expect_status']}")
    if not text_allowed(out["summary"], user):
        problems.append("summary mentions something the user can't have")
    if len(out["summary"]) > 300:
        problems.append("summary too long to read aloud")
    remaining = out["calories_remaining"]
    total_kcal = sum(float(f.get("kcal") or 0) for f in out["food_recommendations"])
    if total_kcal > max(remaining, MIN_BUDGET_KCAL):
        problems.append(f"suggestions add up to {total_kcal:.0f} kcal with {remaining} left")
    problems += [f"food breaks a limit: {f.get('title')}" for f in out["food_recommendations"]
                 if not food_allowed(f, user, remaining)]
    problems += [f"workout breaks a limit: {w.get('title')}" for w in out["workout_recommendations"]
                 if not workout_allowed(w, user)]
    return problems


# Prints one scenario's result
def print_reply(name, out, problems):
    print(f"{'PASS' if not problems else 'FAIL'}  {name}  status={out['status']}  source={out['source']}  {out['timing_ms']} ms")
    for p in problems:
        print(f"      ! {p}")
    print(f"      {out['summary']}")
    for food in out["food_recommendations"]:
        print(f"      food:    {food['title']} ({food.get('kcal', '?')} kcal){' [default]' if food.get('source') == 'default' else ''}")
    for workout in out["workout_recommendations"]:
        print(f"      workout: {workout['title']} ({workout.get('minutes')} min, {workout.get('intensity')})")
    if out["removed_by_limits"]:
        print(f"      removed: {', '.join(out['removed_by_limits'])}")


# Runs the scenarios
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--live", action="store_true", help="use the real chat model")
    parser.add_argument("--only", help="run one scenario by name")
    args = parser.parse_args()

    with open(os.path.join(HERE, "scenarios.json"), encoding="utf-8") as f:
        scenarios = [s for s in json.load(f) if not args.only or s["name"] == args.only]
    if not scenarios:
        sys.exit(f"No scenario named {args.only}")

    failures = 0
    for s in scenarios:
        fake = None if args.live else (lambda _text: json.loads(json.dumps(BAD_REPLY)))
        out = generate_insights(s["user"], s["meals"], **({} if args.live else {"ask_model": fake}))
        problems = check_reply(s, out)
        failures += bool(problems)
        print_reply(s["name"], out, problems)

    print(f"\n{'All scenarios passed.' if not failures else f'{failures} scenario(s) failed.'}")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
