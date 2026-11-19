"""Scores the GUI testers against the known bugs in bugs.json.

Every bug a tester reported (the "bug" of a step in steps.jsonl) is matched to the known bugs by their patterns,
and one report can match several. A report that matches none counts as an environment artifact (a server that
is not running) or as other, which still needs reading by hand because the app has real bugs that are not in
bugs.json.

Usage: python3 score.py bugs.json <run folder>...
Runs are grouped by the folder they are in, so runs/small/1 and runs/small/2 are the small group. It prints JSON
with the runs, steps, reports, matches, recall and what each known bug got, per group.
"""
import collections
import json
import pathlib
import re
import sys

ENV = re.compile(r"couldn.t connect|could not connect|connection|voice|server")


def classify(bugs, text):
    # Returns the ids of the known bugs the report matches, or ENV, or OTHER.
    text = text.lower()
    found = {b["id"] for b in bugs if any(re.search(p, text) for p in b["match"])}
    return found or ({"ENV"} if ENV.search(text) else {"OTHER"})


def score(bugs, runs):
    seen = collections.Counter()  # Maps a known bug id to the number of runs that found it.
    other = collections.Counter()
    steps = reports = matched = env = 0
    for run in runs:
        found = set()
        rows = [json.loads(line) for line in open(run / "steps.jsonl")]
        steps += len(rows)
        for row in rows:
            if not row.get("bug"):
                continue
            reports += 1
            kind = classify(bugs, row["bug"])
            if kind == {"ENV"}:
                env += 1
            elif kind == {"OTHER"}:
                other[row["bug"].strip()[:110]] += 1
            else:
                matched += 1
                found |= kind
        seen.update(found)
    return {"runs": len(runs), "steps": steps, "reports": reports, "tp": matched, "env": env, "other": sum(other.values()),
            "recall": round(sum(seen.values()) / (len(runs) * len(bugs)), 2),
            "per_bug": {b["id"]: f"{seen[b['id']]}/{len(runs)}" for b in bugs}, "others": other.most_common(8)}


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("usage: python3 score.py bugs.json <run folder>...")
    groups = collections.defaultdict(list)
    for folder in sys.argv[2:]:
        path = pathlib.Path(folder)
        groups[path.parent.name].append(path)
    bugs = json.load(open(sys.argv[1]))
    print(json.dumps({name: score(bugs, runs) for name, runs in sorted(groups.items())}, indent=1))
