#!/usr/bin/env python3
"""Task readout and mutations for the desktop kanban panel.

Reads and writes through `hermes kanban` (SQLite-backed). Mutations that the
CLI already exposes go through it, so the panel never reimplements board rules.
The one exception is the category axis: `hermes kanban` has no --category on
create or edit, so this helper owns that column directly and treats it as its
own bookkeeping next to the CLI's `priority`.

Usage:
    kanban-feed.py                 # {"tasks": [...], "error": null}
    kanban-feed.py --pretty        # same thing, indented, for a human
    kanban-feed.py act <args...>   # run `hermes kanban <args...>`, print
                                   # {"ok": true, "error": null} and refresh
                                   # on the next list call

Two axes, deliberately separate:
    category  1..4  C1 urgent, C2 important, C3 necessary, C4 optional; 0 = none
    priority  1..9  P1..P9, the rank *inside* its category
"""

from __future__ import annotations

import json
import os
import shutil
import sqlite3
import subprocess
import sys
from pathlib import Path

HOME = Path.home()

CATEGORY_MIN = 0
CATEGORY_MAX = 4

# The lease the panel takes when it moves a card into IN PROGRESS, in seconds.
# Nothing heartbeats a claim made from here, so the daemon returns the card to
# ready when it expires; eight hours keeps the gesture useful for a workday.
CLAIM_TTL = 28800


def find_hermes() -> str | None:
    found = shutil.which("hermes")
    if found:
        return found
    fallback = HOME / ".hermes" / "hermes-agent" / ".hermes" / "bin" / "hermes"
    if fallback.exists():
        return str(fallback)
    return None


def db_path() -> Path:
    pinned = os.environ.get("HERMES_KANBAN_DB")
    if pinned:
        return Path(pinned)
    return HOME / ".hermes" / "kanban.db"


def connect() -> sqlite3.Connection | None:
    """Open the board DB, adding the category column if this is the first run."""
    path = db_path()
    if not path.exists():
        return None
    try:
        conn = sqlite3.connect(str(path), timeout=5.0)
        conn.execute("PRAGMA busy_timeout = 5000")
        columns = {row[1] for row in conn.execute("PRAGMA table_info(tasks)")}
        if "category" not in columns:
            conn.execute("ALTER TABLE tasks ADD COLUMN category INTEGER NOT NULL DEFAULT 0")
            conn.commit()
    except sqlite3.Error:
        return None
    return conn


def parse_category(raw) -> int | None:
    """Accept 2, '2', 'C2', 'c2'. None when it is not a usable category."""
    if isinstance(raw, int) and not isinstance(raw, bool):
        value = raw
    elif isinstance(raw, str):
        text = raw.strip().upper()
        if text.startswith("C"):
            text = text[1:]
        if not text.isdigit():
            return None
        value = int(text)
    else:
        return None
    if CATEGORY_MIN <= value <= CATEGORY_MAX:
        return value
    return None


def read_categories(conn: sqlite3.Connection | None, ids: list[str]) -> dict[str, int]:
    if conn is None or not ids:
        return {}
    marks = ",".join("?" for _ in ids)
    try:
        rows = conn.execute(
            f"SELECT id, category FROM tasks WHERE id IN ({marks})", ids
        ).fetchall()
    except sqlite3.Error:
        return {}
    return {row[0]: int(row[1] or 0) for row in rows}


def write_category(task_id: str, category: int) -> str | None:
    conn = connect()
    if conn is None:
        return "the board database is not readable"
    try:
        with conn:
            cursor = conn.execute(
                "UPDATE tasks SET category = ? WHERE id = ?", (category, task_id)
            )
            if cursor.rowcount == 0:
                return f"no task with id {task_id}"
    except sqlite3.Error as exc:
        return str(exc)
    finally:
        conn.close()
    return None


def run_kanban(args: list[str]) -> tuple[int, str, str]:
    binary = find_hermes()
    if binary is None:
        return 127, "", "hermes binary not found on PATH"
    try:
        proc = subprocess.run(
            [binary, "kanban", *args],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        return 124, "", "hermes kanban timed out"
    except OSError as exc:
        return 127, "", str(exc)
    return proc.returncode, proc.stdout, proc.stderr


def slim(task: dict, categories: dict[str, int]) -> dict:
    task_id = task.get("id")
    return {
        "id": task_id,
        "title": task.get("title") or "(untitled)",
        "body": task.get("body"),
        "status": task.get("status"),
        "priority": task.get("priority") or 0,
        "category": categories.get(task_id, 0) if task_id else 0,
    }


def do_list() -> dict:
    code, out, err = run_kanban(["list", "--json"])
    if code != 0:
        return {"tasks": [], "error": err.strip() or f"kanban list exited {code}"}
    try:
        tasks = json.loads(out or "[]")
    except json.JSONDecodeError:
        return {"tasks": [], "error": "kanban list printed invalid JSON"}
    if not isinstance(tasks, list):
        return {"tasks": [], "error": "kanban list returned an object, not a list"}
    rows = [t for t in tasks if isinstance(t, dict)]
    conn = connect()
    try:
        categories = read_categories(
            conn, [t["id"] for t in rows if isinstance(t.get("id"), str)]
        )
    finally:
        if conn is not None:
            conn.close()
    return {"tasks": [slim(t, categories) for t in rows], "error": None}


def created_id(raw: str) -> str | None:
    """Pull the new task id out of `create --json`, whatever shape it printed."""
    try:
        parsed = json.loads(raw or "null")
    except json.JSONDecodeError:
        return None
    if isinstance(parsed, list):
        parsed = parsed[0] if parsed else None
    if isinstance(parsed, str):
        return parsed
    if isinstance(parsed, dict):
        for key in ("id", "task_id"):
            value = parsed.get(key)
            if isinstance(value, str) and value:
                return value
        task = parsed.get("task")
        if isinstance(task, dict) and isinstance(task.get("id"), str):
            return task["id"]
    return None


def take_category_flag(args: list[str]) -> tuple[list[str], int | None]:
    """Strip --category/--category= out of the args meant for the CLI."""
    kept: list[str] = []
    category: int | None = None
    index = 0
    while index < len(args):
        arg = args[index]
        if arg == "--category":
            if index + 1 < len(args):
                category = parse_category(args[index + 1])
                if category is None:
                    return args, -1
            index += 2
            continue
        if arg.startswith("--category="):
            category = parse_category(arg.split("=", 1)[1])
            if category is None:
                return args, -1
            index += 1
            continue
        kept.append(arg)
        index += 1
    return kept, category


def do_reopen(task_id: str) -> dict:
    """review -> in progress, which the CLI does not have as one command.

    ``request-changes`` leaves the card in review (it only records what has to
    change) and ``reopen-review`` returns it to ready. The board's only way back
    into IN PROGRESS is that pair: reopen the review, then take the lease again.
    """
    code, out, err = run_kanban(
        ["reopen-review", task_id, "--reason", "Returned to work from review"]
    )
    if code != 0:
        return {"ok": False, "error": err.strip() or f"reopen-review exited {code}", "output": out}
    code, out, err = run_kanban(["claim", task_id, "--ttl", str(CLAIM_TTL)])
    if code != 0:
        return {"ok": False, "error": err.strip() or f"claim exited {code}", "output": out}
    return {"ok": True, "error": None, "output": out.strip()}


def do_act(args: list[str]) -> dict:
    if not args:
        return {"ok": False, "error": "no action given", "output": ""}

    if args[0] == "reopen":
        if len(args) != 2:
            return {"ok": False, "error": "usage: reopen <task-id>", "output": ""}
        return do_reopen(args[1])

    if args[0] == "categorize":
        if len(args) != 3:
            return {"ok": False, "error": "usage: categorize <task-id> <C0-C4>", "output": ""}
        category = parse_category(args[2])
        if category is None:
            return {"ok": False, "error": "a category is C0..C4", "output": ""}
        error = write_category(args[1], category)
        return {"ok": error is None, "error": error, "output": ""}

    cli_args, category = take_category_flag(args)
    if category == -1:
        return {"ok": False, "error": "a category is C0..C4", "output": ""}

    code, out, err = run_kanban(cli_args)
    if code != 0:
        return {"ok": False, "error": err.strip() or f"exited {code}", "output": out}

    # A create that carried a category: the CLI cannot store it, so pin it on
    # the row it just made. A failure here is reported, never swallowed: the
    # card exists but unclassified, and the panel must say so.
    if category is not None and cli_args and cli_args[0] == "create":
        task_id = created_id(out)
        if task_id is None:
            return {"ok": False, "error": "created, but the category could not be applied", "output": out}
        error = write_category(task_id, category)
        if error is not None:
            return {"ok": False, "error": "created without category: " + error, "output": out}

    return {"ok": True, "error": None, "output": out.strip()}


def main(argv: list[str]) -> int:
    if argv and argv[0] == "act":
        blob = do_act(argv[1:])
    else:
        blob = do_list()
    pretty = "--pretty" in argv
    print(json.dumps(blob, indent=2 if pretty else None, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
