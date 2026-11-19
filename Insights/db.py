# Loads users and meals from the PostgreSQL database and saves new meals.

import os
from datetime import date

import psycopg
from psycopg.rows import dict_row

# day boundaries for "today" use this time zone
TIMEZONE = os.environ.get("BELLAI_TZ", "America/Chicago")
NUTRIENTS = ["kcal", "protein_g", "carbs_g", "fat_g", "fiber_g", "sugar_g", "sodium_mg"]
PREF_COLUMNS = ["calorie_goal", "protein_goal_g", "weight_kg", "sodium_limit_mg", "allergies",
                "diet", "goal", "injuries", "fitness_level", "dislikes"]

# parameterized queries only (%s), so input can never change the SQL
PREFS_SQL = f"SELECT {', '.join(PREF_COLUMNS)} FROM user_prefs WHERE user_id = %s"

MEALS_SQL = f"""
SELECT name, {', '.join(NUTRIENTS)}
FROM meals
WHERE user_id = %s AND (eaten_at AT TIME ZONE %s)::date = %s
ORDER BY eaten_at
"""

SAVE_SQL = f"""
INSERT INTO meals (user_id, source, name, {', '.join(NUTRIENTS)})
VALUES (%s, %s, %s, {', '.join(['%s'] * len(NUTRIENTS))})
RETURNING id
"""


# Opens a database connection
def connect():
    return psycopg.connect(os.environ["DATABASE_URL"], row_factory=dict_row)


# User's preferences and today's meals
def load_insights_request(conn, user_id, day=None):
    day = day or date.today()
    prefs = conn.execute(PREFS_SQL, (user_id,)).fetchone() or {}
    user = {k: v for k, v in prefs.items() if v not in (None, [])}
    meals = conn.execute(MEALS_SQL, (user_id, TIMEZONE, day)).fetchall()
    return {"user": user, "meals": [dict(m) for m in meals]}


# Saves one meal
def save_meal(conn, user_id, analysis, source="photo"):
    totals = analysis.get("totals", analysis)
    items = analysis.get("items") or []
    name = analysis.get("name") or ", ".join(i.get("label", "") for i in items if i.get("label")) or "meal"
    values = [float(totals.get(k) or 0) for k in NUTRIENTS]
    row = conn.execute(SAVE_SQL, (user_id, source, name[:200], *values)).fetchone()
    conn.commit()
    return row["id"]
