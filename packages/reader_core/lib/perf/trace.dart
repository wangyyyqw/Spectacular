import 'package:flutter/foundation.dart';

/// 埋点类别（P4-31，技术方案 §44.2）。
enum ReaderTraceName {
  /// 打开书到首屏可读。
  bookOpen,

  /// 分页一章。
  chapterLayout,

  /// 解析章节树与构建选择器索引。
  chapterStructure,

  /// 加载并准备章节样式与内嵌字体。
  chapterStyles,

  /// 聚合章节 DOM 文本与行内标记。
  chapterAggregate,

  /// 聚合章节内容并生成排版块。
  chapterCollect,

  /// 测量并生成章节表格。
  chapterTables,

  /// 对章节块执行分页。
  chapterPagination,

  /// 构建页渲染缓存。
  pageRenderBuild,

  /// 翻页命中缓存。
  pageRenderReuse,

  /// 目录跳转。
  chapterJump,

  /// 设置变更后重排。
  relayout,

  /// 导入。
  import,

  /// 字体加载。
  fontLoad,

  /// 图片解码。
  imageDecode,
}

/// 一次耗时埋点。
class ReaderTraceEvent {
  /// 创建事件。
  const ReaderTraceEvent({
    required this.name,
    required this.bookId,
    required this.microseconds,
    required this.at,
  });

  /// 类别。
  final ReaderTraceName name;

  /// 书籍标识（可为 null）。
  final String? bookId;

  /// 耗时（微秒）。
  final int microseconds;

  /// 记录时间。
  final DateTime at;

  /// 耗时（毫秒）。
  double get milliseconds => microseconds / 1000;
}

/// 命中率计数器（§44.3 的三类比率）。
enum ReaderTraceCounter {
  /// 页缓存命中。
  pageCacheHit,

  /// 页缓存未命中。
  pageCacheMiss,
}

/// 按书聚合的埋点摘要。
class ReaderTraceSummary {
  /// 创建摘要。
  const ReaderTraceSummary({
    required this.bookId,
    required this.counts,
    required this.totalMicroseconds,
    required this.maxMicroseconds,
    required this.samples,
  });

  /// 书籍标识。
  final String? bookId;

  /// 各类别次数。
  final Map<ReaderTraceName, int> counts;

  /// 各类别总耗时（微秒）。
  final Map<ReaderTraceName, int> totalMicroseconds;

  /// 各类别最大耗时（微秒）。
  final Map<ReaderTraceName, int> maxMicroseconds;

  /// 各类别的采样序列（用于分位）。
  final Map<ReaderTraceName, List<int>> samples;

  /// 某类别的平均耗时（毫秒），无采样返回 0。
  double averageMs(ReaderTraceName name) {
    final total = totalMicroseconds[name] ?? 0;
    final count = counts[name] ?? 0;
    return count == 0 ? 0 : total / count / 1000;
  }

  /// 某类别的最大耗时（毫秒）。
  double maxMs(ReaderTraceName name) => (maxMicroseconds[name] ?? 0) / 1000;

  /// 某类别的 P95（毫秒），无采样返回 0。
  double p95Ms(ReaderTraceName name) {
    final values = samples[name];
    if (values == null || values.isEmpty) {
      return 0;
    }
    final sorted = List<int>.of(values)..sort();
    final index = ((sorted.length - 1) * 0.95).round();
    return sorted[index] / 1000;
  }

  /// 页缓存命中率（0..1），没有访问时返回 0。
  double get pageCacheHitRate {
    final hit = counts[ReaderTraceName.pageRenderReuse] ?? 0;
    final miss = counts[ReaderTraceName.chapterLayout] ?? 0;
    final total = hit + miss;
    return total == 0 ? 0 : hit / total;
  }
}

/// 轻量埋点收集器（P4-31）。
///
/// 只在内存里留固定条数的样本：单次记录只有一次 Stopwatch 读取与一次列表
/// 追加，实测远低于 1ms；写盘/上报由调用方按需另做（P7-10 阈值表）。
class ReaderTrace {
  /// 创建收集器。
  ReaderTrace({this.capacity = 512});

  /// 全局实例（可在测试里替换）。
  static ReaderTrace instance = ReaderTrace();

  /// 每类事件最多保留的采样数。
  final int capacity;

  final Map<String?, ReaderTraceSummary> _summaries =
      <String?, ReaderTraceSummary>{};
  final Map<String?, Map<ReaderTraceCounter, int>> _counters =
      <String?, Map<ReaderTraceCounter, int>>{};
  final Map<String?, Map<ReaderTraceName, List<int>>> _samples =
      <String?, Map<ReaderTraceName, List<int>>>{};

  /// 开始计时；配合 [stop] 记录一次耗时。
  ReaderTraceHandle start(ReaderTraceName name, {String? bookId}) =>
      ReaderTraceHandle._(this, name, bookId, Stopwatch()..start());

  /// 记录一次已测量的耗时（微秒）。
  void record(ReaderTraceName name, int microseconds, {String? bookId}) {
    final samples = _samples.putIfAbsent(
      bookId,
      () => <ReaderTraceName, List<int>>{},
    );
    final list = samples.putIfAbsent(name, () => <int>[]);
    if (list.length >= capacity) {
      list.removeAt(0);
    }
    list.add(microseconds);
    _summaries.remove(bookId);
  }

  /// 计数（命中率用）。
  void count(ReaderTraceCounter counter, {String? bookId, int delta = 1}) {
    final counters = _counters.putIfAbsent(
      bookId,
      () => <ReaderTraceCounter, int>{},
    );
    counters[counter] = (counters[counter] ?? 0) + delta;
    _summaries.remove(bookId);
  }

  /// 某本书（或全部）的聚合摘要。
  ReaderTraceSummary summary({String? bookId}) {
    final cached = _summaries[bookId];
    if (cached != null) {
      return cached;
    }
    final samples = _samples[bookId] ?? <ReaderTraceName, List<int>>{};
    final counts = <ReaderTraceName, int>{};
    final totals = <ReaderTraceName, int>{};
    final maxes = <ReaderTraceName, int>{};
    for (final entry in samples.entries) {
      final values = entry.value;
      counts[entry.key] = values.length;
      totals[entry.key] = values.fold<int>(0, (sum, value) => sum + value);
      maxes[entry.key] = values.fold<int>(
        0,
        (max, value) => value > max ? value : max,
      );
    }
    // §44.3：缓存命中按 pageRenderReuse 计，未命中按分页次数计。
    final counters = _counters[bookId];
    if (counters != null) {
      final hit = counters[ReaderTraceCounter.pageCacheHit] ?? 0;
      if (hit > 0) {
        counts[ReaderTraceName.pageRenderReuse] =
            (counts[ReaderTraceName.pageRenderReuse] ?? 0) + hit;
      }
    }
    final summary = ReaderTraceSummary(
      bookId: bookId,
      counts: counts,
      totalMicroseconds: totals,
      maxMicroseconds: maxes,
      samples: <ReaderTraceName, List<int>>{
        for (final entry in samples.entries)
          entry.key: List<int>.of(entry.value),
      },
    );
    _summaries[bookId] = summary;
    return summary;
  }

  /// 清空（测试与「重开书」用）。
  void reset() {
    _summaries.clear();
    _counters.clear();
    _samples.clear();
  }
}

/// 计时句柄：stop() 时记录一次耗时。
class ReaderTraceHandle {
  ReaderTraceHandle._(this._trace, this.name, this.bookId, this._watch);

  final ReaderTrace _trace;

  /// 类别。
  final ReaderTraceName name;

  /// 书籍标识。
  final String? bookId;

  final Stopwatch _watch;
  bool _stopped = false;

  /// 结束计时并记录。
  void stop() {
    if (_stopped) {
      return;
    }
    _stopped = true;
    _watch.stop();
    _trace.record(name, _watch.elapsedMicroseconds, bookId: bookId);
  }

  /// 当前已耗时（微秒），不结束计时。
  int get elapsedMicroseconds => _watch.elapsedMicroseconds;
}

/// 调试开关：默认只在 debug/profile 记录，release 不收集（§44.2）。
bool get readerTraceEnabled => kDebugMode || kProfileMode;
