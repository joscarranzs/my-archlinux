#!/usr/bin/env python3
"""Print Hyprland's socket2 event stream to stdout, one line per event.

The bar polls `hyprctl` for the source of truth; this stream only says "something
changed, refresh now", which is what makes the indicator react in milliseconds
instead of on the next timer tick. Exits quietly when there is no socket, so a
bar started outside a Hyprland session does not spawn a loop of failures.
"""

import os
import socket
import sys


def main() -> int:
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    if not signature:
        return 0
    path = os.path.join(runtime, "hypr", signature, ".socket2.sock")
    conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        conn.connect(path)
    except OSError:
        return 0
    try:
        with conn, conn.makefile("r", encoding="utf-8", errors="replace") as stream:
            for line in stream:
                sys.stdout.write(line)
                sys.stdout.flush()
    except BrokenPipeError:
        # The consumer (the bar) went away. Exit quietly: a traceback here is
        # noise in the journal, and Python's shutdown flush would print a second
        # "Exception ignored" unless stdout is pointed at devnull first.
        devnull = os.open(os.devnull, os.O_WRONLY)
        os.dup2(devnull, sys.stdout.fileno())
    return 0


if __name__ == "__main__":
    sys.exit(main())
