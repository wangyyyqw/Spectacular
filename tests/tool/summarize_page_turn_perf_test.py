"""原始帧统计口径与报告缺项回归；不调用设备。"""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("summary", ROOT / "tool/summarize_page_turn_perf.py")
summary = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(summary)


def report(book="book", mode="cover", scene="open", values=(1, 2, 9), rate=120):
    return {"book_sha256": book, "frame_timings_complete": True,
            "host_meminfo": {"samples": [{"total_pss_bytes": 100}]},
            "turns": [{"mode": mode, "scene": scene, "round": 0,
                       "snapshots_before": 5, "snapshots_after": 6,
                       "input_accepted_ms": 2, "animation_first_frame_ms": 12,
                       "animation_start_us": 200,
                       "frames": {"refresh_rate": rate, "frame_timings_complete": True,
                                  "build_p95_ms": 999,
                                  "raw_frames": [{"buildStart": 100 * (i + 1), "build_us": v * 1000,
                                                  "raster_us": max(0, 10 - v) * 1000} for i, v in enumerate(values)]}}]}


class SummaryTest(unittest.TestCase):
    def test_nearest_rank_uses_raw_frames_and_actual_budget_per_turn(self):
        a = report(values=(1,))
        b = report(values=(9, 10, 11), rate=60)
        result = summary.aggregate([a, b])["groups"][("book", "cover", "open")]
        stats = result["all_frames"]["ui"]
        self.assertEqual(stats["p50_ms"], 9)
        self.assertEqual(stats["p95_ms"], 11)
        self.assertEqual(stats["p99_ms"], 11)
        self.assertEqual(stats["max_ms"], 11)
        self.assertEqual(stats["over_budget_ratio"], 0)
        self.assertEqual(result["all_frames"]["raster"]["over_budget_ratio"], .25)

    def test_animation_uses_marker_and_stage_subtracts_accepted_time(self):
        source = report()
        result = summary.aggregate([source])["groups"][("book", "cover", "open")]
        self.assertEqual(result["stable_animation_frames"]["count"], 2)
        self.assertEqual(result["stable_animation_frames"]["ui"]["p50_ms"], 2)
        self.assertEqual(result["stages"]["accepted_to_animation_first_frame_ms"]["p95_ms"], 10)
        del source["turns"][0]["animation_start_us"]
        result = summary.aggregate([source])["groups"][("book", "cover", "open")]
        self.assertEqual(result["stable_animation_frames"]["count"], 0)
        self.assertIsNone(result["stable_animation_frames"]["ui"]["p95_ms"])

    def test_books_modes_scenes_missing_groups_memory_and_background_snapshot(self):
        base = report()
        candidate = copy.deepcopy(base)
        candidate["host_meminfo"]["samples"][0]["total_pss_bytes"] = 111
        result = summary.compare_reports([base, report("other", "scroll", "fling"),
                                          report(mode="cover", scene="far"),
                                          report(mode="scroll", scene="open")], [candidate])
        self.assertEqual(len(result["groups"]), 4)
        book = result["books"]["book"]
        self.assertIsNone(book["whole_report_pss_peak"]["within_limit"])
        self.assertFalse(book["whole_report_pss_peak"]["workload_comparable"])
        self.assertTrue(book["snapshot_peak"]["within_limit"])
        self.assertEqual(book["snapshot_peak"]["baseline"], 6)
        self.assertIsNone(result["groups"][-1]["candidate"])
        markdown = summary.render_markdown(result)
        self.assertIn("不是系统丢帧", markdown)
        self.assertIn("非模式／场景峰值", markdown)
        self.assertIn("缺报告或帧不完整", markdown)

    def test_explicit_invalid_turns_and_modes_are_excluded_before_parsing(self):
        source = report()
        invalid_turn = {"mode": "cover", "scene": "open", "valid": False,
                        "snapshots_after": 99}
        invalid_mode = {"mode": "scroll", "scene": "fling", "snapshots_after": 100}
        source["turns"].extend([invalid_turn, invalid_mode])
        source["invalid_modes"] = ["scroll"]
        result = summary.compare_reports([source], [report()])
        self.assertEqual(result["excluded_turns"], {"baseline": 2, "candidate": 0})
        self.assertEqual(len(result["groups"]), 1)
        self.assertEqual(result["groups"][0]["baseline"]["turn_count"], 1)
        self.assertEqual(result["books"]["book"]["snapshot_peak"]["baseline"], 6)
        self.assertIsNone(result["books"]["book"]["whole_report_pss_peak"]["within_limit"])
        self.assertIn("基线 2 次，候选 0 次", summary.render_markdown(result))

    def test_pss_is_attributed_to_wall_windows_and_missing_scene_stays_null(self):
        source = report()
        source["turns"][0].update(wall_start_ms=1000, wall_end_ms=1100)
        other = copy.deepcopy(source["turns"][0])
        other.update(scene="far", wall_start_ms=1200, wall_end_ms=1300)
        empty = copy.deepcopy(other)
        empty.update(mode="scroll", wall_start_ms=2000, wall_end_ms=2100)
        source["turns"].extend([other, empty])
        source["host_meminfo"]["samples"] = [
            {"host_epoch_ms": 999, "total_pss_bytes": 9999},
            {"host_epoch_ms": 1000, "total_pss_bytes": 100},
            {"host_epoch_ms": 1100, "total_pss_bytes": 150},
            {"host_epoch_ms": 1150, "total_pss_bytes": 500},
            {"host_epoch_ms": 1250, "total_pss_bytes": 200},
            {"total_pss_bytes": 10000},
        ]
        groups = summary.aggregate([source])["groups"]
        opened = groups[("book", "cover", "open")]
        self.assertEqual(opened["observed_pss_peak_bytes"], 150)
        self.assertEqual(opened["pss_sample_count"], 2)
        self.assertEqual(opened["pss_covered_turn_count"], 1)
        self.assertNotIn("wall_start_ms", opened["stages"])
        self.assertEqual(groups[("book", "cover", "far")]["observed_pss_peak_bytes"], 200)
        self.assertIsNone(groups[("book", "scroll", "far")]["observed_pss_peak_bytes"])
        old = summary.aggregate([report()])["groups"][("book", "cover", "open")]
        self.assertIsNone(old["observed_pss_peak_bytes"])
        self.assertEqual(old["pss_window_count"], 0)

    def test_whole_report_pss_verdict_requires_same_valid_workload(self):
        base = report()
        candidate = report()
        candidate["host_meminfo"]["samples"][0]["total_pss_bytes"] = 111
        result = summary.compare_reports([base], [candidate])
        self.assertFalse(result["books"]["book"]["whole_report_pss_peak"]["within_limit"])
        candidate["turns"].append(copy.deepcopy(candidate["turns"][0]))
        result = summary.compare_reports([base], [candidate])
        self.assertIsNone(result["books"]["book"]["whole_report_pss_peak"]["within_limit"])
        self.assertIn("不判断（模式／场景数量", summary.render_markdown(result))

    def test_invalid_raw_frames_fail_instead_of_using_cached_percentiles(self):
        source = report()
        del source["turns"][0]["frames"]["raw_frames"]
        with self.assertRaisesRegex(ValueError, "raw_frames"):
            summary.aggregate([source])

    def test_thresholds_use_stable_frames_and_accepted_animation_latency(self):
        source = report(scene="continuous", values=(100, 8, 8))
        source["turns"][0]["animation_first_frame_ms"] = 52
        group = summary.compare_reports([source], [source])["groups"][0]
        checks = group["performance_thresholds"]["candidate"]
        self.assertEqual(checks["frame_interval"], "stable_animation_frames")
        self.assertTrue(checks["passed"])
        self.assertEqual(checks["checks"]["ui.p95_ms"]["limit"], 1000 / 120)
        self.assertEqual(checks["checks"]["stage.accepted_to_animation_first_frame_ms.p95"]["value"], 50)

    def test_threshold_failures_and_incomplete_or_missing_samples(self):
        source = report(mode="scroll", scene="fling", values=(17,))
        result = summary.compare_reports([source], [source])
        checks = result["groups"][0]["performance_thresholds"]["candidate"]
        self.assertEqual(checks["frame_interval"], "all_frames")
        self.assertFalse(checks["checks"]["ui.p95_ms"]["passed"])
        self.assertFalse(checks["checks"]["ui.p99_ms"]["passed"])
        self.assertFalse(checks["checks"]["ui.over_budget_ratio"]["passed"])
        self.assertIn("性能阈值未达标／缺测", summary.render_markdown(result))
        source["frame_timings_complete"] = False
        checks = summary.compare_reports([source], [source])["groups"][0]["performance_thresholds"]["candidate"]
        self.assertIsNone(checks["passed"])
        source = report(scene="cross", values=())
        checks = summary.compare_reports([source], [source])["groups"][0]["performance_thresholds"]["candidate"]
        self.assertIsNone(checks["checks"]["ui.p95_ms"]["passed"])
        self.assertIsNone(checks["checks"]["stage.origin_feedback_ms.p95"]["passed"])
        source = report(scene="cold-cross")
        source["turns"][0]["origin_feedback_ms"] = 101
        checks = summary.compare_reports([source], [source])["groups"][0]["performance_thresholds"]["candidate"]
        self.assertFalse(checks["checks"]["stage.origin_feedback_ms.p95"]["passed"])

    def test_cli_writes_json_and_markdown(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "report.json"
            source.write_text(json.dumps(report()), encoding="utf-8")
            summary.main(["--baseline", str(source), "--candidate", str(source),
                          "--output-dir", str(root / "out"), "--book-label", "book=测试书"])
            result = json.loads((root / "out/comparison.json").read_text())
            self.assertEqual(result["books"]["book"]["label"], "测试书")
            self.assertIn("测试书", (root / "out/comparison.md").read_text())


if __name__ == "__main__":
    unittest.main()
