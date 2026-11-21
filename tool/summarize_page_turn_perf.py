#!/usr/bin/env python3
"""聚合翻页原始帧并比较基线与候选版，不读取或控制设备。"""
import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path


NOTES = [
    "分位数使用 nearest rank，对组内原始帧合并计算，不平均每次翻页的分位数。",
    "UI／Raster 分别按该次采样实际刷新率判断超预算；Flutter 超预算帧不是系统丢帧。",
    "animation_start_us 记录首动画帧 postFrame 时刻；稳定动画取 buildStart >= 该标记，排除首帧，全段保留首帧。缺少标记时稳定动画留空，滚动看全段。",
    "性能阈值按各组稳定动画或滚动全段判定；P95 使用组内最短实际帧预算（刷新率混合时保守判断），P99 ≤16.67ms、超预算率 ≤5%。",
    "旧 longest_ui_gap_ms=0 不代表没有阻塞；基线 events 为空，事件明细仅候选阶段可用，不据空事件推断零耗时。",
    "阶段耗时以输入事件为起点；accepted_to_* 为扣除输入接受耗时后的等待，trace 为每次追踪事件。",
    "场景 PSS 仅按 wall_start_ms <= host_epoch_ms <= wall_end_ms 归属离散观测；未命中样本留空，不以整轮峰值替代。",
    "旧报告只有整轮 PSS，非模式／场景峰值；整轮仅在有效模式／场景样本数量及报告数量一致且无作废样本时比较阈值，仍不能确认各场景内存达标。",
    "快照峰值只取采样前后观测值，可能包含背景图；与同书基线观测上限比较，不假定总数为 5。",
]


def _number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def nearest_rank(values, percentile):
    if not values:
        return None
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * percentile / 100) - 1)]


def distribution(values):
    return {
        "count": len(values),
        **{f"p{p}_ms": nearest_rank(values, p) for p in (50, 95, 99)},
        "max_ms": max(values, default=None),
    }


def frame_summary(frames):
    result = {"count": len(frames)}
    for name, key in (("ui", "build_us"), ("raster", "raster_us")):
        values = [frame[key] / 1000 for frame, _ in frames]
        over = sum(value > budget for value, (_, budget) in zip(values, frames))
        result[name] = {
            **distribution(values),
            "over_budget_count": over,
            "over_budget_ratio": over / len(values) if values else None,
        }
    result["frame_budgets_ms"] = sorted({budget for _, budget in frames})
    result["refresh_rates_hz"] = sorted({1000 / budget for _, budget in frames})
    return result


def _budget(turn, report):
    frames = turn["frames"]
    rate = frames.get("refresh_rate", report.get("viewport", {}).get("refresh_rate"))
    if _number(rate) and rate > 0:
        return 1000 / rate
    raise ValueError("原始帧缺少有效实际刷新率，不能判断超预算")


def _frames(turn, report):
    raw = turn.get("frames", {}).get("raw_frames")
    if not isinstance(raw, list):
        raise ValueError("报告缺少 raw_frames，不能用已有分位数代替原始帧聚合")
    if not raw:
        return []
    budget = _budget(turn, report)
    for frame in raw:
        if any(not _number(frame.get(key)) or frame[key] < 0
               for key in ("build_us", "raster_us", "buildStart")):
            raise ValueError("原始帧的 buildStart／build_us／raster_us 无效")
    return [(frame, budget) for frame in raw]


def _snapshot_peak(turns):
    return max((value for turn in turns for key in ("snapshots_before", "snapshots_after")
                if _number(value := turn.get(key))), default=None)


def _pss_peak(report):
    memory = report.get("host_meminfo", {})
    values = [sample.get("total_pss_bytes") for sample in memory.get("samples", [])]
    values.append(memory.get("peak_total_pss_bytes"))
    return max((value for value in values if _number(value)), default=None)


def aggregate(reports):
    buckets = defaultdict(list)
    books = defaultdict(lambda: {"reports": [], "pss_peaks": [], "snapshot_peaks": [],
                                 "excluded_turn_count": 0, "workload": Counter()})
    for report in reports:
        book = report.get("book_sha256")
        if not isinstance(book, str) or not book:
            raise ValueError("报告缺少 book_sha256，无法保证比较同一本书")
        turns = report.get("turns")
        if not isinstance(turns, list):
            raise ValueError("报告缺少 turns")
        valid_turns = [turn for turn in turns if turn.get("valid") is not False
                       and turn.get("mode") not in report.get("invalid_modes", [])]
        excluded = len(turns) - len(valid_turns)
        books[book]["excluded_turn_count"] += excluded
        books[book]["reports"].append({
            "path": report.get("_path"),
            "contract": report.get("contract"),
            "viewport": report.get("viewport"),
            "provenance": report.get("provenance"),
            "frame_timings_complete": report.get("frame_timings_complete"),
            "excluded_turn_count": excluded,
            "invalid_modes": report.get("invalid_modes", []),
        })
        books[book]["pss_peaks"].append(_pss_peak(report))
        books[book]["snapshot_peaks"].append(_snapshot_peak(valid_turns))
        for turn in valid_turns:
            if not turn.get("mode") or not turn.get("scene"):
                raise ValueError("翻页采样缺少 mode／scene")
            buckets[(book, turn["mode"], turn["scene"])].append((turn, report))
            books[book]["workload"][(turn["mode"], turn["scene"])] += 1
    groups = {key: _aggregate_group(samples) for key, samples in buckets.items()}
    for book in books.values():
        book["whole_report_pss_peak_bytes"] = max(
            (v for v in book.pop("pss_peaks") if v is not None), default=None)
        book["snapshot_peak"] = max(
            (v for v in book.pop("snapshot_peaks") if v is not None), default=None)
        book["workload"] = [{"mode": mode, "scene": scene, "turn_count": count}
                            for (mode, scene), count in sorted(book["workload"].items())]
    return {"books": dict(books), "groups": groups,
            "excluded_turn_count": sum(book["excluded_turn_count"] for book in books.values())}


def _scene_memory(samples):
    matched = {}
    windows = covered = 0
    for turn, report in samples:
        start, end = turn.get("wall_start_ms"), turn.get("wall_end_ms")
        if not (_number(start) and _number(end) and end >= start):
            continue
        windows += 1
        found = False
        for index, sample in enumerate(report.get("host_meminfo", {}).get("samples", [])):
            timestamp, value = sample.get("host_epoch_ms"), sample.get("total_pss_bytes")
            if _number(timestamp) and start <= timestamp <= end and _number(value):
                matched[(id(report), index)] = value
                found = True
        covered += found
    return {"observed_pss_peak_bytes": max(matched.values(), default=None),
            "pss_sample_count": len(matched), "pss_window_count": windows,
            "pss_covered_turn_count": covered}


def _aggregate_group(samples):
    frames, stable = [], []
    stages, traces = defaultdict(list), defaultdict(list)
    markers = 0
    for turn, report in samples:
        current = _frames(turn, report)
        frames.extend(current)
        if _number(start := turn.get("animation_start_us")):
            markers += 1
            stable.extend((frame, budget) for frame, budget in current if frame["buildStart"] >= start)
        for name, value in turn.items():
            if name.endswith("_ms") and name not in ("wall_start_ms", "wall_end_ms") and _number(value):
                stages[name].append(value)
        accepted = turn.get("input_accepted_ms")
        if _number(accepted):
            for name in ("origin_feedback", "target_ready", "animation_first_frame", "landed"):
                value = turn.get(f"{name}_ms")
                if _number(value):
                    stages[f"accepted_to_{name}_ms"].append(value - accepted)
        for name, values in turn.get("trace_us", {}).items():
            traces[name].extend(value / 1000 for value in values if _number(value))
    return {
        "turn_count": len(samples),
        "rounds": sorted({turn["round"] for turn, _ in samples if "round" in turn}),
        "frame_timings_complete": all(turn.get("frames", {}).get("frame_timings_complete") is True
                                      and report.get("frame_timings_complete") is True
                                      for turn, report in samples),
        "all_frames": frame_summary(frames),
        "stable_animation_frames": frame_summary(stable),
        "animation_marker_count": markers,
        "stages": {name: distribution(values) for name, values in sorted(stages.items())},
        "trace_events": {name: distribution(values) for name, values in sorted(traces.items())},
        "snapshot_peak": _snapshot_peak([turn for turn, _ in samples]),
        **_scene_memory(samples),
    }


def _comparison(before, after, limit=None):
    known = before is not None and after is not None
    return {
        "baseline": before, "candidate": after,
        "change_ratio": (after / before - 1) if known and before else None,
        "within_limit": after <= limit if after is not None and limit is not None else None,
    }


def _threshold(value, limit, complete, missing=None):
    reason = missing or ("采样不完整" if not complete else None)
    if value is None or limit is None:
        reason = reason or "缺字段或空帧"
    return {"value": value, "limit": limit,
            "passed": value <= limit if reason is None else None, "reason": reason}


def performance_thresholds(group, mode, scene):
    group = group or {}
    complete = group.get("frame_timings_complete") is True
    interval = "all_frames" if mode == "scroll" else "stable_animation_frames"
    frames = group.get(interval, {})
    budgets = frames.get("frame_budgets_ms", [])
    budget = min(budgets, default=None)
    missing = "缺字段或空帧" if not frames.get("count") else None
    if mode != "scroll" and group.get("animation_marker_count", 0) != group.get("turn_count"):
        missing = "缺少动画开始标记"
    checks = {}
    for channel in ("ui", "raster"):
        stats = frames.get(channel, {})
        for metric, limit in (("p95_ms", budget), ("p99_ms", 16.67), ("over_budget_ratio", .05)):
            checks[f"{channel}.{metric}"] = _threshold(stats.get(metric), limit, complete, missing)
    stage = ("origin_feedback_ms", 100) if scene in ("open", "cross", "cold-cross") else (
        ("accepted_to_animation_first_frame_ms", 50) if scene == "continuous" else None)
    if stage:
        name, limit = stage
        stats = group.get("stages", {}).get(name, {})
        coverage = stats.get("count", 0) == group.get("turn_count")
        checks[f"stage.{name}.p95"] = _threshold(
            stats.get("p95_ms"), limit, complete, None if coverage else "阶段字段未覆盖全部样本")
    states = [check["passed"] for check in checks.values()]
    passed = False if False in states else None if None in states else True
    return {"frame_interval": interval, "passed": passed, "checks": checks}


def compare_reports(baseline, candidate, labels=None):
    left, right = aggregate(baseline), aggregate(candidate)
    labels = labels or {}
    exclusions = {"baseline": left["excluded_turn_count"], "candidate": right["excluded_turn_count"]}
    notes = [*NOTES, f"已剔除明确无效样本：基线 {exclusions['baseline']} 次，候选 {exclusions['candidate']} 次；整轮 PSS 仍含原报告全部采样，作废窗口无法从整轮峰值分离。"]
    result = {"schema": 2, "notes": notes, "excluded_turns": exclusions, "books": {}, "groups": []}
    for book in sorted(left["books"].keys() | right["books"].keys()):
        a, b = left["books"].get(book), right["books"].get(book)
        pss_a, pss_b = (a or {}).get("whole_report_pss_peak_bytes"), (b or {}).get("whole_report_pss_peak_bytes")
        limit = (a or {}).get("snapshot_peak")
        comparable = bool(a and b and a["workload"] == b["workload"] and a["workload"]
                          and len(a["reports"]) == len(b["reports"])
                          and not a["excluded_turn_count"] and not b["excluded_turn_count"])
        result["books"][book] = {
            "label": labels.get(book, book[:12]), "baseline": a, "candidate": b,
            "whole_report_pss_peak": {
                **_comparison(pss_a, pss_b, pss_a * 1.1 if comparable and pss_a is not None else None),
                "workload_comparable": comparable,
            },
            "snapshot_peak": _comparison(limit, (b or {}).get("snapshot_peak"), limit),
        }
    for book, mode, scene in sorted(left["groups"].keys() | right["groups"].keys()):
        key = book, mode, scene
        a, b = left["groups"].get(key), right["groups"].get(key)
        result["groups"].append({"book_sha256": book, "mode": mode, "scene": scene,
                                 "baseline": a, "candidate": b,
                                 "performance_thresholds": {
                                     "baseline": performance_thresholds(a, mode, scene),
                                     "candidate": performance_thresholds(b, mode, scene),
                                 },
                                 "observed_pss_peak": _comparison(
                                     (a or {}).get("observed_pss_peak_bytes"),
                                     (b or {}).get("observed_pss_peak_bytes"))})
    return result


def _value(value, percent=False):
    if value is None:
        return "—"
    return f"{value * 100:.2f}%" if percent else f"{value:.3f}"


def _pair(a, b, percent=False):
    return f"{_value(a, percent)} → {_value(b, percent)}"


def _threshold_markdown(groups):
    lines = ["性能阈值未达标／缺测（未列出的检查已通过）：", "",
             "| 模式／场景 | 版本 | 未达标或缺测项 |", "|---|---|---|"]
    for group in groups:
        for side, label in (("baseline", "基线"), ("candidate", "候选")):
            issues = []
            for metric, check in group["performance_thresholds"][side]["checks"].items():
                if check["passed"] is None:
                    issues.append(f"{metric} 缺测：{check['reason']}")
                elif check["passed"] is False:
                    percent = metric.endswith("over_budget_ratio")
                    issues.append(f"{metric} {_value(check['value'], percent)} > {_value(check['limit'], percent)}")
            if issues:
                lines.append(f"| {group['mode']}/{group['scene']} | {label} | {'；'.join(issues)} |")
    if len(lines) == 4:
        lines.append("| 全部已测分组 | 两版 | 无未达标项或缺测项 |")
    return [*lines, ""]


def render_markdown(result):
    lines = ["翻页性能对照（基线 → 候选，耗时单位 ms）", "", *[f"- {note}" for note in result["notes"]], ""]
    for book, summary in result["books"].items():
        pss, snapshots = summary["whole_report_pss_peak"], summary["snapshot_peak"]
        groups = [g for g in result["groups"] if g["book_sha256"] == book]
        rates = sorted({rate for group in groups for side in ("baseline", "candidate")
                        for rate in (group[side] or {}).get("all_frames", {}).get("refresh_rates_hz", [])})
        lines.extend([f"**{summary['label']}**（`{book[:12]}`）", "",
                      f"采样刷新率：{'、'.join(_value(rate) for rate in rates) or '未采到'} Hz。",
                      f"整轮 PSS 峰值：{_pair(pss['baseline'] / 1048576 if pss['baseline'] is not None else None, pss['candidate'] / 1048576 if pss['candidate'] is not None else None)} MiB；变化 {_value(pss['change_ratio'], True)}。",
                      f"整轮 PSS 不超过基线 110%：{_verdict(pss['within_limit']) if pss['workload_comparable'] else '不判断（模式／场景数量、报告数量不同或含作废样本）'}（不能代替场景内存验收）。",
                      f"快照观测峰值：{_pair(snapshots['baseline'], snapshots['candidate'])}；不超过基线上限：{_verdict(snapshots['within_limit'])}。", "",
                      "| 模式／场景 | 区间 | 帧数 | UI P50/P95/P99/最大 | Raster P50/P95/P99/最大 | UI/Raster 超预算率 |",
                      "|---|---|---|---|---|---|"])
        for group in groups:
            for key, label in (("all_frames", "全段"), ("stable_animation_frames", "稳定动画")):
                a, b = (group["baseline"] or {}).get(key, {}), (group["candidate"] or {}).get(key, {})
                cells = [f"{group['mode']}/{group['scene']}", label, _pair(a.get("count"), b.get("count"))]
                for channel in ("ui", "raster"):
                    cells.append(" / ".join(_pair(a.get(channel, {}).get(field), b.get(channel, {}).get(field))
                                            for field in ("p50_ms", "p95_ms", "p99_ms", "max_ms")))
                cells.append(" / ".join(_pair(a.get(c, {}).get("over_budget_ratio"), b.get(c, {}).get("over_budget_ratio"), True)
                                        for c in ("ui", "raster")))
                lines.append("| " + " | ".join(cells) + " |")
        lines.extend(["", "阶段摘要均从输入被接受起算；完整阶段及追踪事件的 P50/P95/P99/最大值见 JSON。", "",
                      "| 模式／场景 | 样本数 | 阶段 P95（基线 → 候选） |", "|---|---|---|"])
        for group in groups:
            a, b = group["baseline"] or {}, group["candidate"] or {}
            stages_a, stages_b = a.get("stages", {}), b.get("stages", {})
            stages = "；".join(f"{label}: {_pair(stages_a.get(name, {}).get('p95_ms'), stages_b.get(name, {}).get('p95_ms'))}"
                              for name, label in (("accepted_to_origin_feedback_ms", "原页反馈"),
                                                  ("accepted_to_target_ready_ms", "目标就绪"),
                                                  ("accepted_to_animation_first_frame_ms", "动画首帧"),
                                                  ("accepted_to_landed_ms", "落页"))
                              if name in stages_a or name in stages_b)
            complete = a.get("frame_timings_complete") and b.get("frame_timings_complete")
            lines.append(f"| {group['mode']}/{group['scene']}{'' if complete else '（缺报告或帧不完整）'} | "
                         f"{_pair(a.get('turn_count'), b.get('turn_count'))} | {stages or '—'} |")
        lines.append("")
        lines.extend(["| 模式／场景 | 观察 PSS 峰值 MiB | 命中内存样本数 | 有内存样本的翻页数／有效翻页数 |",
                      "|---|---|---|---|"])
        for group in groups:
            a, b = group["baseline"] or {}, group["candidate"] or {}
            peak_a, peak_b = a.get("observed_pss_peak_bytes"), b.get("observed_pss_peak_bytes")
            lines.append(f"| {group['mode']}/{group['scene']} | "
                         f"{_pair(peak_a / 1048576 if peak_a is not None else None, peak_b / 1048576 if peak_b is not None else None)} | "
                         f"{_pair(a.get('pss_sample_count'), b.get('pss_sample_count'))} | "
                         f"{a.get('pss_covered_turn_count', 0)}/{a.get('turn_count', 0)} → "
                         f"{b.get('pss_covered_turn_count', 0)}/{b.get('turn_count', 0)} |")
        lines.append("")
        lines.extend(_threshold_markdown(groups))
    return "\n".join(lines) + "\n"


def _verdict(value):
    return "未采到" if value is None else "是" if value else "否"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, nargs="+", required=True, help="一份或多份基线报告")
    parser.add_argument("--candidate", type=Path, nargs="+", required=True, help="一份或多份候选报告")
    parser.add_argument("--output-dir", type=Path, required=True, help="输出目录，建议使用已忽略的 dist 目录")
    parser.add_argument("--book-label", action="append", default=[], metavar="SHA256=书名")
    args = parser.parse_args(argv)
    labels = {}
    for label in args.book_label:
        key, separator, name = label.partition("=")
        if not separator or not key or not name:
            parser.error("--book-label 需要 SHA256=书名")
        labels[key] = name
    def load(paths):
        return [{**json.loads(path.read_text(encoding="utf-8")), "_path": str(path)} for path in paths]
    result = compare_reports(load(args.baseline), load(args.candidate), labels)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "comparison.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (args.output_dir / "comparison.md").write_text(render_markdown(result), encoding="utf-8")
    print(f"已写入 {args.output_dir / 'comparison.md'} 和 comparison.json")


if __name__ == "__main__":
    main()
