#!/usr/bin/env bash
# hypridle condition: exit 0 = on battery (suspend), exit 1 = on AC (defer).
set -u

for f in /sys/class/power_supply/*/online; do
    [[ -f $f ]] || continue
    if [[ $(cat "$f" 2>/dev/null) == "1" ]]; then
        exit 1
    fi
done

exit 0
