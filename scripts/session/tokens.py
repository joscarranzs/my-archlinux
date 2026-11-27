#!/usr/bin/env python3
"""Token, credit and plan-allowance readout for the desktop bar.

Prints one JSON blob on stdout. The Quickshell panel only reads it; all network
access lives here so the widget stays dumb and testable from a terminal.

Three sources, three different failure modes:

  * OpenCode Go  -- a plan allowance: three windows (rolling, weekly, monthly)
                    as consumed percent plus the reset timestamp.
  * Nous Portal  -- a prepaid dollar balance. Its OAuth access token lives about
                    an hour. This helper must never redeem the refresh token
                    itself (it rotates: a second redeemer burns the copy Hermes
                    keeps and forces a re-login), so when the token is dead it
                    asks `hermes auth refresh nous` to renew and persist it, and
                    only falls back to the last good reading marked stale when
                    that fails too.
  * Hermes state.db -- input/output/cache/reasoning tokens, offline and free.
                    This is the only per-model token source that costs nothing.
  * Hermes agent log -- the last "API call #N ... in=X" line of the open session.
                    `in` is the provider's own prompt_tokens for that request, i.e.
                    the buffer the model was carrying, which is what context
                    pressure means. No per-request figure exists in state.db
                    (`session_model_usage` aggregates per task, `messages.token_count`
                    is NULL on this runtime), so the log is the exact source and the
                    per-task average is only the fallback, marked as an estimate.

Usage:
    tokens.py            # the JSON the panel consumes
    tokens.py --pretty   # same thing, indented, for a human
"""

from __future__ import annotations

import json
import math
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import TextIO

HOME = Path.home()
HERMES_HOME = Path(os.environ.get("HERMES_HOME") or HOME / ".hermes")
AUTH_FILE = HERMES_HOME / "auth.json"
ENV_FILE = HERMES_HOME / ".env"
STATE_DB = HERMES_HOME / "state.db"
# Model id -> context window. Two producers, both written by Hermes itself:
# `context_length_cache.yaml` is what the agent's own resolver learned (keyed
# `model@base_url`), and the picker's endpoint metadata JSON. The panel needs the
# ceiling the provider actually serves, so both are read.
MODEL_METADATA_FILE = HERMES_HOME / "cache" / "endpoint_model_metadata.json"
CONTEXT_WINDOW_FILE = HERMES_HOME / "context_length_cache.yaml"
AGENT_LOG = HERMES_HOME / "logs" / "agent.log"

RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")
CACHE_FILE = RUNTIME / "quickshell-tokens.json"
LOCK_FILE = RUNTIME / "quickshell-tokens.lock"

# What was bought for the wallet. The portal reports only what is left, never the
# purchase amount, and its own counter is not trustworthy for spend -- see
# _purchased_usd(). Bump this file by hand after a top-up.
CREDITS_FILE = Path(
    os.environ.get("NOUS_CREDITS_FILE")
    or (Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local" / "state") / "nous-credits.json")
)
DEFAULT_PURCHASED_USD = 20.0

CACHE_TTL = 60          # seconds between live reads of either API
TOKEN_MARGIN = 120      # do not use an access token with less life than this
RATE_LIMIT_BACKOFF = 300
HTTP_TIMEOUT = 8
NOTICE_FILE = RUNTIME / "quickshell-tokens-notified.json"

# How much of the tail of the agent log is searched for the open session's last
# API call. The newest line wins, so a small window is enough; the rotated file
# is only read when the live one has no line for that session.
LOG_TAIL_BYTES = 1 << 20

# Sessions a machine opened, not the user: children of a delegation, headless
# runs, scheduled jobs, webhooks. Same set Hermes itself treats as machine-paced
# (agent/prompt_caching.py), and the reason "today" used to report tokens for
# sessions that never appeared in the app -- a route probe wrote 78 K of input
# into nine of these rows and the panel showed it as the user's own spend.
INTERNAL_SOURCES = frozenset({"subagent", "cron", "oneshot", "webhook", "kanban", "api", "tool", "batch"})

# A session the reaper closed without writing ended_at keeps ended_at NULL forever,
# and the panel's session block reads the newest open row -- so a dead chat would
# pin the block on forever. An open row whose last activity is older than this is
# treated as dead: the block is omitted (or falls through to a genuinely live open
# row) instead of showing numbers nobody is looking at.
STALE_SESSION_SECONDS = 6 * 3600

# "API call #7: model=m provider=p in=1234 out=56 total=1290 latency=1.2s ..."
_API_CALL_RE = re.compile(r"API call #\d+: model=\S+ provider=\S+ in=(\d+)")

NOUS_ACCOUNT_URL = "https://portal.nousresearch.com/api/oauth/account"
GO_USAGE_URL = "https://opencode.ai/zen/go/v1/usage"

# Thresholds default to the panel's own look tokens passed as --alert / --critical;
# the fallbacks only matter when the helper is run by hand.
DEFAULT_ALERT = 50.0
DEFAULT_CRITICAL = 80.0


class RateLimited(Exception):
    """The provider asked us to slow down; keep the previous reading for a while."""


def _now() -> float:
    return time.time()


def _iso(epoch: float | None) -> str | None:
    """Epoch seconds to an ISO-8601 UTC string: readable in a log and in QML."""
    if not isinstance(epoch, (int, float)):
        return None
    return datetime.fromtimestamp(epoch, tz=timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _http_json(url: str, token: str) -> dict:
    request = urllib.request.Request(
        url,
        # A User-Agent is mandatory: the OpenCode Go endpoint answers 403 to
        # urllib's default one and 200 to anything explicit (measured).
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "User-Agent": "hermes-tokens-panel/1.0",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        if exc.code == 429:
            raise RateLimited("rate limited") from exc
        raise RuntimeError(f"http {exc.code}") from exc
    except (urllib.error.URLError, TimeoutError, ValueError) as exc:
        raise RuntimeError(type(exc).__name__) from exc


def _env_key(name: str) -> str | None:
    """Read one key from Hermes' .env without loading the whole environment."""
    value = os.environ.get(name)
    if value:
        return value.strip()
    try:
        for line in ENV_FILE.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if line.startswith(f"{name}="):
                return line.split("=", 1)[1].strip().strip('"').strip("'") or None
    except OSError:
        return None
    return None


def _nous_state() -> dict:
    try:
        state = json.loads(AUTH_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    providers = state.get("providers") or {}
    entry = providers.get("nous")
    return entry if isinstance(entry, dict) else {}


def _hermes_cli() -> str | None:
    for candidate in (
        os.environ.get("HERMES_CLI"),
        str(HERMES_HOME / "hermes-agent" / ".hermes" / "bin" / "hermes"),
        str(HOME / ".local" / "bin" / "hermes"),
    ):
        if candidate and os.access(candidate, os.X_OK):
            return candidate
    return shutil.which("hermes")


def _refresh_nous_token() -> bool:
    """Ask Hermes to renew the OAuth access token.

    The helper never redeems the refresh token itself: it rotates, and a second
    redeemer invalidates the copy Hermes keeps ("refresh_token_reused"), which
    costs the user a re-login. `hermes auth refresh` is the supported path -- it
    redeems, persists the rotated token and clears the credential's cooldown --
    so the panel borrows the outcome instead of doing the exchange.
    """
    cli = _hermes_cli()
    if not cli:
        return False
    try:
        done = subprocess.run(
            [cli, "auth", "refresh", "nous"],
            capture_output=True,
            timeout=45,
            check=False,
        )
        return done.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def _nous_token(allow_refresh: bool = True) -> str | None:
    """A live access token, or None.

    An hour-old token is not a broken account: it is a pase that Hermes renews.
    The first call that finds it dead asks for a renewal and re-reads the file;
    only when that also fails does the panel fall back to the stale block.
    """
    entry = _nous_state()
    token = entry.get("access_token")
    if not token:
        if allow_refresh and _refresh_nous_token():
            return _nous_token(allow_refresh=False)
        return None
    expires_at = entry.get("expires_at")
    if isinstance(expires_at, str):
        try:
            dead = datetime.fromisoformat(expires_at.replace("Z", "+00:00")).timestamp()
        except ValueError:
            return token
        if dead - _now() < TOKEN_MARGIN:
            if allow_refresh and _refresh_nous_token():
                return _nous_token(allow_refresh=False)
            return None
    return token


def _read_credits_state() -> dict:
    try:
        data = json.loads(CREDITS_FILE.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def _write_credits_state(state: dict) -> None:
    try:
        CREDITS_FILE.parent.mkdir(parents=True, exist_ok=True)
        staging = CREDITS_FILE.with_suffix(".json.tmp")
        staging.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
        os.replace(staging, CREDITS_FILE)
    except OSError:
        pass


def _wallet_spend(balance: float, portal_spent: float) -> tuple[float, float]:
    """Return (purchased_usd, spent_usd) and keep the purchase amount up to date.

    The portal exposes only what is left (`purchased_credits_remaining`), never what was
    bought, and its `member_spend_usd` is not the wallet drawdown: on this account the two
    summed to exactly 20.0000000000 while they agreed, then the counter stopped counting
    (it sat at 0.5084044864 while the wallet had lost 0.7520973804). So the spend shown to
    the user is `purchased - remaining`.

    The purchase amount maintains itself, with no manual step:

    * First run: the remembered counter plus the balance IS the amount bought, rounded up
      to the next whole dollar (a $20 top-up reads as 19.7563 + 0.5084 -> 20).
    * Afterwards, a balance that goes UP is a top-up. Purchased grows by the increase, so
      spending does not jump and the balance never turns into a negative spend.
    * A balance that goes down is ordinary spend; nothing to adjust.

    The file is machine state, not a setting: it lives in `~/.local/state/` and is
    rewritten on every changed read.
    """
    state = _read_credits_state()
    purchased = state.get("purchased_usd")
    last = state.get("last_balance_usd")

    if not isinstance(purchased, (int, float)) or purchased <= 0:
        total = balance + max(portal_spent, 0.0)
        purchased = float(math.ceil(total)) if total > 0 else DEFAULT_PURCHASED_USD
    elif isinstance(last, (int, float)) and balance > last + 0.01:
        # The wallet grew: credits were added, they were not un-spent.
        purchased += balance - last

    purchased = round(float(purchased), 10)
    if state.get("purchased_usd") != purchased or state.get("last_balance_usd") != balance:
        _write_credits_state(
            {
                "purchased_usd": purchased,
                "last_balance_usd": balance,
                "note": "machine state: a rising balance is treated as a top-up",
            }
        )
    return purchased, round(max(purchased - balance, 0.0), 10)


def fetch_nous() -> dict:
    token = _nous_token()
    if not token:
        raise RuntimeError("no live token")
    payload = _http_json(NOUS_ACCOUNT_URL, token)
    # Identity fields (email, organisation, account ids) are deliberately dropped:
    # they ride in the same payload as the balance and must never reach a log,
    # a cache file or a panel.
    access = payload.get("paid_service_access") or {}
    # The fields the panel needs have shown up at the top level and inside
    # `paid_service_access` depending on the response generation, so each one is
    # read from both. The balance is the only field that is never optional.
    balance = payload.get("purchased_credits_remaining")
    if balance is None:
        balance = access.get("purchased_credits_remaining")
    usable = payload.get("total_usable_credits")
    if usable is None:
        usable = access.get("total_usable_credits")
    spent = payload.get("member_spend_usd")
    if spent is None:
        spent = access.get("member_spend_usd")
    purchased, spent_usd = _wallet_spend(float(balance or 0), float(spent or 0))
    return {
        "balance_usd": float(balance or 0),
        "total_usable_usd": float(usable or balance or 0),
        # The wallet drawdown, which is what "spent" means to a pay-as-you-go account.
        # `member_spend_usd` is reported apart because it under-counts; see _wallet_spend.
        "spent_usd": spent_usd,
        "purchased_usd": purchased,
        "portal_spent_usd": float(spent or 0),
        "has_subscription": bool(payload.get("subscription")) or bool(access.get("has_active_subscription")),
    }


def _route(provider: str | None, base_url: str | None) -> str | None:
    """What pays for a session: a plan or the prepaid wallet.

    state.db records the route per session (`billing_provider`), never the pricing
    model, so the split is read from who served the request: OpenCode Go is a plan
    allowance, Nous Portal draws on prepaid credits. An unrecognised route returns
    None -- the panel then shows no chip rather than a guess.
    """
    haystack = f"{provider or ''} {base_url or ''}".lower()
    if "opencode" in haystack:
        return "plan"
    if "nous" in haystack:
        return "credit"
    return None


def fetch_go() -> dict:
    key = _env_key("OPENCODE_GO_API_KEY")
    if not key:
        raise RuntimeError("no api key")
    payload = _http_json(GO_USAGE_URL, key)
    usage = payload.get("usage") or {}
    windows = []
    for name in ("rolling", "weekly", "monthly"):
        window = usage.get(name)
        if not isinstance(window, dict):
            continue
        windows.append(
            {
                "key": name,
                "percent": float(window.get("percent") or 0),
                "resets_at": window.get("resetsAt"),
            }
        )
    if not windows:
        raise RuntimeError("no windows in response")
    # The plan's renewal is its longest cycle: the endpoint reports no billing
    # date, and the monthly reset is the only timestamp that is the subscription's
    # own (rolling restarts in hours, weekly inside the same month).
    renews = None
    for window in windows:
        if window["key"] == "monthly" and window["resets_at"]:
            renews = window["resets_at"]
    return {"windows": windows, "renews_at": renews}


# --- local token accounting -------------------------------------------------


def _today_start() -> float:
    """Midnight in the session's own timezone, as epoch seconds."""
    local = datetime.now().astimezone()
    return local.replace(hour=0, minute=0, second=0, microsecond=0).timestamp()


def _token_columns() -> str:
    return (
        "coalesce(sum(input_tokens),0) as input, "
        "coalesce(sum(output_tokens),0) as output, "
        "coalesce(sum(cache_read_tokens),0) as cache_read, "
        "coalesce(sum(cache_write_tokens),0) as cache_write, "
        "coalesce(sum(reasoning_tokens),0) as reasoning, "
        "coalesce(sum(api_call_count),0) as calls, "
        "count(*) as sessions"
    )


# --- context pressure -------------------------------------------------------


def _read_flat_int_map(path: Path, section: str) -> dict[str, int]:
    """`section:` -> {key: int} out of a flat YAML document, stdlib only.

    The file is Hermes' own `context_length_cache.yaml`: one section whose values
    are plain integers. No YAML parser is installed for the interpreter the panel
    uses, and none is needed for a shape this narrow -- anything unreadable is
    skipped, and an unreadable file yields {}, which reads as "window unknown"
    instead of a wrong ceiling. Keys carry a colon of their own
    (`model:free@https://host/v1`), so the value is split off at the last colon,
    and a value wrapped onto the next line is picked up from there.
    """
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return {}
    values: dict[str, int] = {}
    inside = False
    pending: str | None = None
    for raw in lines:
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if not raw[0].isspace():
            inside = raw.strip() == f"{section}:"
            pending = None
            continue
        if not inside:
            continue
        body = raw.strip()
        if pending is not None and body.lstrip("-").isdigit():
            values[pending] = int(body)
            pending = None
            continue
        key, separator, value = body.rpartition(":")
        if not separator:
            pending = None
            continue
        key = key.strip()
        if not value.strip():
            pending = key          # the number is on the next line
            continue
        try:
            values[key] = int(value.strip())
        except ValueError:
            pending = None
    return values


def _window_from_cache(model: str, base_url: str) -> int | None:
    """The window Hermes' own resolver learned for this model.

    Keys are `model@base_url` because the same model carries a different ceiling
    per endpoint, so an exact `model@base_url` wins. The serving endpoint is not
    always the one the ceiling was probed on (`opencode-go` serving a model whose
    window was learned through the Nous endpoint), so a second pass matches the
    model id alone; when those entries disagree the largest wins, since a ceiling
    that is too small invents alarm for a percentage that is not real.
    """
    cache = _read_flat_int_map(CONTEXT_WINDOW_FILE, "context_lengths")
    if not cache:
        return None
    wanted = {model, model.split("/")[-1]}
    served = (base_url or "").rstrip("/")
    by_model: dict[str, int] = {}
    for key, length in cache.items():
        name, _, endpoint = key.lstrip("~").rpartition("@")
        if name not in wanted and name.split("/")[-1] not in wanted:
            continue
        if length <= 0:
            continue
        if served and endpoint.rstrip("/") == served:
            return int(length)
        slot = name if name in wanted else name.split("/")[-1]
        by_model[slot] = max(by_model.get(slot, 0), int(length))
    if not by_model:
        return None
    return max(by_model.values())


def _context_window(model: str | None, base_url: str | None = None) -> int | None:
    """The model's context window, or None.

    The picker's metadata is `{base_url: {models: {model_id: {context_length}}}}`
    and the id in state.db is not always the id in that file, so an exact match is
    tried first and the bare name after the last `/` second. The agent's own
    persistent cache answers when the picker has nothing. No entry from either
    source returns None: the panel then paints no percent instead of inventing a
    ceiling, which is the one number the user cannot verify.
    """
    if not model:
        return None
    try:
        payload = json.loads(MODEL_METADATA_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        payload = None
    if isinstance(payload, dict):
        for entry in payload.values():
            models = entry.get("models") if isinstance(entry, dict) else None
            if not isinstance(models, dict):
                continue
            for key in (model, model.split("/")[-1]):
                meta = models.get(key)
                if isinstance(meta, dict):
                    length = meta.get("context_length")
                    if isinstance(length, (int, float)) and length > 0:
                        return int(length)
    return _window_from_cache(model, base_url or "")


def _tail_lines(path: Path) -> list[str]:
    """The last LOG_TAIL_BYTES of a log, as lines. A missing file gives no lines."""
    try:
        with path.open("rb") as handle:
            handle.seek(0, os.SEEK_END)
            handle.seek(max(0, handle.tell() - LOG_TAIL_BYTES))
            data = handle.read()
    except OSError:
        return []
    return data.decode("utf-8", errors="replace").splitlines()


def _context_used_from_log(session_id: str) -> int | None:
    """Provider-exact prompt tokens of the open session's last API call.

    `in=` is the provider's `prompt_tokens` for that request: the whole buffer it
    had to read, which is what "context occupied" means. The log rotates, so the
    previous file is the fallback, and a session whose calls predate both returns
    None so the caller can fall back to the estimate.
    """
    marker = f"[{session_id}]"
    for path in (AGENT_LOG, AGENT_LOG.with_suffix(".log.1")):
        for line in reversed(_tail_lines(path)):
            if marker in line and "API call #" in line:
                match = _API_CALL_RE.search(line)
                if match:
                    return int(match.group(1))
    return None


def _context_used_estimate(session_id: str, connection: sqlite3.Connection) -> int | None:
    """Average cache traffic per request, for a session the log cannot answer for.

    The main thread re-reads roughly its whole buffer on every request, so
    `(cache_read + cache_write) / api_call_count` of the session's main task row
    lands in the right order of magnitude. It averages the whole session instead
    of reading it live, so the caller reports it as an estimate.
    """
    try:
        row = connection.execute(
            "select cache_read_tokens + cache_write_tokens as read_tokens, api_call_count as calls "
            "from session_model_usage where session_id = ? and coalesce(task, '') = '' "
            "order by last_seen desc limit 1",
            (session_id,),
        ).fetchone()
    except sqlite3.Error:
        return None
    if row is None:
        return None
    calls = int(row["calls"] or 0)
    if calls <= 0:
        return None
    average = int(row["read_tokens"] or 0) / calls
    return int(average) if average >= 1 else None


def read_tokens() -> dict:
    """Token totals from state.db: today and the newest still-open session.

    Read-only. "Today" means sessions with activity since local midnight, not
    sessions that *started* today: a chat that began at 23:40 and is still going
    has to appear here, or the panel reads zero while it is burning tokens. The
    trade-off is that such a session contributes its whole history, which is the
    number the user is already looking at in the session block below.

    An open row is only the session block while its activity is recent
    (STALE_SESSION_SECONDS): the reaper leaves ended_at NULL on sessions it kills,
    so "newest open row" alone would pin the block on a chat that no longer exists.

    Machine-paced sessions are excluded (see INTERNAL_SOURCES): a headless probe
    or a delegation child loads a full system prompt of its own, so nine rows
    nobody opened once showed up as 78 K of "today's" input and the user read it
    as his own spend.

    The session block also carries context pressure: the model's window from the
    picker's metadata cache and the buffer of its last request, provider-exact
    when the agent log answers for the session and an average when it does not.
    """
    if not STATE_DB.exists():
        return {"today": None, "session": None, "error": "no state.db"}
    uri = f"file:{STATE_DB}?mode=ro"
    try:
        connection = sqlite3.connect(uri, uri=True, timeout=3)
    except sqlite3.Error as exc:
        return {"today": None, "session": None, "error": type(exc).__name__}
    try:
        connection.row_factory = sqlite3.Row
        # The machine-paced filter is skipped when the column is absent: an older
        # or newer schema must still give the panel its numbers, and losing the
        # whole "today" block over one missing column is the worse failure.
        columns = {str(row[1]) for row in connection.execute("pragma table_info(sessions)")}
        internal = sorted(INTERNAL_SOURCES) if "source" in columns else []
        where = "coalesce(last_activity_at, started_at) >= ?"
        params: list = [_today_start()]
        if internal:
            where += f" and coalesce(source, '') not in ({', '.join('?' for _ in internal)})"
            params.extend(internal)
        today = connection.execute(
            f"select {_token_columns()}, "
            "coalesce(sum(estimated_cost_usd),0) as cost_usd, "
            "coalesce(sum(actual_cost_usd),0) as actual_cost_usd, "
            "sum(case when cost_status = 'unknown' then 1 else 0 end) as cost_unknown "
            f"from sessions where {where}",
            tuple(params),
        ).fetchone()
        open_where = "ended_at is null and coalesce(last_activity_at, started_at) >= ?"
        open_params: list = [_now() - STALE_SESSION_SECONDS]
        if internal:
            open_where += f" and coalesce(source, '') not in ({', '.join('?' for _ in internal)})"
            open_params.extend(internal)
        # The session block is the user's own chat. A delegation child or a cron
        # job is an open row too, and a newer one every time one runs, so without
        # the same filter the "today" totals use, a subagent would become "the
        # session" the card describes -- and its model, probed through a cheaper
        # route, is often not in the window cache, so the context row vanished
        # while the user's own chat was still running.
        open_session = connection.execute(
            "select id, model, message_count, api_call_count, "
            "input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, "
            "reasoning_tokens, estimated_cost_usd, cost_status, "
            "billing_provider, billing_base_url "
            f"from sessions where {open_where} "
            "order by coalesce(last_activity_at, started_at) desc limit 1",
            tuple(open_params),
        ).fetchone()
        context: dict = {}
        if open_session is not None:
            window = _context_window(open_session["model"], open_session["billing_base_url"])
            used = _context_used_from_log(open_session["id"])
            source = "provider_usage" if used else None
            if used is None:
                used = _context_used_estimate(open_session["id"], connection)
                source = "estimate" if used else None
            if used and window:
                # A single prompt cannot exceed the window; an estimate can.
                used = min(used, window)
            # Both numbers are facts, and each can be missing on its own. The
            # ceiling comes from the model, the buffer from the log. Reporting
            # what is known keeps the row on screen -- an empty bar beside
            # "95K / —" says "this session's ceiling is not cached yet", which is
            # true, instead of deleting the row and looking like a regression.
            context = {
                "context_max": int(window) if window else None,
                "context_used": int(used) if used else None,
                "context_pct": int(round(used / window * 100)) if (used and window) else None,
                "context_source": source if window else None,
                "context_estimated": bool(window) and source not in (None, "provider_usage"),
                "context_window_known": bool(window),
            }
    except sqlite3.Error as exc:
        return {"today": None, "session": None, "error": type(exc).__name__}
    finally:
        connection.close()

    def tokens_from(row) -> dict:
        if row is None:
            return None
        return {
            key: int(row[key] or 0)
            for key in ("input", "output", "cache_read", "cache_write", "reasoning", "calls", "sessions")
            if key in row.keys()
        }

    today_block = tokens_from(today) or {}
    if today is not None:
        today_block.update(
            {
                "cost_usd": float(today["cost_usd"] or 0),
                "actual_cost_usd": float(today["actual_cost_usd"] or 0),
                "cost_unknown_sessions": int(today["cost_unknown"] or 0),
            }
        )

    session_block = None
    if open_session is not None:
        session_block = {
            "id": open_session["id"],
            "model": open_session["model"],
            # Who served it and what pays for it: the panel names both, because
            # "which account is this session spending" is the question a plan and
            # a prepaid wallet side by side make unavoidable.
            "provider": open_session["billing_provider"],
            "route": _route(open_session["billing_provider"], open_session["billing_base_url"]),
            "input": int(open_session["input_tokens"] or 0),
            "output": int(open_session["output_tokens"] or 0),
            "cache_read": int(open_session["cache_read_tokens"] or 0),
            "cache_write": int(open_session["cache_write_tokens"] or 0),
            "reasoning": int(open_session["reasoning_tokens"] or 0),
            "calls": int(open_session["api_call_count"] or 0),
            "messages": int(open_session["message_count"] or 0),
            "cost_usd": float(open_session["estimated_cost_usd"] or 0),
            "cost_status": open_session["cost_status"],
        }
        session_block.update(context)
    return {"today": today_block or None, "session": session_block, "error": None}


# --- cache ------------------------------------------------------------------


def _read_cache() -> dict:
    try:
        return json.loads(CACHE_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def _write_cache(payload: dict) -> None:
    try:
        CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
        staging = CACHE_FILE.with_suffix(".json.tmp")
        staging.write_text(json.dumps(payload), encoding="utf-8")
        os.replace(staging, CACHE_FILE)
    except OSError:
        pass


def _refresh(name: str, fetch, cached: dict) -> dict:
    """Live read, falling back to the last good block marked stale."""
    previous = cached.get(name) or {}
    fetched_epoch = previous.get("fetched_epoch")
    # Freshness is the timestamp alone, not `ok`: a 429 parks that timestamp in
    # the future on purpose, and requiring a healthy previous block here would
    # retry through the whole backoff window.
    if isinstance(fetched_epoch, (int, float)) and _now() - fetched_epoch < CACHE_TTL:
        return previous
    try:
        block = fetch()
        block.update({"ok": True, "stale": False, "fetched_epoch": _now(), "error": None})
        return block
    except RateLimited:
        if previous.get("fetched_epoch"):
            previous = dict(previous)
            # Park the timestamp so the cache stays authoritative for the backoff.
            previous.update(
                {
                    "ok": False,
                    "stale": True,
                    "error": "rate limited",
                    "fetched_epoch": _now() - CACHE_TTL + RATE_LIMIT_BACKOFF,
                }
            )
            return previous
        return {"ok": False, "stale": False, "fetched_epoch": None, "error": "rate limited"}
    except Exception as exc:  # noqa: BLE001 - every failure becomes a visible field
        if previous.get("fetched_epoch"):
            previous = dict(previous)
            previous.update({"ok": False, "stale": True, "error": str(exc)[:80]})
            return previous
        return {"ok": False, "stale": False, "fetched_epoch": None, "error": str(exc)[:80]}


def _lock() -> TextIO | None:
    import fcntl

    try:
        handle: TextIO = open(LOCK_FILE, "w")
    except OSError:
        # No writable runtime dir: skip the cache and the coordination instead of
        # dying. A panel with no lock is worse than a panel with no data.
        return None
    try:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return handle
    except OSError:
        handle.close()
        return None


def _arg_value(flag: str, default: float) -> float:
    """Read `--flag N` from argv. Tiny on purpose: no argparse for two numbers."""
    if flag in sys.argv:
        index = sys.argv.index(flag) + 1
        if index < len(sys.argv):
            try:
                return float(sys.argv[index])
            except ValueError:
                pass
    return default


def _load_notices() -> dict:
    try:
        return json.loads(NOTICE_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def _save_notices(state: dict) -> None:
    try:
        staging = NOTICE_FILE.with_suffix(".json.tmp")
        staging.write_text(json.dumps(state), encoding="utf-8")
        os.replace(staging, NOTICE_FILE)
    except OSError:
        pass


def notify_allowance(go: dict) -> None:
    """One desktop alert per threshold crossing, per allowance window.

    Nothing pushes a plan limit, so the only chance to warn before a hard stop is
    a process that is already reading the numbers. The armed state lives in
    XDG_RUNTIME_DIR, so it dies with the session, and a window that falls back
    under the floor (it reset) re-arms itself for the next climb.
    """
    if not go.get("ok") or go.get("stale"):
        return
    if shutil.which("notify-send") is None:
        return
    alert = _arg_value("--alert", DEFAULT_ALERT)
    critical = _arg_value("--critical", DEFAULT_CRITICAL)
    armed = _load_notices()
    before = json.dumps(armed, sort_keys=True)
    for window in go.get("windows") or []:
        key = str(window.get("key"))
        percent = float(window.get("percent") or 0)
        if percent >= critical:
            level = "critical"
        elif percent >= alert:
            level = "alert"
        else:
            level = None
        if level is None:
            for name in (f"{key}:alert", f"{key}:critical"):
                armed.pop(name, None)
            continue
        token = f"{key}:{level}"
        if armed.get(token):
            continue
        armed[token] = True
        subprocess.run(
            [
                "notify-send",
                "-a", "Hermes tokens",
                "-u", "critical" if level == "critical" else "normal",
                f"OpenCode Go {key} at {percent:.0f}%",
                f"Resets {window.get('resets_at') or 'unknown'}",
            ],
            check=False,
            timeout=5,
        )
    if json.dumps(armed, sort_keys=True) != before:
        _save_notices(armed)


def main() -> int:
    pretty = "--pretty" in sys.argv[1:]
    lock = _lock()
    cached = _read_cache()
    payload = {
        "generated_epoch": _now(),
        "generated_at": None,
        "ttl_seconds": CACHE_TTL,
        "nous": _refresh("nous", fetch_nous, cached),
        "go": _refresh("go", fetch_go, cached),
    }
    payload["generated_at"] = _iso(payload["generated_epoch"])
    for block in ("nous", "go"):
        payload[block]["fetched_at"] = _iso(payload[block].get("fetched_epoch"))
    if lock is not None:
        _write_cache({"nous": payload["nous"], "go": payload["go"]})
        lock.close()
    payload["tokens"] = read_tokens()
    notify_allowance(payload["go"])

    # Identity-free by construction: only balances, percents and counters leave this process.
    text = json.dumps(payload, indent=2 if pretty else None, sort_keys=False)
    sys.stdout.write(text + "\n")
    # Always 0: the JSON is the contract, and a stale block is a field the caller
    # reads, not a failure it has to special-case.
    return 0


if __name__ == "__main__":
    sys.exit(main())
