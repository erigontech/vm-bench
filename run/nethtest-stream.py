#!/usr/bin/env python3
"""Blockchain-test files through one nethtest process (its -x stdin mode), so the dotnet start-up is paid once;
each file and its no-block twin are fed REPEAT times, best wall time each.
usage: run/nethtest-stream.py <nethtest> <repeat> <fixture>...   -> file,nethermind,gas,ms,twin_ms per fixture"""
import json, subprocess, sys, time

nethtest, repeat, files = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
p = subprocess.Popen([nethtest, "-b", "--parallelExecution", "false", "-j", "-n", "-x"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)

def run_one(path):
    start = time.perf_counter()
    p.stdin.write(path + "\n"); p.stdin.flush()
    depth, buf, seen = 0, [], False
    while True:  # the answer is one JSON array: read until its brackets balance
        line = p.stdout.readline()
        if not line: raise RuntimeError("nethtest exited")
        buf.append(line); depth += line.count("[") - line.count("]"); seen = seen or "[" in line
        if seen and depth == 0: break
    elapsed = (time.perf_counter() - start) * 1e3
    results = json.loads("".join(buf))
    return elapsed, bool(results) and all(r.get("pass") for r in results)

def best(path):
    b, ok = None, True
    for _ in range(repeat):
        ms, passed = run_one(path); ok = ok and passed
        b = ms if b is None or ms < b else b
    return b, ok

for f in files:
    name = f.removeprefix("blocktests/eest/").removesuffix(".json")
    gas = sum(int(b["blockHeader"]["gasUsed"], 16) for t in json.load(open(f)).values() for b in t["blocks"])
    ms, ok = best(f)
    tw, ok2 = best(f.replace("blocktests/eest/", "blocktests/eest-twin/", 1))
    if ok and ok2: print(f"{name},nethermind,{gas},{ms:.0f},{tw:.0f}", flush=True)
    else: print(f"nethermind: {name} failed", file=sys.stderr)
p.stdin.write("\n"); p.stdin.close(); p.wait(timeout=60)
