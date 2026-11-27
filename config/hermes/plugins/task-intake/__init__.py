"""task-intake — the agent's door to the Task panel.

One tool, two verbs:

* ``action="open"``  — read the board the way the panel shows it (NEW and
  IN PROGRESS lanes) as one line per card. No bodies unless asked.
* ``action="file"``  — file a pending card, but only after scoring the
  request against every open card. A strong match returns ``DUPLICATE`` and
  writes nothing; a plausible one returns up to three ``CANDIDATES`` so the
  judgement about intent stays with the model; only a clear board creates.

Why a tool instead of the built-in ``kanban_*`` set: those are fourteen
schemas in every prompt, and ``kanban_list`` hands back every column of every
row. Both surfaces were too expensive for "what's pending, add this one".

Pure helpers (``normalize``, ``tokens``, ``score``) hold the matching rule so
it is testable without a board.
"""

from __future__ import annotations

import logging
import unicodedata
from typing import Any, Iterable, Optional, Sequence

logger = logging.getLogger(__name__)

# The panel's own creator caps (KanbanPanel.qml: titleLimit / descriptionLimit).
TITLE_LIMIT = 80
BODY_LIMIT = 200

# The panel's category axis (KanbanPanel.qml categoryNames): 0 is unclassified,
# 1..4 are C1 urgent, C2 important, C3 necessary, C4 optional. Priority stays
# what it always was -- the rank inside a category.
CATEGORY_MAX = 4


def _ensure_category(conn: Any) -> None:
    """Add the category column if this board predates it (idempotent)."""
    columns = {row[1] for row in conn.execute("PRAGMA table_info(tasks)")}
    if "category" not in columns:
        conn.execute("ALTER TABLE tasks ADD COLUMN category INTEGER NOT NULL DEFAULT 0")
        conn.commit()


def _clean_category(raw: Any) -> Optional[int]:
    """Accept 2, '2', 'C2'. None when it is not a category at all."""
    if raw is None or raw == "":
        return 0
    text = str(raw).strip().upper()
    if text.startswith("C"):
        text = text[1:]
    if not text.isdigit():
        return None
    value = int(text)
    return value if 0 <= value <= CATEGORY_MAX else None

# The panel's lanes: NEW and IN PROGRESS. ``blocked`` sits inside PROCESS.
NEW_LANE = ("triage", "todo", "scheduled", "ready")
PROGRESS_LANE = ("running", "review", "blocked")
OPEN_STATUSES = NEW_LANE + PROGRESS_LANE

# Score ladder. Above DUP a card is the same task; between the two it might
# be, and only the model can say whether the intent matches. The floor is low
# on purpose: a missed duplicate leaves two cards for one job, while a spurious
# candidate costs one short sentence.
DUP_THRESHOLD = 0.86
CANDIDATE_THRESHOLD = 0.35
EXACT_TITLE = 1.0

# Spanish function words: they dominate a short title without carrying intent.
_STOPWORDS = frozenset("""
a al algo ante bajo con contra cual cuando de del desde donde dos el ella
ellas ellos en entre era eres es esa ese eso esos esta estas este esto estos
fue ha hace hacia hasta hay la las le les lo los mas me mi mis mucho muy no
nos o os otra otro para pero poco por porque que quien se sea segun ser si
sin sobre son su sus tambien tanto te tiene tienen todo todos tu tus un una
uno unos y ya
""".split())


# --- matching ---------------------------------------------------------------


def normalize(text: Optional[str]) -> str:
    """Accent-folded, lowercased, punctuation-free text with single spaces."""
    if not text:
        return ""
    folded = unicodedata.normalize("NFKD", str(text))
    folded = "".join(ch for ch in folded if not unicodedata.combining(ch))
    cleaned = "".join(ch if ch.isalnum() else " " for ch in folded.lower())
    return " ".join(cleaned.split())


def tokens(text: Optional[str]) -> set[str]:
    """Content words of *text*: normalized, stopwords and single letters gone."""
    return {word for word in normalize(text).split() if len(word) > 1 and word not in _STOPWORDS}


def _jaccard(left: set[str], right: set[str]) -> float:
    if not left or not right:
        return 0.0
    shared = len(left & right)
    return shared / (len(left) + len(right) - shared)


def _containment(left: set[str], right: set[str]) -> float:
    """Share of the shorter title that already lives in the other one.

    Jaccard punishes the case that matters most: two people name the same job
    with a different verb and a different length. Half of the shorter title's
    content words appearing in the other is signal, not noise.
    """
    if not left or not right:
        return 0.0
    return len(left & right) / min(len(left), len(right))


def score(title: str, body: Optional[str], other_title: str, other_body: Optional[str]) -> float:
    """How likely ``title``/``body`` is the same task as the other pair.

    Four readings, best wins: the title is literally the same after folding, the
    titles overlap as sets, most of the shorter title is contained in the other,
    or the whole text (title plus body) overlaps — which is what catches a
    request restated with different words.
    """
    folded, other_folded = normalize(title), normalize(other_title)
    if folded and folded == other_folded:
        return EXACT_TITLE
    left, right = tokens(title), tokens(other_title)
    title_overlap = _jaccard(left, right)
    text_overlap = _jaccard(left | tokens(body), right | tokens(other_body))
    return max(
        title_overlap,
        0.75 * _containment(left, right),
        0.6 * text_overlap + 0.4 * title_overlap,
    )


# --- board access -----------------------------------------------------------


def _board_path():
    from hermes_cli import kanban_db as kb

    return kb.kanban_db_path()


def _board_available() -> bool:
    """check_fn: the tool is meaningless without a board on disk."""
    try:
        return _board_path().is_file()
    except Exception:
        return False


def _open_rows(limit: int) -> list[Any]:
    from hermes_cli import kanban_db_connect as kbc

    marks = ",".join("?" * len(OPEN_STATUSES))
    with kbc.connect_closing() as conn:
        _ensure_category(conn)
        return conn.execute(
            "SELECT id, title, body, status, assignee, category, priority FROM tasks "
            f"WHERE status IN ({marks}) "
            "ORDER BY (category = 0), category, (priority = 0), priority, created_at DESC "
            "LIMIT ?",
            (*OPEN_STATUSES, max(1, limit)),
        ).fetchall()


def _lane_of(status: str) -> str:
    return "new" if status in NEW_LANE else "progress"


def _one_line(row: Any, *, with_body: bool) -> str:
    marks = f"C{row['category'] or 0} P{row['priority'] or 0}"
    line = f"{row['id']} {row['status']} {row['assignee'] or '-'} {marks} {row['title']}"
    if with_body and row["body"]:
        body = " ".join(str(row["body"]).split())
        line += f" | {body[:160]}"
    return line


def _read(args: dict[str, Any]) -> str:
    lane = str(args.get("lane") or "all").lower()
    statuses = NEW_LANE if lane == "new" else PROGRESS_LANE if lane == "progress" else OPEN_STATUSES
    limit = int(args.get("limit") or 20)
    with_body = bool(args.get("with_body"))

    from hermes_cli import kanban_db_connect as kbc

    marks = ",".join("?" * len(statuses))
    with kbc.connect_closing() as conn:
        _ensure_category(conn)
        rows = conn.execute(
            "SELECT id, title, body, status, assignee, category, priority FROM tasks "
            f"WHERE status IN ({marks}) "
            "ORDER BY (category = 0), category, (priority = 0), priority, created_at DESC "
            "LIMIT ?",
            (*statuses, max(1, limit)),
        ).fetchall()

    if not rows:
        return f"open 0 — no cards in {lane}"
    head = f"open {len(rows)} ({sum(_lane_of(r['status']) == 'new' for r in rows)} new, "
    head += f"{sum(_lane_of(r['status']) == 'progress' for r in rows)} progress)"
    return "\n".join([head, *(_one_line(row, with_body=with_body) for row in rows)])


# --- intake -----------------------------------------------------------------


def _clean_title(raw: Any) -> Optional[str]:
    title = " ".join(str(raw or "").split())
    if not title:
        return None
    if len(title) > TITLE_LIMIT:
        return None
    return title


def _clean_body(raw: Any) -> Optional[str]:
    body = " ".join(str(raw or "").split())
    if not body or len(body) > BODY_LIMIT:
        return None
    return body


def _scored(title: str, body: Optional[str]) -> list[tuple[float, Any]]:
    scored = [(score(title, body, row["title"], row["body"]), row) for row in _open_rows(200)]
    return sorted(scored, key=lambda pair: pair[0], reverse=True)


def _file(args: dict[str, Any]) -> str:
    raw_title, raw_body = args.get("title"), args.get("body")
    title = _clean_title(raw_title)
    if title is None:
        raw = " ".join(str(raw_title or "").split())
        return (
            f"ERROR title must be 1-{TITLE_LIMIT} characters (got {len(raw)}); "
            "shorten it and keep the detail in body"
        )
    body = _clean_body(raw_body)
    if body is None:
        raw = " ".join(str(raw_body or "").split())
        return (
            f"ERROR body must be 1-{BODY_LIMIT} characters (got {len(raw)}); "
            "state what has to change and which file or surface"
        )

    force = bool(args.get("force"))
    category = _clean_category(args.get("category"))
    if category is None:
        return (
            f"ERROR category must be C0..C{CATEGORY_MAX} "
            "(C1 urgent, C2 important, C3 necessary, C4 optional)"
        )
    scored = _scored(title, body)

    if not force:
        duplicate = next(((s, row) for s, row in scored if s >= DUP_THRESHOLD), None)
        if duplicate:
            s, row = duplicate
            return (
                f"DUPLICATE {row['id']} ({s:.2f}) {row['status']} "
                f'"{row["title"]}" — nothing created'
            )
        candidates = [pair for pair in scored if pair[0] >= CANDIDATE_THRESHOLD][:3]
        if candidates:
            lines = [
                f"CANDIDATES {len(candidates)} — nothing created; if none is the same intent, "
                "call again with force=true"
            ]
            lines += [f"  {row['id']} ({s:.2f}) {row['status']} \"{row['title']}\"" for s, row in candidates]
            return "\n".join(lines)

    from hermes_cli import kanban_db as kb
    from hermes_cli import kanban_db_connect as kbc

    assignee = str(args.get("assignee") or "").strip() or None
    priority = int(args.get("priority") or 0)
    with kbc.connect_closing() as conn:
        _ensure_category(conn)
        task_id = kb.create_task(
            conn, title=title, body=body, assignee=assignee,
            created_by="hermes", priority=priority,
        )
        # create_task owns the schema up to its own columns; the category is the
        # panel's axis, so it lands here, on the row this call just made.
        if category:
            conn.execute("UPDATE tasks SET category = ? WHERE id = ?", (category, task_id))
            conn.commit()

    note = "" if assignee else " (unassigned: shows in NEW, never dispatched)"
    return f'CREATED {task_id} C{category} "{title}"{note}'


# --- tool surface -----------------------------------------------------------

SCHEMA: dict[str, Any] = {
    "name": "task_intake",
    "description": (
        "Task panel (kanban), compact. "
        "action=open: one line per new/in-progress card. "
        "action=file: scores the card against every open one before writing — DUPLICATE creates "
        "nothing, CANDIDATES asks you to judge intent (re-call with force=true if it differs). "
        f"title<={TITLE_LIMIT}, body<={BODY_LIMIT}."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "action": {"type": "string", "enum": ["open", "file"]},
            "lane": {"type": "string", "enum": ["new", "progress", "all"], "description": "Read: lane (default all)."},
            "limit": {"type": "integer", "description": "Read: max cards (20)."},
            "with_body": {"type": "boolean", "description": "Read: include body preview."},
            "title": {"type": "string", "description": f"File: what the card is, <= {TITLE_LIMIT} chars."},
            "body": {"type": "string", "description": f"File: what has to change, <= {BODY_LIMIT} chars."},
            "assignee": {"type": "string", "description": "File: profile to dispatch; omit = pending."},
            "category": {"type": "string", "description": "File: C1 urgent, C2 important, C3 necessary, C4 optional; omit = C0."},
            "priority": {"type": "integer", "description": "File: rank inside the category, 1-9; omit = 0."},
            "force": {"type": "boolean", "description": "File: create despite CANDIDATES."},
        },
        "required": ["action"],
    },
}


def _handle(args: dict[str, Any], **_kwargs: Any) -> str:
    action = str(args.get("action") or "").strip().lower()
    try:
        if action == "open":
            return _read(args)
        if action == "file":
            return _file(args)
        return "ERROR action must be 'open' or 'file'"
    except Exception as exc:  # noqa: BLE001 - the tool must answer, never raise into the turn
        logger.warning("task_intake %s failed: %s", action or "?", exc, exc_info=True)
        return f"ERROR task_intake {action or '?'}: {exc}"


def register(ctx) -> None:
    ctx.register_tool(
        name="task_intake",
        toolset="task_intake",
        schema=SCHEMA,
        handler=_handle,
        check_fn=_board_available,
        description="Compact Task panel intake: list new/in-progress cards, file one after dedupe",
    )
