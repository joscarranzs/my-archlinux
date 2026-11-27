#!/usr/bin/env bash
# Print 1 if the main keyboard has Caps Lock enabled, otherwise 0.
hyprctl devices -j 2>/dev/null | /usr/bin/python3 -c '
import sys, json
raw = sys.stdin.read().strip()
if not raw:
    print(0)
    raise SystemExit
try:
    data = json.loads(raw)
except ValueError:
    print(0)
    raise SystemExit
if not isinstance(data, dict):
    print(0)
    raise SystemExit
for kb in data.get("keyboards", []):
    if kb.get("main"):
        print(1 if kb.get("capsLock") else 0)
        raise SystemExit
print(0)
'
