#!/usr/bin/env python3
"""Tests for the pure logic in tokens.py.

The helper reads three sources -- two HTTP endpoints and the local state.db -- so
every test patches `_http_json`, `subprocess.run` or the module's paths instead of
standing up a fake server. The contract under test is the JSON the helper prints,
which is what the panel consumes.

Cache, notice, env and database paths are redirected into a temporary directory,
so a run never reads the live desktop files.

    python3 -m unittest discover -s scripts/session/tests
"""

import importlib.util
import io
import json
import sqlite3
import tempfile
import unittest
from contextlib import redirect_stdout
from datetime import datetime
from pathlib import Path
from unittest import mock

TOKENS = Path(__file__).resolve().parents[1] / "tokens.py"
SPEC = importlib.util.spec_from_file_location("tokens", TOKENS)
assert SPEC is not None and SPEC.loader is not None
tokens = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(tokens)


class TempPathsCase(unittest.TestCase):
    """Redirects every file the helper touches into a throwaway directory."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.dir = Path(temporary.name)
        for name, value in (
            ("CACHE_FILE", self.dir / "cache.json"),
            ("LOCK_FILE", self.dir / "cache.lock"),
            ("NOTICE_FILE", self.dir / "notices.json"),
            ("STATE_DB", self.dir / "state.db"),
            ("ENV_FILE", self.dir / ".env"),
            ("CREDITS_FILE", self.dir / "credits.json"),
            ("MODEL_METADATA_FILE", self.dir / "endpoint_model_metadata.json"),
            ("CONTEXT_WINDOW_FILE", self.dir / "context_length_cache.yaml"),
            ("AGENT_LOG", self.dir / "agent.log"),
        ):
            patcher = mock.patch.object(tokens, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)


class IsoTest(unittest.TestCase):
    def test_rejects_anything_that_is_not_a_number(self):
        self.assertIsNone(tokens._iso(None))
        self.assertIsNone(tokens._iso("1794604035"))

    def test_epoch_zero_is_the_utc_epoch(self):
        self.assertEqual(tokens._iso(0), "1970-01-01T00:00:00Z")

    def test_drops_microseconds_so_qml_can_parse_it(self):
        self.assertEqual(tokens._iso(1794604035.987654), "2026-11-13T21:07:15Z")

    def test_round_trips_through_fromisoformat(self):
        stamp = 1794604035
        parsed = datetime.fromisoformat(tokens._iso(stamp).replace("Z", "+00:00"))
        self.assertEqual(parsed.timestamp(), stamp)


class TodayStartTest(unittest.TestCase):
    def test_is_local_midnight(self):
        local = datetime.fromtimestamp(tokens._today_start()).astimezone()
        self.assertEqual((local.hour, local.minute, local.second, local.microsecond), (0, 0, 0, 0))

    def test_never_lies_in_the_future(self):
        self.assertLessEqual(tokens._today_start(), datetime.now().astimezone().timestamp())

    def test_is_less_than_a_day_old(self):
        self.assertLess(datetime.now().astimezone().timestamp() - tokens._today_start(), 86400)


class RefreshTest(TempPathsCase):
    def test_fresh_cache_is_reused_without_a_request(self):
        cached = {"go": {"ok": True, "stale": False, "fetched_epoch": tokens._now(), "windows": [1]}}
        fetch = mock.Mock(side_effect=AssertionError("must not hit the network"))
        self.assertEqual(tokens._refresh("go", fetch, cached), cached["go"])
        fetch.assert_not_called()

    def test_expired_cache_is_refetched_and_cleared(self):
        cached = {"go": {"ok": True, "stale": True, "fetched_epoch": tokens._now() - 3600, "error": "boom"}}
        block = tokens._refresh("go", lambda: {"windows": [{"percent": 5}]}, cached)
        self.assertTrue(block["ok"])
        self.assertFalse(block["stale"])
        self.assertIsNone(block["error"])
        self.assertEqual(block["windows"], [{"percent": 5}])

    def test_a_stale_block_with_an_old_timestamp_is_refetched(self):
        cached = {"go": {"ok": False, "stale": True, "fetched_epoch": tokens._now() - 600, "error": "http 500"}}
        block = tokens._refresh("go", lambda: {"windows": []}, cached)
        self.assertTrue(block["ok"])
        self.assertFalse(block["stale"])

    def test_rate_limit_marks_the_last_reading_stale(self):
        cached = {"go": {"ok": True, "stale": False, "fetched_epoch": tokens._now() - 600, "windows": [{"percent": 40}]}}

        def limited():
            raise tokens.RateLimited("429")

        block = tokens._refresh("go", limited, cached)
        self.assertFalse(block["ok"])
        self.assertTrue(block["stale"])
        self.assertEqual(block["error"], "rate limited")
        self.assertEqual(block["windows"], [{"percent": 40}])

    def test_rate_limit_backs_off_instead_of_retrying(self):
        cached = {"go": {"ok": True, "stale": False, "fetched_epoch": tokens._now() - 600, "windows": []}}

        def limited():
            raise tokens.RateLimited("429")

        block = tokens._refresh("go", limited, cached)
        again = mock.Mock(side_effect=AssertionError("must stay in backoff"))
        tokens._refresh("go", again, {"go": block})
        again.assert_not_called()

    def test_rate_limit_without_a_previous_reading_reports_and_keeps_no_timestamp(self):
        block = tokens._refresh("nous", mock.Mock(side_effect=tokens.RateLimited("429")), {})
        self.assertFalse(block["stale"])
        self.assertIsNone(block["fetched_epoch"])
        self.assertEqual(block["error"], "rate limited")

    def test_a_failure_keeps_the_last_numbers(self):
        cached = {"nous": {"ok": True, "stale": False, "fetched_epoch": tokens._now() - 600, "balance_usd": 19.49}}

        def boom():
            raise RuntimeError("http 401")

        block = tokens._refresh("nous", boom, cached)
        self.assertFalse(block["ok"])
        self.assertTrue(block["stale"])
        self.assertEqual(block["balance_usd"], 19.49)
        self.assertEqual(block["error"], "http 401")

    def test_a_failure_without_a_previous_reading_invents_nothing(self):
        block = tokens._refresh("nous", mock.Mock(side_effect=RuntimeError("http 500")), {})
        self.assertFalse(block["ok"])
        self.assertFalse(block["stale"])
        self.assertIsNone(block["fetched_epoch"])
        self.assertNotIn("balance_usd", block)

    def test_the_error_text_is_capped(self):
        block = tokens._refresh("go", mock.Mock(side_effect=RuntimeError("x" * 500)), {})
        self.assertEqual(len(block["error"]), 80)


class EnvKeyTest(TempPathsCase):
    def test_reads_the_environment_first(self):
        with mock.patch.dict("os.environ", {"OPENCODE_GO_API_KEY": "from-env"}, clear=False):
            tokens.ENV_FILE.write_text("OPENCODE_GO_API_KEY=from-file\n")
            self.assertEqual(tokens._env_key("OPENCODE_GO_API_KEY"), "from-env")

    def test_falls_back_to_the_hermes_env_file(self):
        with mock.patch.dict("os.environ", {}, clear=True):
            tokens.ENV_FILE.write_text("# comment\nOPENCODE_GO_API_KEY=from-file\n")
            self.assertEqual(tokens._env_key("OPENCODE_GO_API_KEY"), "from-file")

    def test_strips_surrounding_quotes(self):
        with mock.patch.dict("os.environ", {}, clear=True):
            tokens.ENV_FILE.write_text('OPENCODE_GO_API_KEY="quoted"\n')
            self.assertEqual(tokens._env_key("OPENCODE_GO_API_KEY"), "quoted")

    def test_returns_none_when_the_key_is_absent_or_empty(self):
        with mock.patch.dict("os.environ", {}, clear=True):
            tokens.ENV_FILE.write_text("OPENCODE_GO_API_KEY=\n")
            self.assertIsNone(tokens._env_key("OPENCODE_GO_API_KEY"))
            self.assertIsNone(tokens._env_key("MISSING"))
            tokens.ENV_FILE.unlink()

    def test_returns_none_when_the_file_cannot_be_read(self):
        with mock.patch.dict("os.environ", {}, clear=True):
            self.assertIsNone(tokens._env_key("OPENCODE_GO_API_KEY"))


class FetchNousTest(TempPathsCase):
    PAYLOAD = {
        "email": "someone@example.com",
        "organization": {"id": "org_123", "name": "Personal"},
        "subscription": None,
        "purchased_credits_remaining": 19.4932893436,
        "member_spend_usd": "0.5067106564",
        "total_usable_credits": 19.4932893436,
        "paid_service_access": {"allowed": True, "reason": "usable_credits"},
    }

    def test_drops_every_identity_field(self):
        with mock.patch.object(tokens, "_nous_token", return_value="t"), mock.patch.object(
            tokens, "_http_json", return_value=dict(self.PAYLOAD)
        ):
            block = tokens.fetch_nous()
        self.assertEqual(
            set(block),
            {"balance_usd", "total_usable_usd", "spent_usd", "purchased_usd",
             "portal_spent_usd", "has_subscription"},
        )
        self.assertNotIn("example.com", json.dumps(block))

    def test_reads_the_balance_spend_and_subscription(self):
        with mock.patch.object(tokens, "_nous_token", return_value="t"), mock.patch.object(
            tokens, "_http_json", return_value=dict(self.PAYLOAD)
        ):
            block = tokens.fetch_nous()
        self.assertAlmostEqual(block["balance_usd"], 19.4932893436)
        self.assertAlmostEqual(block["spent_usd"], 0.5067106564)
        self.assertFalse(block["has_subscription"])

    def test_spend_is_the_wallet_drawdown_not_the_portal_counter(self):
        # The real numbers that made the panel report "spent $0.51" on a $20 top-up while
        # the wallet had already lost $0.75: the portal's member counter under-counts.
        payload = dict(self.PAYLOAD)
        payload["purchased_credits_remaining"] = 19.2479026196
        payload["total_usable_credits"] = 19.2479026196
        payload["member_spend_usd"] = "0.5084044864"
        with mock.patch.object(tokens, "_nous_token", return_value="t"), mock.patch.object(
            tokens, "_http_json", return_value=payload
        ):
            block = tokens.fetch_nous()
        self.assertAlmostEqual(block["spent_usd"], 0.7520973804)
        self.assertAlmostEqual(block["portal_spent_usd"], 0.5084044864)
        self.assertAlmostEqual(block["spent_usd"] + block["balance_usd"], 20.0)

    def test_reads_the_purchased_amount_from_its_own_file(self):
        tokens.CREDITS_FILE.write_text('{"purchased_usd": 100}', encoding="utf-8")
        payload = dict(self.PAYLOAD)
        payload["purchased_credits_remaining"] = 4.5
        with mock.patch.object(tokens, "_nous_token", return_value="t"), mock.patch.object(
            tokens, "_http_json", return_value=payload
        ):
            block = tokens.fetch_nous()
        self.assertAlmostEqual(block["purchased_usd"], 100.0)
        self.assertAlmostEqual(block["spent_usd"], 95.5)

    def test_a_top_up_raises_the_purchase_and_keeps_the_spend(self):
        # The user's example: $19.25 left, a $10 top-up lands, balance becomes $29.25.
        # Spend must stay at $0.75 and the purchase must become $30 -- detected from the
        # balance going up, with nothing to edit by hand.
        tokens.CREDITS_FILE.write_text(
            json.dumps({"purchased_usd": 20.0, "last_balance_usd": 19.2479026196}),
            encoding="utf-8",
        )
        payload = dict(self.PAYLOAD)
        payload["purchased_credits_remaining"] = 29.2479026196
        payload["total_usable_credits"] = 29.2479026196
        with mock.patch.object(tokens, "_nous_token", return_value="t"), mock.patch.object(
            tokens, "_http_json", return_value=payload
        ):
            block = tokens.fetch_nous()
        self.assertAlmostEqual(block["purchased_usd"], 30.0)
        self.assertAlmostEqual(block["spent_usd"], 0.7520973804)
        self.assertAlmostEqual(block["balance_usd"], 29.2479026196)

    def test_ordinary_spending_does_not_touch_the_purchase(self):
        tokens.CREDITS_FILE.write_text(
            json.dumps({"purchased_usd": 20.0, "last_balance_usd": 19.5}),
            encoding="utf-8",
        )
        payload = dict(self.PAYLOAD)
        payload["purchased_credits_remaining"] = 19.25
        payload["total_usable_credits"] = 19.25
        with mock.patch.object(tokens, "_nous_token", return_value="t"), mock.patch.object(
            tokens, "_http_json", return_value=payload
        ):
            block = tokens.fetch_nous()
        self.assertAlmostEqual(block["purchased_usd"], 20.0)
        self.assertAlmostEqual(block["spent_usd"], 0.75)

    def test_a_fresh_account_seeds_the_purchase_from_the_remembered_counter(self):
        # No state yet: balance + the portal's counter, rounded up to a whole dollar, is
        # the best estimate of what was bought -- 19.7563 -> 20.
        payload = dict(self.PAYLOAD)
        payload["purchased_credits_remaining"] = 19.2479026196
        payload["total_usable_credits"] = 19.2479026196
        payload["member_spend_usd"] = "0.5084044864"
        with mock.patch.object(tokens, "_nous_token", return_value="t"), mock.patch.object(
            tokens, "_http_json", return_value=payload
        ):
            block = tokens.fetch_nous()
        self.assertAlmostEqual(block["purchased_usd"], 20.0)
        self.assertAlmostEqual(block["spent_usd"], 0.7520973804)
        state = json.loads(tokens.CREDITS_FILE.read_text(encoding="utf-8"))
        self.assertAlmostEqual(state["purchased_usd"], 20.0)
        self.assertAlmostEqual(state["last_balance_usd"], 19.2479026196)

    def test_falls_back_to_the_nested_access_block(self):
        payload = {
            "paid_service_access": {
                "purchased_credits_remaining": 4.5,
                "total_usable_credits": 4.5,
                "member_spend_usd": 1.5,
                "has_active_subscription": True,
            }
        }
        with mock.patch.object(tokens, "_nous_token", return_value="t"), mock.patch.object(
            tokens, "_http_json", return_value=payload
        ):
            block = tokens.fetch_nous()
        self.assertAlmostEqual(block["balance_usd"], 4.5)
        self.assertTrue(block["has_subscription"])

    def test_refuses_to_request_without_a_live_token(self):
        with mock.patch.object(tokens, "_nous_token", return_value=None), mock.patch.object(
            tokens, "_http_json"
        ) as http:
            with self.assertRaises(RuntimeError):
                tokens.fetch_nous()
        http.assert_not_called()


class FetchGoTest(TempPathsCase):
    PAYLOAD = {
        "usage": {
            "rolling": {"percent": 0, "resetsAt": "2026-11-14T01:09:21Z"},
            "weekly": {"percent": 38, "resetsAt": "2026-11-16T00:00:00Z"},
            "monthly": {"percent": 69, "resetsAt": "2026-11-29T18:13:02Z"},
        }
    }

    def test_keeps_the_three_windows_in_a_fixed_order(self):
        with mock.patch.object(tokens, "_env_key", return_value="key"), mock.patch.object(
            tokens, "_http_json", return_value=dict(self.PAYLOAD)
        ):
            block = tokens.fetch_go()
        self.assertEqual([w["key"] for w in block["windows"]], ["rolling", "weekly", "monthly"])
        self.assertEqual([w["percent"] for w in block["windows"]], [0.0, 38.0, 69.0])
        self.assertEqual(block["windows"][2]["resets_at"], "2026-11-29T18:13:02Z")

    def test_skips_a_window_the_response_does_not_describe(self):
        payload = {"usage": {"weekly": {"percent": 12, "resetsAt": None}, "monthly": "junk"}}
        with mock.patch.object(tokens, "_env_key", return_value="key"), mock.patch.object(
            tokens, "_http_json", return_value=payload
        ):
            block = tokens.fetch_go()
        self.assertEqual([w["key"] for w in block["windows"]], ["weekly"])

    def test_the_plan_renews_with_its_monthly_window(self):
        with mock.patch.object(tokens, "_env_key", return_value="key"), mock.patch.object(
            tokens, "_http_json", return_value=dict(self.PAYLOAD)
        ):
            block = tokens.fetch_go()
        self.assertEqual(block["renews_at"], "2026-11-29T18:13:02Z")

    def test_a_response_without_a_monthly_window_has_no_renewal(self):
        """No month, no billing cycle: an empty field, never the weekly date."""
        payload = {"usage": {"rolling": {"percent": 1, "resetsAt": "2026-11-14T01:09:21Z"}}}
        with mock.patch.object(tokens, "_env_key", return_value="key"), mock.patch.object(
            tokens, "_http_json", return_value=payload
        ):
            block = tokens.fetch_go()
        self.assertIsNone(block["renews_at"])

    def test_a_response_without_windows_is_an_error(self):
        with mock.patch.object(tokens, "_env_key", return_value="key"), mock.patch.object(
            tokens, "_http_json", return_value={"usage": {}}
        ):
            with self.assertRaises(RuntimeError):
                tokens.fetch_go()

    def test_a_missing_api_key_is_an_error(self):
        with mock.patch.object(tokens, "_env_key", return_value=None), mock.patch.object(
            tokens, "_http_json"
        ) as http:
            with self.assertRaises(RuntimeError):
                tokens.fetch_go()
        http.assert_not_called()


class RouteTest(unittest.TestCase):
    def test_opencode_is_a_plan(self):
        self.assertEqual(tokens._route("opencode-go", "https://opencode.ai/zen/go/v1"), "plan")

    def test_nous_is_prepaid_credit(self):
        self.assertEqual(tokens._route("nous", "https://portal.nousresearch.com/v1"), "credit")

    def test_an_unknown_route_is_not_guessed(self):
        self.assertIsNone(tokens._route("local", "http://127.0.0.1:8080/v1"))
        self.assertIsNone(tokens._route(None, None))


class ReadTokensTest(TempPathsCase):
    SCHEMA = """
        create table sessions (
            id text primary key, model text, message_count integer,
            input_tokens integer, output_tokens integer, cache_read_tokens integer,
            cache_write_tokens integer, reasoning_tokens integer,
            api_call_count integer, estimated_cost_usd real, actual_cost_usd real,
            cost_status text, cost_source text, started_at real,
            last_activity_at real, ended_at real, source text,
            billing_provider text, billing_base_url text
        )
    """

    def setUp(self):
        super().setUp()
        self.now = datetime.now().astimezone().timestamp()
        # Pin the "today" boundary to 24 h before the fixture clock instead of
        # the real local midnight: between 00:00 and 01:00 the "closed" row
        # (now - 3600) lands on yesterday, the production filter legitimately
        # drops it, and the 1200 expectation fails on a correct helper. The
        # boundary still separates the recent rows from the "old" one.
        boundary = mock.patch.object(tokens, "_today_start", return_value=self.now - 86400)
        boundary.start()
        self.addCleanup(boundary.stop)
        connection = sqlite3.connect(tokens.STATE_DB)
        connection.execute(self.SCHEMA)
        rows = [
            # Live session, still open: its whole history counts as today.
            ("open", "deepseek-v4.1-flash", 40, 1000, 500, 20000, 0, 300, 12, 0.0, 0.0, "unknown", "none", self.now - 7200, self.now, None, "gui", "opencode-go", "https://opencode.ai/zen/go/v1"),
            # Same morning, already ended.
            ("closed", "deepseek-v4.1-flash", 10, 200, 100, 1000, 5, 20, 3, 0.4, 0.4, "estimated", "table", self.now - 3600, self.now - 1800, self.now - 1700, "gui", None, None),
            # Yesterday: must not appear in the "today" totals.
            ("old", "deepseek-v4.1-flash", 99, 999999, 999999, 0, 0, 0, 99, 9.0, 9.0, "estimated", "table", self.now - 200000, self.now - 190000, self.now - 180000, "gui", None, None),
            # A headless probe from today: nobody opened it, so it is not the
            # user's spend even though the row is recent. This is the 78 K bug.
            ("probe", "deepseek-v4.1-flash", 2, 78000, 40, 0, 0, 0, 1, 0.0, 0.0, "unknown", "none", self.now - 900, self.now - 800, self.now - 700, "oneshot", None, None),
            # A delegation child: machine-paced too.
            ("child", "deepseek-v4.1-flash", 2, 9000, 20, 0, 0, 0, 1, 0.0, 0.0, "unknown", "none", self.now - 900, self.now - 800, self.now - 700, "subagent", None, None),
        ]
        connection.executemany("insert into sessions values (" + ",".join("?" * 19) + ")", rows)
        connection.commit()
        connection.close()

    def _write_window(self, model: str = "deepseek-v4.1-flash", length: int = 1000000) -> None:
        tokens.MODEL_METADATA_FILE.write_text(
            json.dumps({"https://inference.example/v1": {"models": {model: {"context_length": length}}}}),
            encoding="utf-8",
        )

    def _write_context_cache(self, entries: dict[str, int]) -> None:
        """The shape Hermes writes: one section, `model@base_url: int`, wrapped."""
        lines = ["context_lengths:"]
        for key, length in entries.items():
            lines.append(f"  {key}: {length}")
        tokens.CONTEXT_WINDOW_FILE.write_text("\n".join(lines) + "\n", encoding="utf-8")

    def test_sums_only_the_sessions_with_activity_today(self):
        block = tokens.read_tokens()
        today = block["today"]
        self.assertEqual(today["input"], 1200)
        self.assertEqual(today["output"], 600)
        self.assertEqual(today["cache_read"], 21000)
        self.assertEqual(today["calls"], 15)
        self.assertEqual(today["sessions"], 2)
        self.assertAlmostEqual(today["actual_cost_usd"], 0.4)
        self.assertEqual(today["cost_unknown_sessions"], 1)

    def test_machine_paced_sessions_are_not_the_users_spend(self):
        """The probe and the child are today's rows and stay out of the totals."""
        today = tokens.read_tokens()["today"]
        self.assertEqual(today["input"], 1200)
        self.assertEqual(today["sessions"], 2)

    def test_the_session_block_describes_the_open_session(self):
        block = tokens.read_tokens()
        session = block["session"]
        self.assertEqual(session["id"], "open")
        self.assertEqual(session["input"], 1000)
        self.assertEqual(session["calls"], 12)
        self.assertEqual(session["cost_status"], "unknown")
        self.assertEqual(session["provider"], "opencode-go")
        self.assertEqual(session["route"], "plan")
        self.assertIsNone(block["error"])

    def test_a_reaped_session_does_not_pin_the_block(self):
        """A row the reaper left with ended_at NULL must not describe a live chat."""
        connection = sqlite3.connect(tokens.STATE_DB)
        connection.execute(
            "update sessions set last_activity_at = ?, started_at = ? where id = 'open'",
            (self.now - tokens.STALE_SESSION_SECONDS - 60, self.now - tokens.STALE_SESSION_SECONDS - 120),
        )
        connection.commit()
        connection.close()
        block = tokens.read_tokens()
        self.assertIsNone(block["session"])
        self.assertIsNone(block["error"])

    def test_an_active_open_session_wins_over_a_stale_newer_row(self):
        """The filter is the age of the activity, not the id or the start time."""
        connection = sqlite3.connect(tokens.STATE_DB)
        connection.execute(
            "update sessions set last_activity_at = ?, started_at = ? where id = 'open'",
            (self.now - tokens.STALE_SESSION_SECONDS - 60, self.now - 600),
        )
        connection.execute(
            "insert into sessions values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            ("resumed", "deepseek-v4.1-flash", 7, 700, 70, 0, 0, 0, 4, 0.0, 0.0,
             "unknown", "none", self.now - 36000, self.now - 30, None, "gui",
             "opencode-go", "https://opencode.ai/zen/go/v1"),
        )
        connection.commit()
        connection.close()
        self.assertEqual(tokens.read_tokens()["session"]["id"], "resumed")

    def test_context_pressure_is_the_last_api_call_of_that_session(self):
        self._write_window()
        tokens.AGENT_LOG.write_text(
            "2026-11-17 14:20:06 INFO [open] agent.conversation_loop: API call #1: model=m provider=p in=120000 out=1 total=120001 latency=1.0s\n"
            "2026-11-17 14:20:07 INFO [closed] agent.conversation_loop: API call #1: model=m provider=p in=999999 out=1 total=1 latency=1.0s\n"
            "2026-11-17 14:21:06 INFO [open] agent.conversation_loop: API call #2: model=m provider=p in=150000 out=1 total=150001 latency=1.0s\n",
            encoding="utf-8",
        )
        session = tokens.read_tokens()["session"]
        self.assertEqual(session["context_used"], 150000)
        self.assertEqual(session["context_max"], 1000000)
        self.assertEqual(session["context_pct"], 15)
        self.assertEqual(session["context_source"], "provider_usage")
        self.assertFalse(session["context_estimated"])

    def test_an_unknown_window_invents_no_ceiling(self):
        """No ceiling is invented, and the row does not have to disappear."""
        tokens.AGENT_LOG.write_text(
            "2026-11-17 14:21:06 INFO [open] agent.conversation_loop: API call #2: model=m provider=p in=150000 out=1 total=1 latency=1.0s\n",
            encoding="utf-8",
        )
        session = tokens.read_tokens()["session"]
        self.assertIsNone(session["context_max"])
        self.assertIsNone(session["context_pct"])
        self.assertEqual(session["context_used"], 150000)
        self.assertFalse(session["context_window_known"])

    def test_a_machine_paced_session_never_becomes_the_open_session(self):
        """A delegation child is an open row too, and a newer one every time.

        Without the filter the card describes the child instead of the user's
        chat, and a child runs on a cheaper model whose window is often not
        cached -- so the context row vanished while the user was still typing.
        """
        connection = sqlite3.connect(tokens.STATE_DB)
        # The fixture's own chat is the newest row; the child has to overtake it,
        # which is what happens in practice: a delegation writes activity now.
        connection.execute(
            "update sessions set last_activity_at = ? where id = 'open'", (self.now - 120,)
        )
        connection.execute(
            "insert into sessions values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            ("delegate", "mimo-v2.6-flash", 4, 40, 20, 0, 0, 0, 2, 0.0, 0.0,
             "unknown", "none", self.now - 60, self.now - 5, None, "subagent",
             "opencode-go", "https://opencode.ai/zen/go/v1"),
        )
        connection.commit()
        connection.close()
        self.assertEqual(tokens.read_tokens()["session"]["id"], "open")

    def test_the_window_comes_from_the_agents_own_cache(self):
        """The panel's ceiling is not the picker's cache alone.

        On disk Hermes persists what its resolver learned in
        `context_length_cache.yaml`, keyed `model@base_url` and often wrapped onto
        the next line. The open session is served by opencode-go while the ceiling
        was learned through the Nous endpoint, which is the live case: matching the
        model id is what makes the percentage appear at all.
        """
        tokens.CONTEXT_WINDOW_FILE.write_text(
            "context_lengths:\n"
            "  upstage/solar-mini4:free@https://inference-api.nousresearch.com/v1: 524288\n"
            "  deepseek/deepseek-v4.1-flash@https://inference-api.nousresearch.com/v1: \n"
            "    1048576\n",
            encoding="utf-8",
        )
        tokens.AGENT_LOG.write_text(
            "2026-11-17 14:21:06 INFO [open] agent.conversation_loop: API call #2: model=m provider=p in=62931 out=1 total=1 latency=1.0s\n",
            encoding="utf-8",
        )
        session = tokens.read_tokens()["session"]
        self.assertEqual(session["context_max"], 1048576)
        self.assertEqual(session["context_used"], 62931)
        self.assertEqual(session["context_pct"], 6)
        self.assertEqual(session["context_source"], "provider_usage")

    def test_the_served_endpoints_ceiling_wins(self):
        """Same model, two endpoints, two limits: the one serving the session counts."""
        self._write_context_cache(
            {
                "deepseek/deepseek-v4.1-flash@https://inference-api.nousresearch.com/v1": 1048576,
                "deepseek/deepseek-v4.1-flash@https://opencode.ai/zen/go/v1": 262144,
            }
        )
        self.assertEqual(tokens.read_tokens()["session"]["context_max"], 262144)

    def test_capacity_is_reported_without_a_percentage(self):
        """The ceiling is a fact about the model; the buffer may be unknown."""
        self._write_context_cache({"deepseek-v4.1-flash@https://opencode.ai/zen/go/v1": 1048576})
        session = tokens.read_tokens()["session"]
        self.assertEqual(session["context_max"], 1048576)
        self.assertIsNone(session["context_used"])
        self.assertIsNone(session["context_pct"])
        self.assertIsNone(session["context_source"])

    def test_a_session_with_no_log_line_falls_back_to_the_average(self):
        self._write_window()
        connection = sqlite3.connect(tokens.STATE_DB)
        connection.execute(
            "create table session_model_usage (session_id text, model text, task text, "
            "api_call_count integer, cache_read_tokens integer, cache_write_tokens integer, last_seen real)"
        )
        connection.execute(
            "insert into session_model_usage values ('open', 'deepseek-v4.1-flash', '', 10, 800000, 0, 1.0)"
        )
        connection.commit()
        connection.close()
        session = tokens.read_tokens()["session"]
        self.assertEqual(session["context_used"], 80000)
        self.assertEqual(session["context_pct"], 8)
        self.assertEqual(session["context_source"], "estimate")
        self.assertTrue(session["context_estimated"])

    def test_a_missing_database_is_reported_not_raised(self):
        tokens.STATE_DB.unlink()
        block = tokens.read_tokens()
        self.assertEqual(block["error"], "no state.db")
        self.assertIsNone(block["today"])
        self.assertIsNone(block["session"])

    def test_a_broken_database_is_reported_not_raised(self):
        tokens.STATE_DB.write_text("not a database")
        block = tokens.read_tokens()
        self.assertIsNotNone(block["error"])
        self.assertIsNone(block["today"])


class NotifyAllowanceTest(TempPathsCase):
    def setUp(self):
        super().setUp()
        self.run = mock.Mock()
        for patcher in (
            mock.patch.object(tokens.shutil, "which", return_value="/usr/bin/notify-send"),
            mock.patch.object(tokens.subprocess, "run", self.run),
            mock.patch.object(tokens.sys, "argv", ["tokens.py"]),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    @staticmethod
    def go(*percents):
        keys = ("rolling", "weekly", "monthly")
        return {
            "ok": True,
            "stale": False,
            "windows": [{"key": keys[i], "percent": p, "resets_at": "2026-11-29T18:13:02Z"} for i, p in enumerate(percents)],
        }

    def notified(self):
        # notify-send -a <app> -u <urgency> <title> <body>
        return [call.args[0][5] for call in self.run.call_args_list]

    def test_says_nothing_below_the_alert_threshold(self):
        tokens.notify_allowance(self.go(0, 38, 45))
        self.run.assert_not_called()

    def test_warns_once_per_window_and_level(self):
        tokens.notify_allowance(self.go(0, 38, 55))
        tokens.notify_allowance(self.go(0, 38, 56))
        self.assertEqual(self.notified(), ["OpenCode Go monthly at 55%"])

    def test_escalates_from_alert_to_critical_once(self):
        tokens.notify_allowance(self.go(0, 0, 55))
        tokens.notify_allowance(self.go(0, 0, 85))
        tokens.notify_allowance(self.go(0, 0, 90))
        self.assertEqual(self.notified(), ["OpenCode Go monthly at 55%", "OpenCode Go monthly at 85%"])
        self.assertEqual(self.run.call_args_list[-1].args[0][4], "critical")

    def test_rearms_when_the_window_resets(self):
        tokens.notify_allowance(self.go(0, 0, 85))
        tokens.notify_allowance(self.go(0, 0, 3))  # window reset
        tokens.notify_allowance(self.go(0, 0, 60))  # climbed again
        self.assertEqual(len(self.notified()), 2)

    def test_ignores_a_stale_or_failed_block(self):
        stale = self.go(0, 0, 99)
        stale["stale"] = True
        tokens.notify_allowance(stale)
        failed = self.go(0, 0, 99)
        failed["ok"] = False
        tokens.notify_allowance(failed)
        self.run.assert_not_called()

    def test_honours_thresholds_passed_on_the_command_line(self):
        tokens.sys.argv = ["tokens.py", "--alert", "50", "--critical", "80"]
        tokens.notify_allowance(self.go(0, 60, 0))
        self.assertEqual(self.notified(), ["OpenCode Go weekly at 60%"])

    def test_stays_silent_without_a_notification_client(self):
        tokens.shutil.which.return_value = None
        tokens.notify_allowance(self.go(0, 0, 99))
        self.run.assert_not_called()
        self.assertFalse(tokens.NOTICE_FILE.exists())

    def test_the_armed_state_survives_a_restart(self):
        tokens.notify_allowance(self.go(0, 0, 60))
        self.assertTrue(tokens.NOTICE_FILE.exists())
        self.assertTrue(json.loads(tokens.NOTICE_FILE.read_text())["monthly:alert"])


class MainTest(TempPathsCase):
    def run_main(self):
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            code = tokens.main()
        return code, json.loads(stdout.getvalue())

    def setUp(self):
        super().setUp()
        for patcher in (
            mock.patch.object(tokens, "_lock", return_value=None),
            mock.patch.object(tokens.subprocess, "run", mock.Mock()),
            mock.patch.object(tokens.shutil, "which", return_value=None),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_prints_one_json_object_and_always_exits_zero(self):
        with mock.patch.object(tokens, "fetch_nous", return_value={"balance_usd": 1.0}), mock.patch.object(
            tokens, "fetch_go", return_value={"windows": []}
        ), mock.patch.object(tokens, "read_tokens", return_value={"today": None, "session": None, "error": None}):
            code, payload = self.run_main()
        self.assertEqual(code, 0)
        self.assertEqual(set(payload), {"generated_epoch", "generated_at", "ttl_seconds", "nous", "go", "tokens"})
        self.assertRegex(payload["generated_at"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")

    def test_a_dead_provider_still_produces_a_parseable_payload(self):
        with mock.patch.object(tokens, "fetch_nous", side_effect=RuntimeError("http 401")), mock.patch.object(
            tokens, "fetch_go", side_effect=RuntimeError("http 403")
        ), mock.patch.object(tokens, "read_tokens", return_value={"today": None, "session": None, "error": None}):
            code, payload = self.run_main()
        self.assertEqual(code, 0)
        self.assertFalse(payload["nous"]["ok"])
        self.assertEqual(payload["nous"]["error"], "http 401")
        self.assertEqual(payload["go"]["error"], "http 403")

    def test_the_account_identity_never_reaches_stdout(self):
        account = {
            "email": "someone@example.com",
            "organization": {"id": "org_123", "name": "Personal"},
            "purchased_credits_remaining": 19.49,
            "member_spend_usd": "0.51",
            "total_usable_credits": 19.49,
        }

        def http(url, token):
            return account if "nousresearch" in url else FetchGoTest.PAYLOAD

        with mock.patch.object(tokens, "_nous_token", return_value="t"), mock.patch.object(
            tokens, "_env_key", return_value="k"
        ), mock.patch.object(tokens, "_http_json", side_effect=http), mock.patch.object(
            tokens, "read_tokens", return_value={"today": None, "session": None, "error": None}
        ):
            code, payload = self.run_main()
        self.assertEqual(code, 0)
        dumped = json.dumps(payload)
        self.assertNotIn("example.com", dumped)
        self.assertNotIn("org_123", dumped)
        self.assertNotIn("Personal", dumped)
        self.assertAlmostEqual(payload["nous"]["balance_usd"], 19.49)


if __name__ == "__main__":
    unittest.main()
