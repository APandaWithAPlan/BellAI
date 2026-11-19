-- Fake test users for the insights scenarios (ids 9001 and up). Re-running replaces them.
-- Meals cover a week ending 2026-10-31; regenerate with make_fake_meals.py --today for other dates.
BEGIN;
DELETE FROM users WHERE id >= 9001;

-- avoid_foods
INSERT INTO users (id, name) VALUES (9001, 'test_avoid_foods');
INSERT INTO user_prefs (user_id, calorie_goal, protein_goal_g, weight_kg, sodium_limit_mg, diet, goal, fitness_level, allergies, injuries, dislikes) VALUES (9001, '2000', '100', NULL, NULL, NULL, 'maintain', NULL, ARRAY['peanut', 'shellfish']::TEXT[], ARRAY[]::TEXT[], ARRAY[]::TEXT[]);
INSERT INTO meals (user_id, eaten_at, source, name, kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg) VALUES
  (9001, '2026-10-25T08:21:00-05:00', 'voice', 'buttered white toast and scrambled eggs and toast', 455.7, 21.5, 42.0, 22.4, 3.0, 6.0, 780.3),
  (9001, '2026-10-25T12:53:00-05:00', 'voice', 'chicken caesar wrap', 501.5, 31.3, 39.7, 23.0, 3.1, 3.1, 1201.6),
  (9001, '2026-10-25T15:39:00-05:00', 'photo', 'granola bar', 205.9, 4.3, 31.4, 7.6, 2.2, 13.0, 130.1),
  (9001, '2026-10-25T18:35:00-05:00', 'voice', 'grilled chicken breast and white rice and mac and cheese', 869.3, 66.2, 95.4, 22.3, 2.7, 6.2, 1020.4),
  (9001, '2026-10-26T07:33:00-05:00', 'text', 'bagel with cream cheese and plain greek yogurt', 433.0, 27.1, 57.9, 10.0, 1.9, 12.4, 616.8),
  (9001, '2026-10-26T12:13:00-05:00', 'voice', 'deli turkey sandwich', 351.3, 21.5, 41.0, 9.8, 2.9, 5.9, 1366.1),
  (9001, '2026-10-26T15:48:00-05:00', 'voice', 'protein shake', 154.5, 29.0, 4.8, 2.4, 1.0, 1.9, 241.3),
  (9001, '2026-10-26T18:56:00-05:00', 'text', 'baked salmon and white rice', 519.8, 35.9, 49.1, 18.6, 0.7, 0.0, 88.2),
  (9001, '2026-10-27T08:17:00-05:00', 'photo', 'buttered white toast and scrambled eggs and toast', 459.7, 21.2, 43.6, 22.3, 3.1, 6.2, 785.8),
  (9001, '2026-10-27T12:22:00-05:00', 'photo', 'chicken caesar wrap', 528.0, 33.0, 41.8, 24.2, 3.3, 3.3, 1265.0),
  (9001, '2026-10-27T15:49:00-05:00', 'photo', 'granola bar', 195.7, 4.1, 29.9, 7.2, 2.1, 12.4, 123.6),
  (9001, '2026-10-27T18:31:00-05:00', 'photo', 'grilled chicken breast and white rice and mac and cheese', 841.2, 64.0, 94.2, 20.7, 2.5, 5.6, 936.5),
  (9001, '2026-10-28T07:37:00-05:00', 'photo', 'bagel with cream cheese and plain greek yogurt', 440.6, 27.3, 59.0, 10.2, 1.9, 12.6, 629.3),
  (9001, '2026-10-28T12:16:00-05:00', 'text', 'deli turkey sandwich', 357.5, 21.8, 41.7, 9.9, 3.0, 6.0, 1390.2),
  (9001, '2026-10-28T15:38:00-05:00', 'photo', 'protein shake', 149.4, 28.0, 4.7, 2.3, 0.9, 1.9, 233.4),
  (9001, '2026-10-28T18:49:00-05:00', 'photo', 'baked salmon and white rice', 518.4, 38.6, 42.0, 20.4, 0.6, 0.0, 96.9),
  (9001, '2026-10-29T08:06:00-05:00', 'voice', 'buttered white toast and scrambled eggs and toast', 476.7, 22.5, 43.8, 23.5, 3.2, 6.3, 816.4),
  (9001, '2026-10-29T12:45:00-05:00', 'photo', 'chicken caesar wrap', 470.1, 29.4, 37.2, 21.5, 2.9, 2.9, 1126.2),
  (9001, '2026-10-29T15:44:00-05:00', 'photo', 'granola bar', 173.9, 3.7, 26.5, 6.4, 1.8, 11.0, 109.8),
  (9001, '2026-10-29T19:08:00-05:00', 'photo', 'grilled chicken breast and white rice and mac and cheese', 851.0, 59.4, 98.8, 22.1, 2.8, 6.4, 1035.2),
  (9001, '2026-10-30T07:32:00-05:00', 'text', 'bagel with cream cheese and plain greek yogurt', 482.6, 28.9, 65.4, 11.3, 2.1, 13.5, 697.4),
  (9001, '2026-10-30T12:42:00-05:00', 'text', 'deli turkey sandwich', 362.4, 22.1, 42.3, 10.1, 3.0, 6.0, 1409.2),
  (9001, '2026-10-30T15:41:00-05:00', 'text', 'protein shake', 146.2, 27.4, 4.6, 2.3, 0.9, 1.8, 228.4),
  (9001, '2026-10-30T19:01:00-05:00', 'photo', 'baked salmon and white rice', 481.5, 33.7, 44.3, 17.5, 0.6, 0.0, 83.2),
  (9001, '2026-10-31T08:27:00-05:00', 'voice', 'buttered white toast and scrambled eggs and toast', 440.0, 20.5, 41.2, 21.5, 2.9, 5.9, 752.8),
  (9001, '2026-10-31T12:27:00-05:00', 'photo', 'chicken caesar wrap', 499.9, 31.2, 39.6, 22.9, 3.1, 3.1, 1197.7),
  (9001, '2026-10-31T15:41:00-05:00', 'text', 'granola bar', 198.9, 4.2, 30.4, 7.3, 2.1, 12.6, 125.6),
  (9001, '2026-10-31T18:59:00-05:00', 'voice', 'grilled chicken breast and white rice and mac and cheese', 876.8, 64.1, 99.4, 22.4, 2.8, 6.3, 1033.5);

-- high_sodium
INSERT INTO users (id, name) VALUES (9002, 'test_high_sodium');
INSERT INTO user_prefs (user_id, calorie_goal, protein_goal_g, weight_kg, sodium_limit_mg, diet, goal, fitness_level, allergies, injuries, dislikes) VALUES (9002, '2200', '100', NULL, NULL, NULL, 'maintain', NULL, ARRAY[]::TEXT[], ARRAY[]::TEXT[], ARRAY[]::TEXT[]);
INSERT INTO meals (user_id, eaten_at, source, name, kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg) VALUES
  (9002, '2026-10-25T07:48:00-05:00', 'voice', 'scrambled eggs and toast and black coffee', 306.0, 18.8, 17.4, 17.4, 2.2, 3.3, 537.1),
  (9002, '2026-10-25T12:50:00-05:00', 'voice', 'deli turkey sandwich and potato chips', 533.2, 25.0, 59.3, 20.9, 4.2, 6.3, 1609.9),
  (9002, '2026-10-25T15:18:00-05:00', 'photo', 'pretzels', 100.5, 2.8, 21.4, 0.7, 0.9, 0.7, 358.4),
  (9002, '2026-10-25T19:04:00-05:00', 'photo', 'instant ramen and canned chicken noodle soup', 568.0, 16.9, 75.2, 19.9, 3.2, 4.2, 3733.2),
  (9002, '2026-10-26T07:33:00-05:00', 'photo', 'bagel with cream cheese', 377.9, 11.5, 58.8, 10.5, 2.1, 7.3, 629.8),
  (9002, '2026-10-26T12:32:00-05:00', 'photo', 'cheese pizza, 2 slices', 579.6, 24.4, 73.2, 20.3, 4.1, 8.1, 1301.5),
  (9002, '2026-10-26T15:32:00-05:00', 'photo', 'cottage cheese', 200.5, 22.8, 7.3, 8.2, 0.0, 5.5, 747.3),
  (9002, '2026-10-26T18:34:00-05:00', 'photo', 'beef stir fry takeout', 695.7, 32.1, 64.2, 32.1, 4.3, 16.1, 2247.6),
  (9002, '2026-10-27T07:37:00-05:00', 'photo', 'scrambled eggs and toast and black coffee', 291.7, 17.9, 16.6, 16.6, 2.1, 3.1, 511.9),
  (9002, '2026-10-27T12:05:00-05:00', 'voice', 'deli turkey sandwich and potato chips', 503.7, 24.2, 56.3, 19.2, 4.0, 6.2, 1556.5),
  (9002, '2026-10-27T15:36:00-05:00', 'text', 'pretzels', 111.4, 3.1, 23.7, 0.8, 1.0, 0.8, 397.1),
  (9002, '2026-10-27T19:15:00-05:00', 'text', 'instant ramen and canned chicken noodle soup', 554.2, 16.2, 73.5, 19.5, 3.1, 4.1, 3587.7),
  (9002, '2026-10-28T07:55:00-05:00', 'photo', 'bagel with cream cheese', 341.2, 10.4, 53.1, 9.5, 1.9, 6.6, 568.6),
  (9002, '2026-10-28T12:19:00-05:00', 'voice', 'cheese pizza, 2 slices', 589.6, 24.8, 74.5, 20.7, 4.1, 8.3, 1324.0),
  (9002, '2026-10-28T15:48:00-05:00', 'photo', 'cottage cheese', 211.9, 24.1, 7.7, 8.7, 0.0, 5.8, 789.9),
  (9002, '2026-10-28T19:09:00-05:00', 'photo', 'beef stir fry takeout', 586.2, 27.1, 54.1, 27.1, 3.6, 13.5, 1893.9),
  (9002, '2026-10-29T07:46:00-05:00', 'photo', 'scrambled eggs and toast and black coffee', 258.0, 15.8, 14.6, 14.6, 1.8, 2.7, 452.9),
  (9002, '2026-10-29T12:56:00-05:00', 'photo', 'deli turkey sandwich and potato chips', 554.8, 26.1, 61.8, 21.6, 4.3, 6.6, 1680.6),
  (9002, '2026-10-29T15:10:00-05:00', 'voice', 'pretzels', 105.2, 2.9, 22.4, 0.8, 1.0, 0.8, 375.0),
  (9002, '2026-10-29T19:09:00-05:00', 'photo', 'instant ramen and canned chicken noodle soup', 561.5, 16.9, 74.2, 19.6, 3.2, 4.2, 3729.9),
  (9002, '2026-10-30T08:05:00-05:00', 'text', 'bagel with cream cheese', 372.1, 11.4, 57.9, 10.3, 2.1, 7.2, 620.1),
  (9002, '2026-10-30T12:06:00-05:00', 'photo', 'cheese pizza, 2 slices', 619.2, 26.1, 78.2, 21.7, 4.3, 8.7, 1390.5),
  (9002, '2026-10-30T15:56:00-05:00', 'photo', 'cottage cheese', 209.6, 23.8, 7.6, 8.6, 0.0, 5.7, 781.4),
  (9002, '2026-10-30T18:39:00-05:00', 'text', 'beef stir fry takeout', 681.5, 31.5, 62.9, 31.5, 4.2, 15.7, 2201.8),
  (9002, '2026-10-31T07:51:00-05:00', 'photo', 'scrambled eggs and toast and black coffee', 269.7, 16.5, 15.3, 15.3, 1.9, 2.9, 473.3),
  (9002, '2026-10-31T12:32:00-05:00', 'voice', 'deli turkey sandwich and potato chips', 536.2, 25.0, 59.6, 21.1, 4.2, 6.3, 1610.9),
  (9002, '2026-10-31T15:58:00-05:00', 'photo', 'pretzels', 102.6, 2.9, 21.9, 0.8, 1.0, 0.8, 365.8),
  (9002, '2026-10-31T18:47:00-05:00', 'photo', 'instant ramen and canned chicken noodle soup', 496.7, 15.2, 65.5, 17.3, 2.8, 3.8, 3369.3);

-- low_protein
INSERT INTO users (id, name) VALUES (9003, 'test_low_protein');
INSERT INTO user_prefs (user_id, calorie_goal, protein_goal_g, weight_kg, sodium_limit_mg, diet, goal, fitness_level, allergies, injuries, dislikes) VALUES (9003, '2000', '120', NULL, NULL, NULL, 'maintain', 'intermediate', ARRAY[]::TEXT[], ARRAY[]::TEXT[], ARRAY[]::TEXT[]);
INSERT INTO meals (user_id, eaten_at, source, name, kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg) VALUES
  (9003, '2026-10-25T08:10:00-05:00', 'text', 'bagel with cream cheese and orange juice', 463.7, 12.9, 80.0, 10.5, 2.5, 26.4, 602.8),
  (9003, '2026-10-25T12:32:00-05:00', 'photo', 'pasta with marinara', 448.7, 15.0, 85.5, 5.3, 6.4, 12.8, 747.8),
  (9003, '2026-10-25T15:34:00-05:00', 'photo', 'granola bar and apple', 276.8, 4.2, 53.3, 6.8, 6.5, 31.2, 113.8),
  (9003, '2026-10-25T18:53:00-05:00', 'text', 'white rice and steamed broccoli and garden salad with vinaigrette', 402.3, 9.6, 66.1, 12.1, 8.4, 6.6, 296.5),
  (9003, '2026-10-26T08:06:00-05:00', 'photo', 'oatmeal with banana and black coffee', 258.8, 6.9, 52.1, 3.8, 6.6, 14.2, 14.2),
  (9003, '2026-10-26T12:31:00-05:00', 'photo', 'mac and cheese', 348.5, 11.0, 44.0, 14.7, 1.8, 5.5, 797.9),
  (9003, '2026-10-26T15:08:00-05:00', 'photo', 'pretzels and apple', 213.9, 3.8, 50.4, 1.2, 5.5, 20.0, 423.8),
  (9003, '2026-10-26T18:40:00-05:00', 'text', 'pasta with marinara and buttered white toast', 618.6, 18.8, 110.9, 11.7, 7.3, 15.7, 1027.4),
  (9003, '2026-10-27T07:43:00-05:00', 'photo', 'bagel with cream cheese and orange juice', 476.4, 13.1, 82.9, 10.6, 2.5, 28.5, 605.4),
  (9003, '2026-10-27T12:25:00-05:00', 'text', 'pasta with marinara', 437.9, 14.6, 83.4, 5.2, 6.3, 12.5, 729.8),
  (9003, '2026-10-27T15:07:00-05:00', 'photo', 'granola bar and apple', 283.0, 4.5, 53.7, 7.2, 6.4, 30.9, 120.5),
  (9003, '2026-10-27T18:44:00-05:00', 'photo', 'white rice and steamed broccoli and garden salad with vinaigrette', 399.6, 9.4, 63.3, 13.2, 8.5, 7.0, 318.2),
  (9003, '2026-10-28T07:33:00-05:00', 'photo', 'oatmeal with banana and black coffee', 246.4, 6.6, 49.6, 3.6, 6.3, 13.5, 14.2),
  (9003, '2026-10-28T12:02:00-05:00', 'text', 'mac and cheese', 347.1, 11.0, 43.8, 14.6, 1.8, 5.5, 794.7),
  (9003, '2026-10-28T15:42:00-05:00', 'voice', 'pretzels and apple', 188.8, 3.2, 44.7, 1.0, 5.1, 18.7, 353.9),
  (9003, '2026-10-28T19:29:00-05:00', 'voice', 'pasta with marinara and buttered white toast', 553.5, 16.9, 99.5, 10.3, 6.6, 14.1, 919.4),
  (9003, '2026-10-29T07:56:00-05:00', 'photo', 'bagel with cream cheese and orange juice', 452.9, 12.4, 79.0, 10.0, 2.4, 27.5, 571.1),
  (9003, '2026-10-29T12:42:00-05:00', 'voice', 'pasta with marinara', 385.9, 12.9, 73.5, 4.6, 5.5, 11.0, 643.2),
  (9003, '2026-10-29T15:55:00-05:00', 'photo', 'granola bar and apple', 277.8, 4.4, 52.7, 7.1, 6.3, 30.3, 118.5),
  (9003, '2026-10-29T18:55:00-05:00', 'text', 'white rice and steamed broccoli and garden salad with vinaigrette', 410.4, 10.0, 67.8, 12.1, 8.9, 6.8, 302.2),
  (9003, '2026-10-30T07:42:00-05:00', 'photo', 'oatmeal with banana and black coffee', 289.1, 7.7, 58.3, 4.2, 7.4, 15.9, 15.2),
  (9003, '2026-10-30T12:08:00-05:00', 'voice', 'mac and cheese', 382.8, 12.1, 48.3, 16.1, 2.0, 6.0, 876.3),
  (9003, '2026-10-30T15:55:00-05:00', 'photo', 'pretzels and apple', 195.5, 3.3, 46.4, 1.0, 5.3, 19.6, 362.6),
  (9003, '2026-10-30T19:05:00-05:00', 'photo', 'pasta with marinara and buttered white toast', 597.5, 18.1, 107.0, 11.4, 7.0, 15.1, 992.3),
  (9003, '2026-10-31T08:23:00-05:00', 'photo', 'bagel with cream cheese and orange juice', 450.8, 12.2, 79.6, 9.7, 2.4, 29.5, 548.3),
  (9003, '2026-10-31T12:59:00-05:00', 'photo', 'pasta with marinara', 459.4, 15.3, 87.5, 5.5, 6.6, 13.1, 765.7),
  (9003, '2026-10-31T15:13:00-05:00', 'voice', 'granola bar and apple', 272.0, 4.2, 52.0, 6.8, 6.3, 30.1, 114.0),
  (9003, '2026-10-31T18:54:00-05:00', 'text', 'white rice and steamed broccoli and garden salad with vinaigrette', 407.9, 9.6, 67.9, 11.8, 8.0, 6.4, 287.0);

-- no_meals
INSERT INTO users (id, name) VALUES (9004, 'test_no_meals');
INSERT INTO user_prefs (user_id, calorie_goal, protein_goal_g, weight_kg, sodium_limit_mg, diet, goal, fitness_level, allergies, injuries, dislikes) VALUES (9004, '2200', '130', NULL, NULL, NULL, 'gain', NULL, ARRAY[]::TEXT[], ARRAY[]::TEXT[], ARRAY[]::TEXT[]);

-- on_track
INSERT INTO users (id, name) VALUES (9005, 'test_on_track');
INSERT INTO user_prefs (user_id, calorie_goal, protein_goal_g, weight_kg, sodium_limit_mg, diet, goal, fitness_level, allergies, injuries, dislikes) VALUES (9005, '2000', '100', NULL, NULL, NULL, 'maintain', 'intermediate', ARRAY[]::TEXT[], ARRAY[]::TEXT[], ARRAY[]::TEXT[]);
INSERT INTO meals (user_id, eaten_at, source, name, kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg) VALUES
  (9005, '2026-10-25T07:44:00-05:00', 'photo', 'oatmeal with banana and plain greek yogurt and orange juice', 476.0, 24.5, 86.8, 5.2, 7.7, 40.9, 67.4),
  (9005, '2026-10-25T12:05:00-05:00', 'voice', 'grilled chicken breast and brown rice and steamed broccoli', 544.7, 56.8, 59.5, 7.5, 9.0, 2.9, 195.6),
  (9005, '2026-10-25T15:14:00-05:00', 'photo', 'apple and almonds', 236.8, 6.0, 28.2, 13.1, 7.2, 18.3, 1.8),
  (9005, '2026-10-25T18:56:00-05:00', 'photo', 'baked salmon and baked sweet potato and garden salad with vinaigrette', 610.7, 38.6, 42.7, 31.9, 8.3, 15.6, 407.5),
  (9005, '2026-10-26T08:25:00-05:00', 'photo', 'scrambled eggs and toast and black coffee', 279.1, 17.1, 15.8, 15.8, 2.0, 3.0, 489.8),
  (9005, '2026-10-26T12:10:00-05:00', 'voice', 'black bean burrito bowl', 546.9, 21.0, 84.1, 12.6, 15.8, 4.2, 946.6),
  (9005, '2026-10-26T15:21:00-05:00', 'photo', 'plain greek yogurt and apple and granola bar', 392.6, 21.3, 60.7, 8.6, 6.3, 36.6, 191.9),
  (9005, '2026-10-26T19:08:00-05:00', 'text', 'grilled chicken breast and pasta with marinara and steamed broccoli', 672.7, 59.1, 85.3, 9.8, 10.9, 13.2, 813.9),
  (9005, '2026-10-27T08:29:00-05:00', 'voice', 'oatmeal with banana and plain greek yogurt and orange juice', 505.1, 27.2, 90.8, 5.5, 7.9, 43.3, 76.4),
  (9005, '2026-10-27T12:56:00-05:00', 'text', 'grilled chicken breast and brown rice and steamed broccoli', 492.5, 50.2, 55.4, 6.7, 8.5, 2.7, 176.9),
  (9005, '2026-10-27T15:02:00-05:00', 'photo', 'apple and almonds', 267.2, 6.8, 31.6, 14.9, 8.1, 20.5, 2.0),
  (9005, '2026-10-27T19:25:00-05:00', 'photo', 'baked salmon and baked sweet potato and garden salad with vinaigrette', 635.7, 40.2, 44.7, 33.1, 8.7, 16.3, 421.9),
  (9005, '2026-10-28T08:23:00-05:00', 'text', 'scrambled eggs and toast and black coffee', 275.3, 16.9, 15.6, 15.6, 2.0, 2.9, 483.2),
  (9005, '2026-10-28T12:22:00-05:00', 'photo', 'black bean burrito bowl', 484.9, 18.7, 74.6, 11.2, 14.0, 3.7, 839.3),
  (9005, '2026-10-28T15:04:00-05:00', 'photo', 'plain greek yogurt and apple and granola bar', 399.2, 22.2, 62.3, 8.3, 6.7, 38.4, 189.6),
  (9005, '2026-10-28T18:47:00-05:00', 'photo', 'grilled chicken breast and pasta with marinara and steamed broccoli', 702.8, 63.3, 86.8, 10.4, 10.7, 13.4, 839.5),
  (9005, '2026-10-29T07:44:00-05:00', 'photo', 'oatmeal with banana and plain greek yogurt and orange juice', 506.0, 27.5, 90.9, 5.4, 7.8, 44.1, 77.7),
  (9005, '2026-10-29T12:58:00-05:00', 'text', 'grilled chicken breast and brown rice and steamed broccoli', 527.0, 56.6, 55.1, 7.4, 8.0, 2.5, 186.0),
  (9005, '2026-10-29T15:56:00-05:00', 'voice', 'apple and almonds', 253.5, 6.5, 29.6, 14.3, 7.6, 19.1, 1.9),
  (9005, '2026-10-29T19:04:00-05:00', 'text', 'baked salmon and baked sweet potato and garden salad with vinaigrette', 570.5, 35.5, 39.3, 30.4, 7.8, 14.5, 395.9),
  (9005, '2026-10-30T08:07:00-05:00', 'voice', 'scrambled eggs and toast and black coffee', 295.8, 18.1, 16.8, 16.8, 2.1, 3.1, 519.1),
  (9005, '2026-10-30T12:08:00-05:00', 'voice', 'black bean burrito bowl', 505.6, 19.4, 77.8, 11.7, 14.6, 3.9, 875.2),
  (9005, '2026-10-30T15:40:00-05:00', 'photo', 'plain greek yogurt and apple and granola bar', 353.4, 19.8, 55.0, 7.4, 5.8, 33.9, 168.5),
  (9005, '2026-10-30T18:54:00-05:00', 'voice', 'grilled chicken breast and pasta with marinara and steamed broccoli', 726.1, 65.8, 88.8, 10.8, 10.5, 13.6, 865.0),
  (9005, '2026-10-31T07:30:00-05:00', 'photo', 'oatmeal with banana and plain greek yogurt and orange juice', 502.1, 27.8, 89.8, 5.3, 7.6, 44.2, 78.9),
  (9005, '2026-10-31T12:41:00-05:00', 'text', 'grilled chicken breast and brown rice and steamed broccoli', 529.1, 55.7, 56.8, 7.4, 8.3, 2.6, 186.1),
  (9005, '2026-10-31T15:29:00-05:00', 'photo', 'apple and almonds', 249.5, 6.4, 29.0, 14.1, 7.5, 18.7, 1.8),
  (9005, '2026-10-31T19:02:00-05:00', 'photo', 'baked salmon and baked sweet potato and garden salad with vinaigrette', 626.2, 41.1, 42.9, 32.4, 8.2, 15.5, 394.4);

-- one_day_only
INSERT INTO users (id, name) VALUES (9006, 'test_one_day_only');
INSERT INTO user_prefs (user_id, calorie_goal, protein_goal_g, weight_kg, sodium_limit_mg, diet, goal, fitness_level, allergies, injuries, dislikes) VALUES (9006, '2000', '100', NULL, NULL, NULL, 'maintain', NULL, ARRAY[]::TEXT[], ARRAY[]::TEXT[], ARRAY[]::TEXT[]);
INSERT INTO meals (user_id, eaten_at, source, name, kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg) VALUES
  (9006, '2026-10-31T08:07:00-05:00', 'text', 'oatmeal with banana', 288.7, 7.5, 58.6, 4.3, 7.5, 16.0, 10.7),
  (9006, '2026-10-31T12:15:00-05:00', 'photo', 'deli turkey sandwich', 347.2, 21.2, 40.5, 9.6, 2.9, 5.8, 1350.2);

-- over_calories
INSERT INTO users (id, name) VALUES (9007, 'test_over_calories');
INSERT INTO user_prefs (user_id, calorie_goal, protein_goal_g, weight_kg, sodium_limit_mg, diet, goal, fitness_level, allergies, injuries, dislikes) VALUES (9007, '1800', '110', NULL, NULL, NULL, 'lose', 'beginner', ARRAY[]::TEXT[], ARRAY[]::TEXT[], ARRAY[]::TEXT[]);
INSERT INTO meals (user_id, eaten_at, source, name, kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg) VALUES
  (9007, '2026-10-25T07:46:00-05:00', 'photo', 'glazed donut and bagel with cream cheese and orange juice', 736.9, 17.3, 113.7, 24.6, 3.5, 42.5, 819.2),
  (9007, '2026-10-25T12:00:00-05:00', 'photo', 'cheeseburger and french fries and soda', 821.2, 19.8, 121.5, 29.8, 5.6, 46.1, 1079.1),
  (9007, '2026-10-25T15:57:00-05:00', 'photo', 'potato chips and granola bar', 343.6, 6.1, 44.9, 16.7, 3.1, 13.0, 264.6),
  (9007, '2026-10-25T18:39:00-05:00', 'voice', 'pasta with marinara and buttered white toast and soda', 747.5, 18.4, 148.1, 11.4, 7.1, 55.0, 1050.9),
  (9007, '2026-10-26T08:27:00-05:00', 'photo', 'scrambled eggs and toast and glazed donut', 517.8, 19.6, 44.6, 29.2, 2.8, 17.2, 650.6),
  (9007, '2026-10-26T12:06:00-05:00', 'text', 'chicken caesar wrap and french fries and soda', 995.1, 36.2, 123.3, 39.8, 7.0, 40.6, 1516.2),
  (9007, '2026-10-26T15:26:00-05:00', 'photo', 'almonds and granola bar', 377.8, 10.6, 37.6, 22.3, 5.8, 14.2, 129.2),
  (9007, '2026-10-26T18:40:00-05:00', 'photo', 'cheese pizza, 2 slices and soda', 751.2, 26.0, 115.1, 21.7, 4.3, 45.6, 1431.6),
  (9007, '2026-10-27T07:51:00-05:00', 'voice', 'glazed donut and bagel with cream cheese and orange juice', 732.6, 16.4, 111.3, 25.7, 3.4, 44.5, 765.7),
  (9007, '2026-10-27T12:17:00-05:00', 'photo', 'cheeseburger and french fries and soda', 858.4, 20.2, 127.9, 31.0, 5.9, 49.2, 1107.0),
  (9007, '2026-10-27T15:55:00-05:00', 'photo', 'potato chips and granola bar', 335.8, 5.8, 42.6, 17.0, 2.9, 11.2, 267.1),
  (9007, '2026-10-27T18:59:00-05:00', 'text', 'pasta with marinara and buttered white toast and soda', 759.5, 18.8, 151.8, 11.0, 7.4, 57.2, 1062.5),
  (9007, '2026-10-28T07:44:00-05:00', 'photo', 'scrambled eggs and toast and glazed donut', 554.0, 20.6, 48.2, 31.3, 3.0, 18.8, 688.0),
  (9007, '2026-10-28T12:55:00-05:00', 'photo', 'chicken caesar wrap and french fries and soda', 912.1, 30.9, 117.1, 35.9, 6.5, 40.7, 1314.8),
  (9007, '2026-10-28T15:41:00-05:00', 'voice', 'almonds and granola bar', 360.9, 10.4, 34.3, 22.0, 5.7, 12.8, 114.7),
  (9007, '2026-10-28T18:51:00-05:00', 'photo', 'cheese pizza, 2 slices and soda', 740.1, 24.9, 116.3, 20.7, 4.1, 50.0, 1374.0),
  (9007, '2026-10-29T07:46:00-05:00', 'photo', 'glazed donut and bagel with cream cheese and orange juice', 747.0, 17.6, 114.2, 25.3, 3.6, 41.2, 847.5),
  (9007, '2026-10-29T12:20:00-05:00', 'voice', 'cheeseburger and french fries and soda', 783.1, 17.8, 118.6, 27.8, 5.3, 47.5, 981.1),
  (9007, '2026-10-29T15:24:00-05:00', 'photo', 'potato chips and granola bar', 345.7, 6.1, 44.4, 17.2, 3.0, 12.1, 271.4),
  (9007, '2026-10-29T19:29:00-05:00', 'photo', 'pasta with marinara and buttered white toast and soda', 702.5, 17.5, 138.3, 11.0, 6.7, 49.6, 997.9),
  (9007, '2026-10-30T08:12:00-05:00', 'text', 'scrambled eggs and toast and glazed donut', 518.3, 20.2, 43.9, 29.3, 2.9, 16.6, 664.1),
  (9007, '2026-10-30T12:57:00-05:00', 'text', 'chicken caesar wrap and french fries and soda', 998.2, 34.9, 124.6, 40.1, 7.2, 39.5, 1474.0),
  (9007, '2026-10-30T15:20:00-05:00', 'voice', 'almonds and granola bar', 360.6, 10.1, 36.0, 21.3, 5.6, 13.6, 124.0),
  (9007, '2026-10-30T18:42:00-05:00', 'voice', 'cheese pizza, 2 slices and soda', 734.0, 24.9, 114.3, 20.8, 4.2, 47.7, 1376.0),
  (9007, '2026-10-31T07:41:00-05:00', 'text', 'glazed donut and bagel with cream cheese and orange juice', 746.7, 17.0, 114.0, 25.8, 3.5, 44.4, 799.4),
  (9007, '2026-10-31T12:13:00-05:00', 'voice', 'cheeseburger and french fries and soda', 818.2, 19.0, 121.1, 29.9, 5.7, 44.7, 1041.6),
  (9007, '2026-10-31T15:20:00-05:00', 'voice', 'potato chips and granola bar', 354.7, 6.2, 45.5, 17.7, 3.1, 12.4, 279.0),
  (9007, '2026-10-31T19:20:00-05:00', 'photo', 'pasta with marinara and buttered white toast and soda', 731.4, 18.0, 145.1, 11.2, 7.0, 54.1, 1026.8);

-- under_eating
INSERT INTO users (id, name) VALUES (9008, 'test_under_eating');
INSERT INTO user_prefs (user_id, calorie_goal, protein_goal_g, weight_kg, sodium_limit_mg, diet, goal, fitness_level, allergies, injuries, dislikes) VALUES (9008, '1500', '90', NULL, NULL, NULL, 'lose', NULL, ARRAY[]::TEXT[], ARRAY[]::TEXT[], ARRAY[]::TEXT[]);
INSERT INTO meals (user_id, eaten_at, source, name, kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg) VALUES
  (9008, '2026-10-25T07:48:00-05:00', 'text', 'black coffee', 2.1, 0.3, 0.0, 0.0, 0.0, 0.0, 5.2),
  (9008, '2026-10-25T12:15:00-05:00', 'text', 'garden salad with vinaigrette and apple', 241.4, 2.4, 36.4, 11.4, 7.6, 25.3, 231.9),
  (9008, '2026-10-25T15:01:00-05:00', 'photo', 'plain greek yogurt and granola bar', 273.1, 19.8, 32.9, 7.2, 1.9, 16.9, 170.4),
  (9008, '2026-10-25T19:24:00-05:00', 'photo', 'canned chicken noodle soup and steamed broccoli', 197.1, 11.3, 28.0, 4.9, 5.9, 3.9, 1752.8),
  (9008, '2026-10-26T08:06:00-05:00', 'photo', 'black coffee and apple', 104.3, 0.8, 26.9, 0.3, 4.7, 20.5, 7.1),
  (9008, '2026-10-26T12:25:00-05:00', 'photo', 'plain greek yogurt and granola bar', 290.0, 21.6, 34.6, 7.6, 2.0, 18.0, 180.9),
  (9008, '2026-10-26T15:44:00-05:00', 'photo', 'almonds', 152.4, 5.6, 5.6, 13.0, 3.3, 1.1, 0.0),
  (9008, '2026-10-26T19:26:00-05:00', 'photo', 'grilled chicken breast and steamed broccoli', 326.4, 53.6, 11.8, 6.0, 5.4, 2.1, 188.3),
  (9008, '2026-10-27T07:44:00-05:00', 'photo', 'black coffee', 2.1, 0.3, 0.0, 0.0, 0.0, 0.0, 5.3),
  (9008, '2026-10-27T12:29:00-05:00', 'photo', 'garden salad with vinaigrette and apple', 257.8, 2.6, 36.6, 13.0, 7.8, 25.0, 267.3),
  (9008, '2026-10-27T15:07:00-05:00', 'voice', 'plain greek yogurt and granola bar', 307.0, 21.5, 37.5, 8.3, 2.2, 19.1, 191.7),
  (9008, '2026-10-27T19:03:00-05:00', 'text', 'canned chicken noodle soup and steamed broccoli', 193.6, 11.1, 27.6, 4.8, 5.9, 3.8, 1713.0),
  (9008, '2026-10-28T08:09:00-05:00', 'voice', 'black coffee and apple', 104.6, 0.9, 27.0, 0.3, 4.7, 20.5, 7.6),
  (9008, '2026-10-28T12:57:00-05:00', 'photo', 'plain greek yogurt and granola bar', 298.4, 22.2, 35.7, 7.8, 2.0, 18.5, 186.2),
  (9008, '2026-10-28T15:30:00-05:00', 'voice', 'almonds', 172.0, 6.3, 6.3, 14.7, 3.7, 1.3, 0.0),
  (9008, '2026-10-28T19:10:00-05:00', 'text', 'grilled chicken breast and steamed broccoli', 288.3, 47.3, 10.4, 5.3, 4.7, 1.9, 166.4),
  (9008, '2026-10-29T08:03:00-05:00', 'voice', 'black coffee', 2.1, 0.3, 0.0, 0.0, 0.0, 0.0, 5.3),
  (9008, '2026-10-29T12:04:00-05:00', 'text', 'garden salad with vinaigrette and apple', 244.5, 2.5, 34.1, 12.6, 7.3, 23.3, 258.2),
  (9008, '2026-10-29T15:57:00-05:00', 'photo', 'plain greek yogurt and granola bar', 278.5, 20.0, 33.7, 7.4, 1.9, 17.3, 173.8),
  (9008, '2026-10-29T19:14:00-05:00', 'photo', 'canned chicken noodle soup and steamed broccoli', 191.2, 10.9, 27.1, 4.7, 5.7, 3.7, 1711.8),
  (9008, '2026-10-30T07:56:00-05:00', 'text', 'black coffee and apple', 88.8, 0.8, 22.8, 0.3, 4.0, 17.3, 7.0),
  (9008, '2026-10-30T12:13:00-05:00', 'voice', 'plain greek yogurt and granola bar', 287.7, 21.1, 34.6, 7.6, 2.0, 17.8, 179.5),
  (9008, '2026-10-30T15:49:00-05:00', 'photo', 'almonds', 160.4, 5.9, 5.9, 13.7, 3.4, 1.2, 0.0),
  (9008, '2026-10-30T18:54:00-05:00', 'voice', 'grilled chicken breast and steamed broccoli', 323.6, 53.2, 11.6, 6.0, 5.3, 2.1, 186.3),
  (9008, '2026-10-31T07:52:00-05:00', 'text', 'black coffee', 1.8, 0.3, 0.0, 0.0, 0.0, 0.0, 4.5),
  (9008, '2026-10-31T12:53:00-05:00', 'voice', 'garden salad with vinaigrette and apple', 259.3, 2.6, 37.3, 12.9, 7.9, 25.6, 264.8),
  (9008, '2026-10-31T15:51:00-05:00', 'photo', 'plain greek yogurt and granola bar', 299.7, 21.3, 36.4, 8.0, 2.1, 18.6, 187.1),
  (9008, '2026-10-31T19:01:00-05:00', 'photo', 'canned chicken noodle soup and steamed broccoli', 202.1, 11.5, 28.5, 5.1, 5.8, 3.9, 1836.9);

-- vegetarian_knee
INSERT INTO users (id, name) VALUES (9009, 'test_vegetarian_knee');
INSERT INTO user_prefs (user_id, calorie_goal, protein_goal_g, weight_kg, sodium_limit_mg, diet, goal, fitness_level, allergies, injuries, dislikes) VALUES (9009, '1900', NULL, '65', NULL, 'vegetarian', 'maintain', 'beginner', ARRAY['peanut']::TEXT[], ARRAY['knee']::TEXT[], ARRAY['mushrooms']::TEXT[]);
INSERT INTO meals (user_id, eaten_at, source, name, kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg) VALUES
  (9009, '2026-10-25T08:10:00-05:00', 'text', 'bagel with cream cheese and orange juice', 463.7, 12.9, 80.0, 10.5, 2.5, 26.4, 602.8),
  (9009, '2026-10-25T12:32:00-05:00', 'photo', 'pasta with marinara', 448.7, 15.0, 85.5, 5.3, 6.4, 12.8, 747.8),
  (9009, '2026-10-25T15:34:00-05:00', 'photo', 'granola bar and apple', 276.8, 4.2, 53.3, 6.8, 6.5, 31.2, 113.8),
  (9009, '2026-10-25T18:53:00-05:00', 'text', 'white rice and steamed broccoli and garden salad with vinaigrette', 402.3, 9.6, 66.1, 12.1, 8.4, 6.6, 296.5),
  (9009, '2026-10-26T08:06:00-05:00', 'photo', 'oatmeal with banana and black coffee', 258.8, 6.9, 52.1, 3.8, 6.6, 14.2, 14.2),
  (9009, '2026-10-26T12:31:00-05:00', 'photo', 'mac and cheese', 348.5, 11.0, 44.0, 14.7, 1.8, 5.5, 797.9),
  (9009, '2026-10-26T15:08:00-05:00', 'photo', 'pretzels and apple', 213.9, 3.8, 50.4, 1.2, 5.5, 20.0, 423.8),
  (9009, '2026-10-26T18:40:00-05:00', 'text', 'pasta with marinara and buttered white toast', 618.6, 18.8, 110.9, 11.7, 7.3, 15.7, 1027.4),
  (9009, '2026-10-27T07:43:00-05:00', 'photo', 'bagel with cream cheese and orange juice', 476.4, 13.1, 82.9, 10.6, 2.5, 28.5, 605.4),
  (9009, '2026-10-27T12:25:00-05:00', 'text', 'pasta with marinara', 437.9, 14.6, 83.4, 5.2, 6.3, 12.5, 729.8),
  (9009, '2026-10-27T15:07:00-05:00', 'photo', 'granola bar and apple', 283.0, 4.5, 53.7, 7.2, 6.4, 30.9, 120.5),
  (9009, '2026-10-27T18:44:00-05:00', 'photo', 'white rice and steamed broccoli and garden salad with vinaigrette', 399.6, 9.4, 63.3, 13.2, 8.5, 7.0, 318.2),
  (9009, '2026-10-28T07:33:00-05:00', 'photo', 'oatmeal with banana and black coffee', 246.4, 6.6, 49.6, 3.6, 6.3, 13.5, 14.2),
  (9009, '2026-10-28T12:02:00-05:00', 'text', 'mac and cheese', 347.1, 11.0, 43.8, 14.6, 1.8, 5.5, 794.7),
  (9009, '2026-10-28T15:42:00-05:00', 'voice', 'pretzels and apple', 188.8, 3.2, 44.7, 1.0, 5.1, 18.7, 353.9),
  (9009, '2026-10-28T19:29:00-05:00', 'voice', 'pasta with marinara and buttered white toast', 553.5, 16.9, 99.5, 10.3, 6.6, 14.1, 919.4),
  (9009, '2026-10-29T07:56:00-05:00', 'photo', 'bagel with cream cheese and orange juice', 452.9, 12.4, 79.0, 10.0, 2.4, 27.5, 571.1),
  (9009, '2026-10-29T12:42:00-05:00', 'voice', 'pasta with marinara', 385.9, 12.9, 73.5, 4.6, 5.5, 11.0, 643.2),
  (9009, '2026-10-29T15:55:00-05:00', 'photo', 'granola bar and apple', 277.8, 4.4, 52.7, 7.1, 6.3, 30.3, 118.5),
  (9009, '2026-10-29T18:55:00-05:00', 'text', 'white rice and steamed broccoli and garden salad with vinaigrette', 410.4, 10.0, 67.8, 12.1, 8.9, 6.8, 302.2),
  (9009, '2026-10-30T07:42:00-05:00', 'photo', 'oatmeal with banana and black coffee', 289.1, 7.7, 58.3, 4.2, 7.4, 15.9, 15.2),
  (9009, '2026-10-30T12:08:00-05:00', 'voice', 'mac and cheese', 382.8, 12.1, 48.3, 16.1, 2.0, 6.0, 876.3),
  (9009, '2026-10-30T15:55:00-05:00', 'photo', 'pretzels and apple', 195.5, 3.3, 46.4, 1.0, 5.3, 19.6, 362.6),
  (9009, '2026-10-30T19:05:00-05:00', 'photo', 'pasta with marinara and buttered white toast', 597.5, 18.1, 107.0, 11.4, 7.0, 15.1, 992.3),
  (9009, '2026-10-31T08:23:00-05:00', 'photo', 'bagel with cream cheese and orange juice', 450.8, 12.2, 79.6, 9.7, 2.4, 29.5, 548.3),
  (9009, '2026-10-31T12:59:00-05:00', 'photo', 'pasta with marinara', 459.4, 15.3, 87.5, 5.5, 6.6, 13.1, 765.7),
  (9009, '2026-10-31T15:13:00-05:00', 'voice', 'granola bar and apple', 272.0, 4.2, 52.0, 6.8, 6.3, 30.1, 114.0),
  (9009, '2026-10-31T18:54:00-05:00', 'text', 'white rice and steamed broccoli and garden salad with vinaigrette', 407.9, 9.6, 67.9, 11.8, 8.0, 6.4, 287.0);
SELECT setval('users_id_seq', GREATEST((SELECT max(id) FROM users WHERE id < 9001), 1));

COMMIT;
