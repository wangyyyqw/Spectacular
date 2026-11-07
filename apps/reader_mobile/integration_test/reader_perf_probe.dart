import 'dart:ui' show FramePhase, FrameTiming;

/// 按原始帧时间归属事件；结束后的结果仍可由延迟帧批次补齐。
class ReaderPerfProbeSamples {
  final List<_ProbeWindow> _windows = [];
  _ProbeWindow? _current;
  int? _latestBuildStart;

  bool get complete =>
      _current == null && _windows.every((window) => window.complete);

  /// 时间须来自 Timeline.now，与原生 FrameTiming 使用同一单调时钟。
  void start(int rawFrameTimestampMicros) {
    if (_current != null) throw StateError('上一个采样事件尚未结束');
    final window = _ProbeWindow(rawFrameTimestampMicros);
    _windows.add(window);
    _current = window;
  }

  void tick(int elapsedMicros) => _active.tick(elapsedMicros);

  /// 返回原始可变结果，调用者须保留引用以接收延迟帧更新。
  Map<String, Object> finish({
    required int elapsedMicros,
    required int rawFrameTimestampMicros,
  }) {
    final window = _active;
    window.tick(elapsedMicros);
    window.end = rawFrameTimestampMicros;
    _current = null;
    window.updateCompletion(_latestBuildStart);
    return window.result;
  }

  void addFrames(List<FrameTiming> frames) {
    for (final frame in frames) {
      final buildStart = frame.timestampInMicroseconds(FramePhase.buildStart);
      final latest = _latestBuildStart;
      if (latest == null || buildStart > latest) _latestBuildStart = buildStart;
      for (final window in _windows) {
        if (window.contains(buildStart)) window.addFrame(frame);
      }
    }
    for (final window in _windows) {
      window.updateCompletion(_latestBuildStart);
    }
  }

  _ProbeWindow get _active => _current ?? (throw StateError('尚未开始采样事件'));
}

class _ProbeWindow {
  _ProbeWindow(this.start);

  final int start;
  int? end;
  int _lastTick = 0;
  int _maximumGap = 0;
  int _maximumBuild = 0;
  int _maximumRaster = 0;
  int _frameCount = 0;
  final Map<String, Object> result = {
    'longest_ui_gap_ms': 0.0,
    'longest_build_ms': 0.0,
    'longest_raster_ms': 0.0,
    'frame_count': 0,
    'frame_timings_complete': false,
  };

  bool get complete => result['frame_timings_complete'] == true;

  bool contains(int buildStart) =>
      buildStart > start && (end == null || buildStart <= end!);

  void tick(int elapsedMicros) {
    final gap = elapsedMicros - _lastTick;
    if (gap > _maximumGap) _maximumGap = gap;
    _lastTick = elapsedMicros;
    result['longest_ui_gap_ms'] = _maximumGap / 1000;
  }

  void addFrame(FrameTiming frame) {
    final build = frame.buildDuration.inMicroseconds;
    final raster = frame.rasterDuration.inMicroseconds;
    if (build > _maximumBuild) _maximumBuild = build;
    if (raster > _maximumRaster) _maximumRaster = raster;
    result['longest_build_ms'] = _maximumBuild / 1000;
    result['longest_raster_ms'] = _maximumRaster / 1000;
    result['frame_count'] = ++_frameCount;
  }

  void updateCompletion(int? latestBuildStart) {
    final endFrame = end;
    result['frame_timings_complete'] =
        endFrame != null &&
        _frameCount > 0 &&
        latestBuildStart != null &&
        latestBuildStart >= endFrame;
  }
}
