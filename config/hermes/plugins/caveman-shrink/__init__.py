"""Caveman Shrink — deterministic output compressor for the `terminal` tool.

The idea is stolen from caveman's "read less" rock, not its code: it ships that
compressor inside its own Go proxy because the Claude/Codex hook APIs cannot
rewrite tool output. Hermes can (`transform_terminal_output`), so this runs as a
plain plugin with no proxy, no account and no network.

Contract (website/docs/user-guide/features/hooks.md):

    transform_terminal_output(command, output, returncode, task_id, env_type)
        -> str   replaces what the model reads
        -> None  leaves it untouched

Two rules govern everything here:

1. **Payload is verbatim.** Error lines, tracebacks, paths, counts and exit
   status are copied, never paraphrased. A summary that invents or rounds a
   number is worse than no summary.
2. **Fail open.** Unknown shape, ambiguous format, thin win, or any exception
   returns None. The output then reaches the model exactly as it was produced.
   A plugin must never be the reason a command's result is missing.
3. **The footer is a promise.** Hermes only writes an overflow spill when the
   capture itself blows past its ceiling, so a 30 KB shrink would otherwise
   advertise a file that was never created. We write the untouched text
   ourselves and print that path; if the write fails the footer says so.

"""

from __future__ import annotations

import json
import os
import re
import time
from pathlib import Path

# --------------------------------------------------------------------------- #
# Thresholds
# --------------------------------------------------------------------------- #

# Below this the summary costs more attention than it saves. 2048 rather than
# 4096: over a bench of real captures, mid-size output (2.5-3 KB logs and test
# runs) shrink ~24% with every decisive line kept, while the old floor left all
# of them untouched. Nothing else changed: above 4 KB both floors behave alike.
MIN_BYTES = 2048

# A shrink that keeps more than this share of the original is not worth the risk
# of dropping a fact; the caller gets the original instead. Measured: 0.50 saved
# fewer tokens overall (it declined more files than it tightened) and 0.70
# changed nothing measurable.
MAX_KEEP_RATIO = 0.60

# Hard ceiling on what a summary may cost. Past this the oldest spans go first:
# in a log or a test run the interesting part is almost always at the end.
# Measured: 8_000 bought only ~2% more total saving on real spills, cost 4 points
# of decisive-line retention, and pushed the thin-win floor up to 13.3 KB — past
# that every log shrinks no matter how much of it mattered. Not worth it.
MAX_SUMMARY_BYTES = 12_000

# Where the untouched output is parked so the footer can promise a real path.
# Hermes only spills to this directory when the capture itself overflows, which
# leaves every shrink between MIN_BYTES and that ceiling with no recovery copy.
SPILL_MAX_AGE_S = 7 * 24 * 3600

# --------------------------------------------------------------------------- #
# Detection
# --------------------------------------------------------------------------- #

# Two tiers on purpose. Uppercase severity tokens and exception/traceback shapes
# are real signal. A bare lowercase "error" is not: Hermes logs carry
# ``"error": null`` on every structured line, which alone kept 165 of 400 lines
# in a journal sample.
_HARD = re.compile(
    r"(?:"
    r"\b(?:FATAL|CRITICAL|PANIC|ERROR|WARNING|SEVERE)\b"
    r"|Traceback \(most recent call last\)"
    r"|^\s*File \"[^\"]+\", line \d+"
    r"|\b[A-Z]\w*(?:Error|Exception|Warning):"
    r"|\b(?:panic:|fatal error:)"
    r"|(?i:\b(?:failed|failure|denied|refused|timed out|no such file|permission denied|segfault)\b)"
    r")"
)

_TEST_SUMMARY = re.compile(
    r"^(?:Ran \d+ tests? in .*|OK$|FAILED \(.*|={3,} .*={3,}$|-{3,} .*-{3,}$"
    r"|.*\b\d+ (?:passed|failed|error[s]?)\b.*)$",
    re.MULTILINE,
)

# Classification needs a stronger signal than line selection: a markdown doc that
# says "3 failed" once is not a test report. Getting this wrong is destructive —
# it shredded a 5.7 KB SKILL.md into four lines — so a test run must announce
# itself with a real summary line.
_TEST_MARKER = re.compile(
    r"^(?:Ran \d+ tests? in .*"
    r"|OK$|OK \(.*"
    r"|FAILED \(.*"
    r"|=+ \d+ (?:passed|failed|error).*"
    r"|-+ \d+ (?:passed|failed|error).*"
    r"|(?:FAIL|ERROR): \S+)",
    re.MULTILINE,
)

# A prose document (markdown, or any text built on bullets, headings, quotes and
# fences) is payload, not noise: never summarise it, whatever else it contains.
_MD_LINE = re.compile(r"^\s*(?:#{1,6} |[-*+>] |```|\| )")

_SYSTEMD_TABLE = re.compile(r"^\s*UNIT\s+LOAD\s+ACTIVE\s+SUB\s+DESCRIPTION", re.MULTILINE)

# Unit states that need no attention. "mounted" is in the list because a machine
# with a dozen filesystems would otherwise fill the whole summary with .mount
# rows and hide the one unit that failed.
_BORING_STATES = {"running", "exited", "plugged", "waiting", "mounted", "auto-restart", "active"}
_LOAD_STATES = {"loaded", "not-found", "error", "masked", "bad-setting", "not-loaded"}

# `Nov 15 11:34:18 host unit[123]: ` and `2026-11-15 11:34:18,715 LEVEL name: `
_LOG_PREFIX = re.compile(
    r"^(?:[A-Z][a-z]{2} +\d+ \d\d:\d\d:\d\d \S+ [^:\s]+(?:\[\d+\])?: "
    r"|\d{4}-\d\d-\d\d[ T]\d\d:\d\d:\d\d[.,]?\d* +(?:\w+ +)?)"
)

# Uppercase severity tokens mark a real log line; lowercase "error:" in a code
# listing does not, and neither does the word INFO inside a docstring.
_LOG_LEVEL = re.compile(
    r"\b(?:TRACE|DEBUG|INFO|NOTICE|WARN|WARNING|ERROR|CRIT|CRITICAL|FATAL|SEVERE|PANIC)\b"
)


def _log_signal(text: str) -> bool:
    """True when the text looks like a log, not like source code or a listing.

    The log compressor is the last resort and the only one that invents a shape
    out of arbitrary lines, so it needs evidence in the text. A `grep` of Python
    symbols has neither timestamps nor severity tokens; treating it as a log kept
    4 of 40 lines and threw the code away. Fail open: no signal, no shrink.
    """
    lines = [line for line in text.splitlines() if line.strip()]
    if len(lines) < 10:
        return False
    if "Traceback (most recent call last)" in text:
        return True
    stamped = sum(1 for line in lines if _LOG_PREFIX.match(line))
    leveled = sum(1 for line in lines if _LOG_LEVEL.search(line))
    return stamped / len(lines) >= 0.20 or leveled / len(lines) >= 0.20

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #


def _tokens(text: str) -> int:
    """Caveman's own estimate basis: one token per three bytes."""
    return (len(text.encode("utf-8")) + 2) // 3


def _bytes(text: str) -> int:
    return len(text.encode("utf-8"))


_SPACE_RUN = re.compile(r"\s{2,}")


def _tidy(line: str) -> str:
    """Collapse a fixed-width table's padding. Alignment is not payload."""
    return _SPACE_RUN.sub("  ", line.strip())


def _spans(indices: list[int]) -> list[tuple[int, int]]:
    """Collapse sorted line indices into contiguous runs."""
    out: list[tuple[int, int]] = []
    start = prev = None
    for index in indices:
        if start is None:
            start = prev = index
        elif index == prev + 1:
            prev = index
        else:
            out.append((start, prev))
            start = prev = index
    if start is not None:
        out.append((start, prev))
    return out


def _dedupe(lines: list[str]) -> list[str]:
    """Collapse consecutive lines that differ only in their timestamp/level."""
    out: list[str] = []
    run_key = None
    run_count = 0
    for line in lines:
        key = _LOG_PREFIX.sub("", line).strip()
        if out and key == run_key:
            run_count += 1
            continue
        if run_count:
            out[-1] = f"{out[-1].rstrip()}  (x{run_count + 1})"
        run_key = key
        run_count = 0
        out.append(line)
    if out and run_count:
        out[-1] = f"{out[-1].rstrip()}  (x{run_count + 1})"
    return out


def _spill_dir() -> Path:
    """Same directory Hermes uses for its own overflow spills."""
    root = os.environ.get("HERMES_HOME", "").strip()
    return (Path(root) if root else Path.home() / ".hermes") / "cache" / "terminal-output"


def _spill(original: str, kind: str) -> Path | None:
    """Park the untouched output on disk. Return its path, or None on failure.

    The footer is a promise: if this returns None the caller must say so instead
    of pointing at a file that does not exist. Never raises.
    """
    try:
        directory = _spill_dir()
        directory.mkdir(parents=True, exist_ok=True)
        try:
            cutoff = time.time() - SPILL_MAX_AGE_S
            for old in directory.glob("caveman-*.log"):
                if old.stat().st_mtime < cutoff:
                    old.unlink()
        except OSError:
            pass
        path = directory / f"caveman-{int(time.time())}-{os.getpid()}-{kind}.log"
        path.write_text(original, encoding="utf-8", errors="replace")
        return path
    except Exception:
        return None


def _finish(original: str, kept: str, kind: str) -> str | None:
    """Append the honest footer, or refuse the shrink when it did not pay off."""
    kept = kept.strip("\n")
    if not kept:
        return None
    if _bytes(kept) > _bytes(original) * MAX_KEEP_RATIO:
        return None
    footer = (
        f"\n\n[caveman-shrink: {kind} · {_tokens(original)} -> {_tokens(kept)} tok "
        f"({_bytes(original)} -> {_bytes(kept)} bytes)."
    )
    spill = _spill(original, kind)
    if spill:
        footer += f" Full text: {spill}"
    else:
        footer += (
            " The full text was NOT saved to disk; re-run the command with a "
            "narrower filter or redirect it to a file if this is not enough."
        )
    return kept + footer + "]"


def _budget(lines: list[str], note: str) -> list[str]:
    """Trim oldest body lines until the summary fits MAX_SUMMARY_BYTES.

    The header stays put and the note is added once at the end, so every pass
    strictly shrinks the body: the loop cannot oscillate on a list that is too
    short to divide by eight.
    """
    if not lines:
        return lines
    header, body = lines[0], lines[1:]
    dropped = 0
    while body and _bytes(header + "\n" + "\n".join(body)) > MAX_SUMMARY_BYTES:
        step = max(1, len(body) // 8)
        body = body[step:]
        dropped += step

    out = [header]
    if dropped:
        out.append(f"  [{note}: {dropped} lines]")
    out.extend(body)
    return out


# --------------------------------------------------------------------------- #
# Compressors — each returns the kept text, or None to decline
# --------------------------------------------------------------------------- #


def _shrink_log(text: str) -> str | None:
    """Keep decisive lines (severity, tracebacks, failures) plus local context."""
    lines = text.splitlines()
    wanted: list[int] = []
    for index, line in enumerate(lines):
        if _HARD.search(line):
            wanted.extend(range(max(0, index - 2), min(len(lines), index + 3)))
    if not wanted:
        return None

    kept: list[str] = []
    spans = _spans(sorted(set(wanted)))
    for start, end in spans[:60]:
        if kept:
            kept.append("  ...")
        kept.extend(_dedupe(lines[start : end + 1]))
    if len(spans) > 60:
        kept.append(f"  ... and {len(spans) - 60} more spans")

    header = (
        f"{len(lines)} log lines; {len(spans)} relevant spans found "
        f"(severity, tracebacks, failures, ±2 lines of context):"
    )
    kept = _budget([header, *kept], "older spans dropped to fit the budget")
    return "\n".join(kept)


def _shrink_table(text: str) -> str | None:
    """Systemd-style table: header, tally, and only the rows that are not boring."""
    raw_lines = text.splitlines()
    header = _tidy(raw_lines[0])

    # A real row has a unit name and a known LOAD state. The dotted suffix test
    # rejects the legend and the "0 loaded units listed." footer, which used to
    # be counted as rows and produced garbage tally keys (`units=1`).
    rows = []
    for line in raw_lines[1:]:
        parts = line.split()
        if (
            len(parts) >= 4
            and parts[1] in _LOAD_STATES
            and ("." in parts[0] or "@" in parts[0])
        ):
            rows.append((parts, line))
    if len(rows) < 20:
        return None

    interesting = [
        line
        for parts, line in rows
        if not (parts[2] == "active" and parts[3] in _BORING_STATES)
    ]
    counts: dict[str, int] = {}
    for parts, _ in rows:
        counts[parts[2]] = counts.get(parts[2], 0) + 1
    tally = ", ".join(f"{k}={v}" for k, v in sorted(counts.items(), key=lambda kv: -kv[1]))

    kept = [header, f"{len(rows)} rows ({tally}). Rows needing a look:"]
    if interesting:
        kept.extend(_tidy(line) for line in interesting[:40])
    else:
        kept.append("  (none)")
    if len(interesting) > 40:
        kept.append(f"  ... and {len(interesting) - 40} more")
    return "\n".join(kept)


def _shrink_json(text: str) -> str | None:
    """Homogeneous arrays: shape, count, and a head/tail sample."""
    data = json.loads(text)

    if isinstance(data, dict):
        keys = list(data.keys())
        if len(keys) == 1:
            return None  # a wrapper around one value: the value is the payload
        return "JSON object, %d keys: %s" % (len(keys), ", ".join(keys[:40]))

    if not isinstance(data, list) or not data:
        return None
    if not all(isinstance(item, dict) for item in data):
        return "JSON array of %d scalars, first 20: %s" % (len(data), data[:20])

    keys: list[str] = []
    for item in data:
        for key in item:
            if key not in keys:
                keys.append(key)

    sample = data[:2]
    if len(data) > 4:
        sample.append("...")
    sample.append(data[-1])
    body = json.dumps(sample, ensure_ascii=False, indent=1)
    return f"JSON array of {len(data)} objects, keys: {', '.join(keys[:30])}\nhead/tail sample:\n{body}"


def _shrink_test_output(text: str) -> str | None:
    """Test run: the summary lines and the failures, nothing else."""
    lines = text.splitlines()
    kept = [line for line in lines if _HARD.search(line) or _TEST_SUMMARY.match(line)]
    if not kept:
        return None
    kept = _dedupe(kept)
    body = [f"test output: {len(lines)} lines, decisive lines kept:"]
    body.extend(kept[:150])
    if len(kept) > 150:
        body.append(f"  ... and {len(kept) - 150} more")
    return "\n".join(body)


# --------------------------------------------------------------------------- #
# Hook
# --------------------------------------------------------------------------- #


def _looks_like_prose(text: str) -> bool:
    """True when the text is a document (markdown-shaped), not command noise."""
    lines = [line for line in text.splitlines() if line.strip()]
    if len(lines) < 20:
        return False
    marked = sum(1 for line in lines if _MD_LINE.match(line))
    return marked / len(lines) >= 0.20


def shrink(command: str = "", output: str = "", returncode=None, **kwargs) -> str | None:
    """Pick a compressor by shape. Return None to leave the output untouched."""
    try:
        if not output or _bytes(output) < MIN_BYTES:
            return None

        # A document is the payload the user asked to read. Summarising it is
        # data loss, not compression.
        if _looks_like_prose(output):
            return None

        candidates: list[tuple[str, object]] = []
        stripped = output.lstrip()
        if stripped[:1] in ("{", "["):
            candidates.append(("json", _shrink_json))
        if _SYSTEMD_TABLE.search(output):
            candidates.append(("table", _shrink_table))
        if _TEST_MARKER.search(output):
            candidates.append(("tests", _shrink_test_output))
        # Last resort, and the only compressor that invents a shape: it runs only
        # when the text carries log evidence (see _log_signal).
        if _log_signal(output):
            candidates.append(("log", _shrink_log))

        for kind, compress in candidates:
            try:
                kept = compress(output)
            except Exception:
                continue
            if kept:
                result = _finish(output, kept, kind)
                if result:
                    return result
        return None
    except Exception:
        # A compressor must never break a command's result.
        return None


def register(ctx):
    ctx.register_hook("transform_terminal_output", shrink)
