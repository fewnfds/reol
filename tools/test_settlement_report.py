"""Numerical and CLI counterexamples for the offline settlement log consumer."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from settlement_report import METRICS, analyze


def snapshot(at=240000, completed=8, stock=30):
    return {"at_ms": at, "actions": {"cook": completed}, "refusals": {"take:empty": 3},
            "generated": {"grain": 12}, "items": {"grain": 0, "meal": stock, "water": 20},
            "metrics": dict.fromkeys(METRICS, 0) | {"step_usec": 1000, "decision_usec": 700, "observations": 10},
            "satiety": [3000, 5000, 7000], "energy": [2000, 4000, 6000],
            "lowest_sampled": {"satiety": {"actor": 2, "value": 900},
                               "energy": {"actor": 3, "value": 100}},
            "districts": [{"name": "东院", "actions": {"cook": completed},
                           "items": {"grain": 0, "meal": stock, "water": 20}, "satiety": [3000, 5000, 7000],
                           "energy": [2000, 6000]}]}


def line(data, wall=1000):
    suffix = "" if wall is None else f" wall_ms={wall}"
    return "NORMAL_SETTLEMENT " + json.dumps(data, ensure_ascii=False) + suffix + "\n"


class SettlementReportTest(unittest.TestCase):
    def test_cumulative_baseline_units_stocks_and_sampled_low(self):
        a, b = snapshot(), snapshot(360000, 10, 25)
        b["metrics"].update({"step_usec": 3000, "decision_usec": 2000, "observations": 15})
        b["refusals"]["take:empty"] = 4
        report = analyze(line(a) + line(b, 5000) + "SETTLEMENT_CYCLE_SMOKE errors=0 final={Godot dictionary}\n")
        delta = report["observed_span"]
        self.assertEqual(delta["actions_delta"], {"cook": 2})
        self.assertEqual(delta["completed_per_sim_minute"], {"cook": 1})
        self.assertEqual((delta["simulation_ms"], delta["wall_ms"], delta["simulation_to_wall_ratio"]), (120000, 4000, 30))
        self.assertEqual(delta["items_delta"], {"grain": 0, "meal": -5, "water": 0})
        self.assertEqual(delta["refusals_delta"], {"take:empty": 1})
        self.assertEqual(delta["metrics_delta"]["decision_usec"], 1300)
        self.assertEqual(delta["districts"]["东院"]["resident_actions_delta"], {"cook": 2})
        self.assertEqual(delta["lowest_sampled_through_end"]["energy"]["value"], 100)
        self.assertEqual(report["terminal"]["kind"], "smoke")
        self.assertIsNone(report["process_exit_code"])

    def test_gap_uses_real_duration_without_interpolation(self):
        report = analyze(line(snapshot()) + line(snapshot(480000, 10), 3000))
        self.assertEqual(len(report["windows"]), 1)
        self.assertEqual(report["windows"][0]["completed_per_sim_minute"]["cook"], 0.5)

    def test_one_sample_and_absent_wall_are_unknown_not_zero(self):
        report = analyze(line(snapshot(), None))
        self.assertIsNone(report["observed_span"])
        self.assertEqual(report["terminal"]["kind"], "absent")
        pair = analyze(line(snapshot(), None) + line(snapshot(360000, 10), None))
        self.assertIsNone(pair["windows"][0]["wall_ms"])
        self.assertIsNone(pair["windows"][0]["simulation_to_wall_ratio"])

    def test_new_counter_can_appear_but_removed_nonzero_counter_is_reset(self):
        a, b = snapshot(), snapshot(360000, 10)
        b["generated"]["water"] = 5
        report = analyze(line(a) + line(b, 2000))
        self.assertEqual(report["windows"][0]["generated_delta"], {"grain": 0, "water": 5})
        del b["actions"]["cook"]
        with self.assertRaisesRegex(ValueError, "went backwards"):
            analyze(line(a) + line(b, 2000))

    def test_partial_and_runtime_failure_are_preserved(self):
        report = analyze(line(snapshot()) + "SCRIPT ERROR: bad state\nSETTLEMENT_CYCLE_PARTIAL errors=1 at_ms=250000\n")
        self.assertEqual(report["terminal"]["kind"], "partial")
        self.assertEqual(report["terminal"]["reported_errors"], 1)
        self.assertEqual(report["diagnostics"][0]["message"], "SCRIPT ERROR: bad state")

    def test_user_error_with_clean_smoke_marker_is_still_retained(self):
        report = analyze(line(snapshot()) + "  USER ERROR: rejected state\nSETTLEMENT_CYCLE_SMOKE errors=0\n")
        self.assertEqual(len(report["diagnostics"]), 1)
        self.assertEqual(report["diagnostics"][0]["message"], "USER ERROR: rejected state")
        self.assertIsNone(report["process_exit_code"])

    def test_no_samples_in_short_run_is_explicit(self):
        with self.assertRaisesRegex(ValueError, "no NORMAL_SETTLEMENT"):
            analyze("SETTLEMENT_CYCLE_PARTIAL errors=0 at_ms=1000\n")

    def test_malformed_terminal_does_not_report_fractional_errors_as_zero(self):
        for errors in ("0.5", "-1", "unknown"):
            with self.subTest(errors=errors), self.assertRaisesRegex(ValueError, "malformed terminal"):
                analyze(line(snapshot()) + f"SETTLEMENT_CYCLE_SMOKE errors={errors}\n")

    def test_reject_corrupt_or_ambiguous_json(self):
        malformed = ["NORMAL_SETTLEMENT {\"at_ms\": 2", "NORMAL_SETTLEMENT {\"at_ms\":1,\"at_ms\":2}",
                     "NORMAL_SETTLEMENT {\"at_ms\":NaN}", line(snapshot()) + "NORMAL_SETTLEMENT []"]
        for text in malformed:
            with self.subTest(text=text[-60:]), self.assertRaises(ValueError):
                analyze(text)

    def test_missing_wrong_and_negative_fields_are_not_assumed_zero(self):
        for field, value in (("metrics", None), ("actions", {"cook": True}),
                             ("generated", {"grain": -1}), ("refusals", []),
                             ("lowest_sampled", None), ("districts", [])):
            data = snapshot()
            data[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                analyze(line(data))

    def test_reject_clock_counter_reset_and_concatenation(self):
        a = line(snapshot())
        lower = snapshot(360000, 10)
        lower["metrics"]["step_usec"] = 1
        cases = [a + line(snapshot(), 2000), a + line(snapshot(360000), 999), a + line(lower, 2000),
                 a + "SETTLEMENT_CYCLE_PARTIAL errors=0\nSETTLEMENT_CYCLE_SMOKE errors=0\n",
                 a + "SETTLEMENT_CYCLE_PARTIAL errors=0\n" + line(snapshot(360000), 2000)]
        for content in cases:
            with self.subTest(tail=content[-60:]), self.assertRaises(ValueError):
                analyze(content)

    def test_missing_fixed_stock_or_metric_and_unclassified_gauge_rejected(self):
        for part, key in (("items", "grain"), ("metrics", "decisions")):
            data = snapshot(); del data[part][key]
            with self.subTest(part=part), self.assertRaisesRegex(ValueError, "missing fixed"):
                analyze(line(data))
        data = snapshot(); data["metrics"]["oldest_age_ms"] = 100
        with self.assertRaisesRegex(ValueError, "classify new counters/gauges"):
            analyze(line(data))

    def test_district_identity_is_checked_by_name_not_list_order(self):
        a = snapshot()
        other = copy.deepcopy(a["districts"][0]); other["name"] = "西院"
        a["districts"].append(other)
        b = copy.deepcopy(a); b["at_ms"] = 360000; b["districts"].reverse()
        self.assertEqual(set(analyze(line(a) + line(b, 2000))["windows"][0]["districts"]), {"东院", "西院"})
        b["districts"][0]["name"] = "南院"
        with self.assertRaisesRegex(ValueError, "district membership changed"):
            analyze(line(a) + line(b, 2000))

    def test_spatial_stock_transfer_does_not_imply_resident_production(self):
        a = snapshot()
        other = copy.deepcopy(a["districts"][0]); other["name"] = "西院"
        other["items"]["grain"] = 4; a["items"]["grain"] = 4
        a["districts"].append(other)
        b = copy.deepcopy(a); b["at_ms"] = 360000
        b["districts"][0]["items"]["grain"] = 4
        b["districts"][1]["items"]["grain"] = 0
        delta = analyze(line(a) + line(b, 2000))["observed_span"]
        self.assertEqual(delta["districts"]["东院"]["resident_actions_delta"]["cook"], 0)
        self.assertEqual(delta["districts"]["东院"]["spatial_items_delta"]["grain"], 4)
        self.assertEqual(delta["districts"]["西院"]["spatial_items_delta"]["grain"], -4)
        self.assertEqual(delta["items_delta"]["grain"], 0)

    def test_cli_does_not_overwrite_source_or_existing_report(self):
        tool = Path(__file__).with_name("settlement_report.py")
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "input.log"
            output = Path(folder) / "result.json"
            raw = line(snapshot()) + "SETTLEMENT_CYCLE_SMOKE errors=2\n"
            source.write_text(raw, encoding="utf-8")
            def run(target):
                return subprocess.run([sys.executable, "-X", "utf8", str(tool), str(source), "--output", str(target)],
                                      capture_output=True, text=True, encoding="utf-8", timeout=10)
            self.assertEqual(run(source).returncode, 2)
            self.assertEqual(source.read_text(encoding="utf-8"), raw)
            result = run(output)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(report["terminal"]["reported_errors"], 2)
            self.assertIsNone(report["process_exit_code"])
            written = output.read_bytes()
            self.assertEqual(run(output).returncode, 2)
            self.assertEqual(output.read_bytes(), written)


if __name__ == "__main__":
    unittest.main()
