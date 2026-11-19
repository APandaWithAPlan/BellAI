-- BellAi insights tables (PostgreSQL). Safe to run more than once.
-- Column names match what Insights/insights_server.py expects in "user" and "meals".

CREATE TABLE IF NOT EXISTS users (
  id          SERIAL PRIMARY KEY,
  name        TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- one row per user; allergies, diet and injuries are always enforced by limits.py
CREATE TABLE IF NOT EXISTS user_prefs (
  user_id          INT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  calorie_goal     INT  CHECK (calorie_goal BETWEEN 1200 AND 6000),
  protein_goal_g   INT  CHECK (protein_goal_g BETWEEN 10 AND 400),
  weight_kg        REAL CHECK (weight_kg BETWEEN 25 AND 400),
  sodium_limit_mg  INT  CHECK (sodium_limit_mg BETWEEN 500 AND 10000),
  allergies        TEXT[] NOT NULL DEFAULT '{}',
  diet             TEXT,              -- vegetarian, vegan, pescatarian, halal, kosher
  goal             TEXT CHECK (goal IN ('lose', 'maintain', 'gain')),
  injuries         TEXT[] NOT NULL DEFAULT '{}',
  fitness_level    TEXT CHECK (fitness_level IN ('beginner', 'intermediate', 'advanced')),
  dislikes         TEXT[] NOT NULL DEFAULT '{}'
);

-- one row per logged meal; columns match the food model's "totals"
CREATE TABLE IF NOT EXISTS meals (
  id          SERIAL PRIMARY KEY,
  user_id     INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  eaten_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  source      TEXT CHECK (source IN ('photo', 'text', 'voice')),
  name        TEXT,
  kcal        REAL NOT NULL DEFAULT 0,
  protein_g   REAL NOT NULL DEFAULT 0,
  carbs_g     REAL NOT NULL DEFAULT 0,
  fat_g       REAL NOT NULL DEFAULT 0,
  fiber_g     REAL NOT NULL DEFAULT 0,
  sugar_g     REAL NOT NULL DEFAULT 0,
  sodium_mg   REAL NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS meals_user_time ON meals (user_id, eaten_at);

-- daily Apple Health summary sent by the iOS app (for workout suggestions later)
CREATE TABLE IF NOT EXISTS health_daily (
  user_id      INT  NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day          DATE NOT NULL,
  steps        INT,
  active_kcal  INT,
  weight_kg    REAL,
  PRIMARY KEY (user_id, day)
);
