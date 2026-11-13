#!/usr/bin/env python3
# wins.py: erigon PRs by AskAlexSharov merged in the last 7 days whose body has a perf table, from the public GitHub search API.
# Writes history/<UTC now>/wins.csv (number,merged_at,title,row): row = the first line with a signed % in the body's first code block.
# Backports ("[r3.8] ...") are left out, so a win counts once.
import csv, datetime, json, re, sys, urllib.request
from pathlib import Path

PCT = re.compile(r"[+-]\d+(\.\d+)?%")


def headline(body):
    m = re.search(r"```[^\n]*\n(.*?)```", body or "", re.S)
    return next((l.strip() for l in m.group(1).splitlines() if PCT.search(l)), None) if m else None


assert headline("x\n```\nrow  change\nfoo  -14.3% (noise ~8%)\nbar  -2%\n```\n```\nz +9%\n```") == "foo  -14.3% (noise ~8%)"
assert headline("```\nbefore after\n0 1\n```") is None and headline(None) is None

now = datetime.datetime.now(datetime.timezone.utc)
since = (now - datetime.timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%SZ")
q = f"repo:erigontech/erigon+is:pr+is:merged+author:AskAlexSharov+merged:>={since}"
items = []
for page in range(1, 11):
    req = urllib.request.Request(f"https://api.github.com/search/issues?q={q}&per_page=100&page={page}", headers={"User-Agent": "vm-bench"})
    with urllib.request.urlopen(req, timeout=60) as r:
        got = json.load(r)
    assert not got["incomplete_results"], "GitHub search returned incomplete results"
    items += got["items"]
    if len(got["items"]) < 100:
        break
rows = sorted(((it["number"], it["pull_request"]["merged_at"], it["title"], headline(it["body"])) for it in items if not it["title"].startswith("[r")),
              key=lambda r: r[1], reverse=True)
rows = [r for r in rows if r[3]]
out = Path(__file__).resolve().parent.parent / "history" / now.strftime("%Y-%m-%dT%H%M")
out.mkdir(exist_ok=True)
with open(out / "wins.csv", "w", newline="") as f:
    csv.writer(f).writerows(rows)
print(f"wins: {len(rows)} of {len(items)} merged PRs have a perf table", file=sys.stderr)
