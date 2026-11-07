"""A partial, duplicated, failed, or mixed shard set cannot certify coverage."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location(
    "reol_test_reports", Path(__file__).resolve().parents[1] / "tools/check_test_reports.py"
)
reports = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reports)


class TestReportCoverageTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.paths = [Path(self.directory.name) / f"check-test-timings-{i}.jsonl" for i in (1, 2)]
        names = [f"test_{letter}" for letter in "abcde"]
        self.events = []
        for index in (1, 2):
            selected = names[index - 1::2]
            events = [{"event": "run_started", "registered_suites": names,
                       "registered_count": 5, "shard_index": index, "shard_count": 2, "suites": selected}]
            for name in selected:
                events += [{"event": "suite_started", "suite": name},
                           {"event": "suite_finished", "suite": name, "checks": 3,
                            "assertion_failures": 0, "elapsed_ms": 10.0}]
            events.append({"event": "run_finished", "passed": len(selected), "failed": 0,
                           "checks": 3 * len(selected)})
            self.events.append(events)

    def verify(self):
        for path, events in zip(self.paths, self.events):
            path.write_text("".join(json.dumps(event) + "\n" for event in events), encoding="utf-8")
        return reports.verify_reports(self.paths, 2)

    def test_complete_disjoint_shards_preserve_all_suites_and_counts(self):
        self.assertEqual(self.verify(), {"suites": 5, "checks": 15, "shard_ms": {1: 30.0, 2: 20.0}})

    def test_missing_report_and_duplicate_report_fail(self):
        self.verify()
        for paths in [self.paths[:1], [self.paths[0], self.paths[0]]]:
            with self.subTest(paths=paths), self.assertRaises(reports.ReportError):
                reports.verify_reports(paths, 2)

    def test_timeout_without_terminal_record_fails(self):
        self.events[0].pop()
        with self.assertRaises(reports.ReportError):
            self.verify()

    def test_missing_suite_events_fail(self):
        del self.events[0][1:3]
        with self.assertRaises(reports.ReportError):
            self.verify()

    def test_a_selected_subset_cannot_replace_the_partition(self):
        self.events[0][0]["suites"] = ["test_a"]
        self.events[0] = [self.events[0][0], *self.events[0][1:3],
                          {"event": "run_finished", "passed": 1, "failed": 0, "checks": 3}]
        with self.assertRaises(reports.ReportError):
            self.verify()

    def test_different_registries_fail(self):
        self.events[1][0]["registered_suites"] = ["test_a", "test_b", "test_c", "test_d", "test_f"]
        with self.assertRaises(reports.ReportError):
            self.verify()

    def test_failed_assertions_or_run_totals_fail(self):
        self.events[0][2]["assertion_failures"] = 1
        with self.assertRaises(reports.ReportError):
            self.verify()
        self.events[0][2]["assertion_failures"] = 0
        self.events[0][-1]["failed"] = 1
        with self.assertRaises(reports.ReportError):
            self.verify()

    def test_summary_must_match_executed_checks(self):
        self.events[0][-1]["checks"] += 1
        with self.assertRaises(reports.ReportError):
            self.verify()

    def test_invalid_event_or_counts_fail(self):
        for value in [True, -1, "3", None]:
            with self.subTest(value=value):
                self.events[0][2]["checks"] = value
                with self.assertRaises(reports.ReportError):
                    self.verify()

    def test_invalid_json_fails(self):
        self.verify()
        self.paths[0].write_text("{partial", encoding="utf-8")
        with self.assertRaises(ValueError):
            reports.verify_reports(self.paths, 2)


if __name__ == "__main__":
    unittest.main()
