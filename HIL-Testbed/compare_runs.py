import argparse
import json
from pathlib import Path


def table(rows):
    """Groups results by scenario, device kind and check, keeping each device's verdict."""
    out = {}
    for r in rows:
        if r["verdict"] in ("pass", "fail"):
            out.setdefault((r["scenario"], r["kind"], r["test"]), {})[r["device"]] = r["verdict"]
    return out


def between_devices(rows):
    """Lists the checks where devices of the same kind disagreed in one run."""
    return [(key, found) for key, found in sorted(table(rows).items()) if len(set(found.values())) > 1]


def between_runs(a, b):
    """Compares two runs check by check; a check passes in a run only if every required device passed it."""
    keep = lambda rows: [r for r in rows if r["failure_type"] != "compatibility"]
    ta, tb = table(keep(a)), table(keep(b))
    verdict = lambda found: "fail" if "fail" in found.values() else "pass"
    shared = sorted(set(ta) & set(tb))
    differ = [(key, verdict(ta[key]), verdict(tb[key])) for key in shared if verdict(ta[key]) != verdict(tb[key])]
    return shared, differ, len(set(ta) - set(tb)), len(set(tb) - set(ta))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Shows where two test runs disagree, e.g. the virtual stage and the Pi")
    parser.add_argument("first", help="results file, e.g. results/virtual-....json")
    parser.add_argument("second", help="results file, e.g. results/physical-....json")
    args = parser.parse_args()
    a, b = (json.loads(Path(p).read_text(encoding="utf-8")) for p in (args.first, args.second))
    shared, differ, only_a, only_b = between_runs(a["results"], b["results"])
    name_a, name_b = a["summary"]["stage"], b["summary"]["stage"]
    print(f"{len(shared)} checks in both runs, {len(shared) - len(differ)} agree, {len(differ)} differ")
    print(f"{only_a} checks only in the {name_a} run, {only_b} only in the {name_b} run")
    for (scenario, kind, test), va, vb in differ:
        print(f"  {scenario} {kind} {test}: {name_a} {va}, {name_b} {vb}")
