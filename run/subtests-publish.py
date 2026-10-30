#!/usr/bin/env python3
"""run/subtests-publish.py <run/subtests.sh output> [arm=label ...]: a new history/<UTC time>/ with subtests.csv and subtest-arms.csv.
Arms keep their order in the run, which the page reads as base build first; an arm without a label is labelled with its name.
Then run/history.py rebuilds the page."""
import csv, sys, time
from pathlib import Path

root = Path(__file__).resolve().parent.parent
rows = []
for r in csv.reader(open(sys.argv[1])):
    # older outputs have the sub-test name unquoted, so its commas split it
    rows.append([r[0], ",".join(r[1:-4]), r[-4], *map(int, r[-3:])])
arms = list(dict.fromkeys(r[2] for r in rows))
labels = dict(a.split("=", 1) for a in sys.argv[2:])
if set(labels) - set(arms):
    sys.exit(f"no rows for arm {', '.join(sorted(set(labels) - set(arms)))}; arms in {sys.argv[1]}: {', '.join(arms)}")
snap = root / "history" / time.strftime("%Y-%m-%dT%H%M", time.gmtime())
snap.mkdir(parents=True)
csv.writer(open(snap / "subtests.csv", "w", newline=""), lineterminator="\n").writerows(rows)
csv.writer(open(snap / "subtest-arms.csv", "w", newline=""), lineterminator="\n").writerows([a, labels.get(a, a)] for a in arms)
print(snap)
