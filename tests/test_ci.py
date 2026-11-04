"""Offline tests for the rate-limited GitHub Actions run cache."""

from copy import deepcopy
from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
import json
import multiprocessing
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    "reol_ci", Path(__file__).resolve().parents[1] / "tools" / "ci.py"
)
CI = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = CI
SPEC.loader.exec_module(CI)

REPO = "fewnfds/reol"
RUN_ID = 41762510648
SHA = "a29314667f6a743fd3177b0a5190c810c2b6650b"


def run_state(status="in_progress", conclusion="", sha=SHA, run_id=RUN_ID, repo=REPO):
    return {
        "status": status,
        "conclusion": conclusion,
        "headSha": sha,
        "url": f"https://github.com/{repo}/actions/runs/{run_id}",
        "databaseId": run_id,
    }


class FakeClock:
    def __init__(self):
        self.value = 10000.0

    def now(self):
        return self.value

    def advance(self, seconds):
        self.value += seconds


class FakeQuery:
    def __init__(self, *results):
        self.results = list(results)
        self.calls = []

    def __call__(self, repo, run_id):
        self.calls.append((repo, run_id))
        if not self.results:
            raise AssertionError("unexpected external query")
        result = self.results.pop(0)
        if isinstance(result, BaseException):
            raise result
        return deepcopy(result)


def _hold_monitor_lock(cache_dir, ready):
    """Hold the lock inside a query in a separate spawned process."""
    def query(_repo, _run_id):
        ready.send("ready")
        time.sleep(15)
        return run_state()

    try:
        monitor = CI.RunMonitor(
            Path(cache_dir), REPO, RUN_ID, SHA,
            query=query, now=lambda: 10000.0,
        )
        monitor.poll()
    except BaseException as exc:
        ready.send(f"{type(exc).__name__}: {exc}")
    finally:
        ready.close()


class RunMonitorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="reol-ci-test-")
        self.addCleanup(self.tmp.cleanup)
        self.cache = Path(self.tmp.name)
        self.clock = FakeClock()
        self.sleep_calls = []

    def unexpected_sleep(self, seconds):
        self.sleep_calls.append(seconds)
        raise AssertionError("poll must never sleep")

    def monitor(self, query, repo=REPO, run_id=RUN_ID, sha=SHA):
        return CI.RunMonitor(
            self.cache, repo, run_id, sha,
            query=query, now=self.clock.now, sleep=self.unexpected_sleep,
        )

    def assert_result(self, result, cached, state):
        self.assertEqual(result["cached"], cached)
        self.assertGreaterEqual(result["next_poll_in"], 0)
        for field in ("status", "conclusion", "headSha", "url", "databaseId"):
            self.assertEqual(result["state"][field], state[field])

    def retry_without_query(self, monitor, query):
        """A failed first attempt may have no state to return while cooling down."""
        count = len(query.calls)
        try:
            result = monitor.poll()
        except CI.CIError:
            pass
        else:
            self.assertTrue(result["cached"])
            self.assertGreaterEqual(result["next_poll_in"], 0)
        self.assertEqual(len(query.calls), count)

    def test_cache_is_shared_and_refreshes_only_at_300_seconds(self):
        self.assertEqual(CI.MIN_INTERVAL_SECONDS, 300)
        first_state = run_state(status="queued")
        second_state = run_state(status="in_progress")
        query = FakeQuery(first_state, second_state)
        self.assert_result(self.monitor(query).poll(), False, first_state)
        self.assertEqual(query.calls, [(REPO, RUN_ID)])

        # Reconstructing the monitor cannot bypass the on-disk deadline.
        self.clock.advance(295)
        cached = self.monitor(query).poll()
        self.assert_result(cached, True, first_state)
        self.assertEqual(cached["next_poll_in"], 5)
        self.assertEqual(len(query.calls), 1)

        self.clock.advance(5)
        self.assert_result(self.monitor(query).poll(), False, second_state)
        self.assertEqual(query.calls, [(REPO, RUN_ID), (REPO, RUN_ID)])
        self.assertEqual(self.sleep_calls, [])

    def test_each_completed_conclusion_stays_cached_across_instances(self):
        for index, conclusion in enumerate(("success", "failure", "cancelled", "timed_out")):
            with self.subTest(conclusion=conclusion):
                run_id = RUN_ID + index
                state = run_state(status="completed", conclusion=conclusion, run_id=run_id)
                query = FakeQuery(state)
                self.assert_result(self.monitor(query, run_id=run_id).poll(), False, state)
                self.clock.advance(10 * 365 * 24 * 60 * 60)
                self.assert_result(self.monitor(query, run_id=run_id).poll(), True, state)
                self.assertEqual(query.calls, [(REPO, run_id)])
        self.assertEqual(self.sleep_calls, [])

    def test_query_identity_must_match_sha_and_run_id(self):
        for index, bad in enumerate((
            run_state(sha="b" * 40),
            run_state(run_id=RUN_ID + 1),
        )):
            with self.subTest(bad=bad):
                run_id = RUN_ID + 100 + index
                bad["databaseId"] = run_id if index == 0 else run_id + 1
                query = FakeQuery(bad, run_state(run_id=run_id))
                monitor = self.monitor(query, run_id=run_id)
                with self.assertRaises(CI.CIError):
                    monitor.poll()
                self.assertEqual(len(query.calls), 1)
                self.retry_without_query(self.monitor(query, run_id=run_id), query)
                self.clock.advance(300)
                self.assert_result(self.monitor(query, run_id=run_id).poll(), False, run_state(run_id=run_id))
                self.assertEqual(len(query.calls), 2)
        self.assertEqual(self.sleep_calls, [])

    def test_query_error_is_wrapped_throttled_and_releases_lock(self):
        query = FakeQuery(OSError("temporary query failure"), run_state())
        with self.assertRaises(CI.CIError):
            self.monitor(query).poll()
        self.assertEqual(query.calls, [(REPO, RUN_ID)])
        self.clock.advance(299)
        self.retry_without_query(self.monitor(query), query)
        self.clock.advance(1)
        self.assert_result(self.monitor(query).poll(), False, run_state())
        self.assertEqual(query.calls, [(REPO, RUN_ID), (REPO, RUN_ID)])
        self.assertEqual(self.sleep_calls, [])

    def test_repo_and_run_each_have_independent_json_caches_without_credentials(self):
        secret = "fake-local-gh-token-please-do-not-persist"
        query = FakeQuery(
            run_state(), run_state(repo="example/other"), run_state(run_id=RUN_ID + 1),
        )
        with patch.dict(os.environ, {"GH_TOKEN": secret}):
            self.monitor(query).poll()
            self.monitor(query, repo="example/other").poll()
            self.monitor(query, run_id=RUN_ID + 1).poll()
            self.assert_result(self.monitor(query).poll(), True, run_state())

        self.assertEqual(query.calls, [
            (REPO, RUN_ID), ("example/other", RUN_ID), (REPO, RUN_ID + 1),
        ])
        cache_files = list(self.cache.rglob("*.json"))
        self.assertTrue(cache_files, "the persistent cache must contain JSON")
        for path in cache_files:
            text = path.read_text(encoding="utf-8")
            self.assertNotIn(secret, text)
            json.loads(text)
        self.assertEqual(self.sleep_calls, [])

    def test_wait_queries_at_least_300_seconds_apart_and_prints_only_changes(self):
        states = [
            run_state(status="queued"),
            run_state(status="queued"),
            run_state(status="in_progress"),
            run_state(status="in_progress"),
            run_state(status="completed", conclusion="success"),
        ]
        query = FakeQuery(*states)
        attempts = []
        sleeps = []

        def timed_query(repo, run_id):
            attempts.append(self.clock.now())
            return query(repo, run_id)

        def advance(seconds):
            sleeps.append(seconds)
            self.clock.advance(seconds)

        monitor = CI.RunMonitor(
            self.cache, REPO, RUN_ID, SHA,
            query=timed_query, now=self.clock.now, sleep=advance,
        )
        stdout, stderr = io.StringIO(), io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            result = monitor.wait(timeout=1500)
        self.assertEqual(result, 0)
        self.assertEqual(len(attempts), 5)
        self.assertTrue(all(right - left >= 300 for left, right in zip(attempts, attempts[1:])))
        self.assertEqual(sleeps, [300, 300, 300, 300])
        observed = [json.loads(line) for line in stdout.getvalue().splitlines()]
        self.assertEqual([row["state"]["status"] for row in observed], ["queued", "in_progress", "completed"])
        self.assertEqual(observed[-1]["state"]["conclusion"], "success")
        self.assertEqual(stderr.getvalue(), "")

    def test_wait_does_not_query_at_the_timeout_boundary(self):
        query = FakeQuery(run_state(), run_state())
        attempts = []
        sleeps = []

        def timed_query(repo, run_id):
            attempts.append(self.clock.now())
            return query(repo, run_id)

        def advance(seconds):
            sleeps.append(seconds)
            self.clock.advance(seconds)

        monitor = CI.RunMonitor(
            self.cache, REPO, RUN_ID, SHA,
            query=timed_query, now=self.clock.now, sleep=advance,
        )
        stdout, stderr = io.StringIO(), io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            result = monitor.wait(timeout=600)
        self.assertEqual(result, 2)
        self.assertEqual(attempts, [10000, 10300])
        self.assertEqual(sleeps, [300, 300])
        self.assertEqual(len(stdout.getvalue().splitlines()), 1)
        self.assertIn("timed out", stderr.getvalue())

    def test_wait_reports_terminal_failure_without_sleeping(self):
        query = FakeQuery(run_state(status="completed", conclusion="cancelled"))
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            result = self.monitor(query).wait(timeout=300)
        self.assertEqual(result, 1)
        self.assertEqual(len(query.calls), 1)
        self.assertEqual(json.loads(stdout.getvalue())["state"]["conclusion"], "cancelled")
        self.assertEqual(self.sleep_calls, [])

    def test_cross_process_lock_is_nonblocking_and_crash_keeps_attempt_deadline(self):
        context = multiprocessing.get_context("spawn")
        ready_reader, ready_writer = context.Pipe(duplex=False)
        child = context.Process(
            target=_hold_monitor_lock,
            args=(str(self.cache), ready_writer),
        )
        child.start()
        ready_writer.close()
        try:
            self.assertTrue(ready_reader.poll(10), "child never entered its query")
            self.assertEqual(ready_reader.recv(), "ready")
            query = FakeQuery(run_state())
            with self.assertRaises(CI.CIError):
                self.monitor(query).poll()
            self.assertEqual(query.calls, [])
            self.assertEqual(self.sleep_calls, [])

            # Simulate a process dying during the external call. The OS lock
            # must disappear, while the already-persisted attempt still limits
            # a fresh process from making a duplicate request.
            child.terminate()
            child.join(10)
            self.assertFalse(child.is_alive())
            self.retry_without_query(self.monitor(query), query)
            self.clock.advance(300)
            self.assert_result(self.monitor(query).poll(), False, run_state())
            self.assertEqual(query.calls, [(REPO, RUN_ID)])
            self.assertEqual(self.sleep_calls, [])
        finally:
            if child.is_alive():
                child.terminate()
                child.join(10)
            ready_reader.close()


if __name__ == "__main__":
    unittest.main()
