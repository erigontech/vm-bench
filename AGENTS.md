# Agent guide

Read `.claude/skills/vm-bench/SKILL.md` before any change: the fairness rules, the tiers, the refresh procedure for
main and dbg, and the page check. This file only adds what an agent gets wrong without it.

- **Decide before measuring.** Write the question, the arms (shas), the metric and the stop rule first. Smoke one test
  end to end on the real binary before a long run.
- **One box, one lock, one run.** Every script takes `BENCH_LOCK`. Never build or profile on a box while a run holds it.
  Long runs go detached (`setsid nohup ... &`), and the log ends with a `*_DONE` marker to wait on.
- **Never edit numbers by hand.** A snapshot comes only from a script; a wrong number is fixed in the harness and
  re-measured. Delete a void snapshot instead of footnoting it.
- **Every page change:** `run/history.py`, the JS OK check from the skill, a headless screenshot when the layout moved.
  Commit `run/page.html` and `docs/index.html` together.
- **Writing:** short sentences, verdict first, compact tables. No box names, run counts, ticket or agent names on the
  page or in the README. Commits `area: subject`, no attribution lines.
- **Fixtures are pinned** by tag and sha256 (EEST `tests-benchmark@v0.0.9`; BAL-on set by `run/balfix.sh` digest). A new
  fixture set starts a new series; never mix it into an old trend.
