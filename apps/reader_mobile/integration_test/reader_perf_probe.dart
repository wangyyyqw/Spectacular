import 'dart:ui' show FramePhase, FrameTiming;

/// 回调仅收集原始时间；结束或显式 flush 后结算，延迟批次仍归属原窗口。
class ReaderPerfProbeSamples {
  final List<_ProbeWindow> _windows = [];
  _ProbeWindow? _current;
  int? _latestBuildStart;

  bool get complete =>
      _current == null && _windows.every((window) => window.complete);

  /// 与 FrameTiming 使用同一单调时钟；刷新率取当前阅读视口的 display。
  void start(int rawFrameTimestampMicros, {double refreshRate = 60}) {
    if (_current != null) throw StateError('上一个采样事件尚未结束');
    final window = _ProbeWindow(rawFrameTimestampMicros, refreshRate);
    _windows.add(window);
    _current = window;
  }

  void tick(int elapsedMicros) => _active.tick(elapsedMicros);

  /// 保留可变结果引用，采样结束后 flush 可补齐迟到的原生批次。
  Map<String, Object> finish({
    required int elapsedMicros,
    required int rawFrameTimestampMicros,
  }) {
    final window = _active;
    if (window._lastTick > 0) window.tick(elapsedMicros);
    window.end = rawFrameTimestampMicros;
    _current = null;
    window.updateCompletion(_latestBuildStart);
    window.summarize();
    return window.result;
  }

  void addFrames(List<FrameTiming> frames) {
    for (final frame in frames) {
      final buildStart = frame.timestampInMicroseconds(FramePhase.buildStart);
      final latest = _latestBuildStart;
      if (latest == null || buildStart > latest) _latestBuildStart = buildStart;
      for (final window in _windows) {
        if (window.contains(buildStart)) window.frames.add(frame);
      }
    }
    for (final window in _windows) {
      window.updateCompletion(_latestBuildStart);
    }
  }

  /// 不在帧回调或动画中调用；仅结算已结束的窗口。
  void flush() {
    for (final window in _windows) {
      if (window.end != null) window.summarize();
    }
  }

  _ProbeWindow get _active => _current ?? (throw StateError('尚未开始采样事件'));
}

class _ProbeWindow {
  _ProbeWindow(this.start, this.refreshRate);

  final int start;
  final double refreshRate;
  int? end;
  int _lastTick = 0;
  int _maximumGap = 0;
  final List<FrameTiming> frames = [];
  bool complete = false;
  int _summarized = -1;
  final Map<String, Object> result = {};

  bool contains(int buildStart) =>
      buildStart > start && (end == null || buildStart <= end!);

  void tick(int elapsedMicros) {
    final gap = elapsedMicros - _lastTick;
    if (gap > _maximumGap) _maximumGap = gap;
    _lastTick = elapsedMicros;
  }

  void updateCompletion(int? latestBuildStart) {
    complete =
        end != null &&
        frames.isNotEmpty &&
        latestBuildStart != null &&
        latestBuildStart >= end!;
  }

  void summarize() {
    result['frame_timings_complete'] = complete;
    if (_summarized == frames.length) return;
    _summarized = frames.length;
    final builds = frames.map((f) => f.buildDuration.inMicroseconds).toList()
      ..sort();
    final rasters = frames.map((f) => f.rasterDuration.inMicroseconds).toList()
      ..sort();
    final budget = 1000000 / refreshRate;
    double percentile(List<int> values, double p) =>
        values.isEmpty ? 0 : values[(values.length * p).ceil() - 1] / 1000;
    result.addAll({
      'longest_ui_gap_ms': _maximumGap / 1000,
      'ui_gap_sampled': _lastTick > 0,
      'longest_build_ms': percentile(builds, 1),
      'longest_raster_ms': percentile(rasters, 1),
      'frame_count': frames.length,
      'refresh_rate': refreshRate,
      'frame_budget_ms': budget / 1000,
      'frames_over_16_67_ms': rasters.where((v) => v > 16667).length,
      'raw_frames': [
        for (final frame in frames)
          {
            for (final phase in FramePhase.values)
              phase.name: frame.timestampInMicroseconds(phase),
            'build_us': frame.buildDuration.inMicroseconds,
            'raster_us': frame.rasterDuration.inMicroseconds,
          },
      ],
      for (final entry in {'build': builds, 'raster': rasters}.entries) ...{
        for (final p in [50, 95, 99])
          '${entry.key}_p${p}_ms': percentile(entry.value, p / 100),
        '${entry.key}_over_budget': entry.value.where((v) => v > budget).length,
        '${entry.key}_over_budget_ratio': entry.value.isEmpty
            ? 0.0
            : entry.value.where((v) => v > budget).length / entry.value.length,
      },
    });
  }
}
