#!/usr/bin/env python3
"""Count how many times capslock-state.sh is spawned inside a time window.

The lockscreen used to poll the compositor every 500 ms for as long as it stayed
up, which measured at two spawns a second, each one bash + python3 + hyprctl.
The count is the regression test for that: an idle card spawns the script once
(when it appears) and never again.

Matching is on the script's own command line in /proc, never through `pgrep -f`:
a pattern that also appears in the probing command's own command line matches
itself, and that is how the first measurement of this number came out wrong.
"""

import os
import sys
import time

window = float(sys.argv[1]) if len(sys.argv) > 1 else 3.0
delay = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0

# The delay is not decoration. The card is supposed to look when a key is typed
# or an attempt fails, and a harness that drives those states makes it spawn on
# purpose; waiting out the harness's own input is what isolates "idle".
if delay > 0:
    time.sleep(delay)

seen = set()
deadline = time.time() + window
while time.time() < deadline:
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or pid in seen:
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as handle:
                command = handle.read()
        except OSError:
            continue
        if b"capslock-state.sh" in command:
            seen.add(pid)
    time.sleep(0.002)

print(len(seen))
