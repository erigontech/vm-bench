#!/usr/bin/env python3
"""balfix-digest.py <fixtures dir>: "<tests> <sha256>" over the sorted "<test> <_info.hash>" lines of the Amsterdam engine_x fixtures."""
import glob, hashlib, json, sys

lines = sorted(f"{n} {t['_info']['hash']}\n" for f in glob.glob(f"{sys.argv[1]}/blockchain_tests_engine_x/for_amsterdam_at_0150M/**/*.json", recursive=True)
               for n, t in json.load(open(f)).items())
print(len(lines), hashlib.sha256("".join(lines).encode()).hexdigest())
