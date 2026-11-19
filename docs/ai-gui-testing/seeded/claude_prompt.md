# Prompt for the blind Claude run

Paste into a **fresh** Claude Code session that has the iOS Simulator tool. Replace `<UDID>` and `<LOG PATH>`.
Do not add hints about what is wrong with the app.

---

You are a QA tester exploring an iOS app called BellAI, a personal assistant. It is already running in the iOS Simulator (device UDID <UDID>), on its Home screen.

Your job: explore the app through its user interface and report anything that looks broken: unreadable or low-contrast text, overlapping or cut-off elements, error messages, misleading labels, empty or stuck loading states, controls that do not do what they should. Do NOT report things that look fine. Do NOT send email, delete anything or press destructive buttons.

STRICT RULES (this is a controlled experiment, so they matter):
- Use ONLY the tool mcp__Claude_Code_iOS_Simulator__control (actions: screenshot, tap, swipe, press_key, text, etc.). If its schema is not loaded, load it with ToolSearch query "select:mcp__Claude_Code_iOS_Simulator__control". Coordinates are device points on a 402x874 screen, origin top-left.
- Do NOT read, search or list any files or folders (no Read, Grep, Glob, Bash, or similar), and do not look at source code or the repository. Judge the app only from what you see on screen.
- Do not use any other tools except the one Write call at the end described below. Do not restart, rebuild or reinstall the app, and do not change the simulator's appearance or settings.
- Budget: at most 40 ACTIONS (each tap, swipe, key press or text entry counts as one action; screenshots do not count). Stop earlier if you have genuinely explored everything.

Method: take a screenshot, note what is on screen and any problem you see on THAT screen, choose the next control to use, perform it, and repeat. Visit every tab and every screen you can reach.

When finished, write a log with the Write tool to exactly this path:
<LOG PATH>/steps.jsonl
One JSON object per line, one line per action you performed, in order, with exactly these keys:
{"step": <int>, "observation": "<what was on screen before the action, one sentence>", "bug": null or "<one concrete problem visible on that screen, in your own words>", "tapped": "<label of what you tapped or did>"}
Report each distinct problem on the step where you first saw it, and also repeat it on later steps only if you see it again on a new screen. Use null when the screen looked fine. After writing the file, reply with a short summary: number of actions used, screens visited, and the list of problems you reported.
