#!/usr/bin/env python3
"""Build docs/index.html from history/*/: the latest table and Mgas/s over time per client."""
import csv, json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
runs = []
for d in sorted(p for p in (root / "history").iterdir() if p.is_dir()):
    run = {"date": d.name, "versions": {}, "ns": {}}
    for f in d.glob("*.csv"):
        if f.name == "versions.csv":
            run["versions"] = dict(csv.reader(open(f)))
            continue
        for fixture, client, ns in csv.reader(open(f)):
            run["ns"].setdefault(fixture, {})[client] = int(ns)
    runs.append(run)
gas = {p.parent.name + "/" + p.stem: int(next(iter(json.load(open(p)).values()))["_info"]["gasUsed"], 16)
       for p in (root / "fixtures").glob("*/*.json")}
html = (root / "run" / "page.html").read_text().replace("/*DATA*/", json.dumps({"runs": runs, "gas": gas}))
(root / "docs").mkdir(exist_ok=True)
(root / "docs" / ".nojekyll").touch()
(root / "docs" / "index.html").write_text(html)
