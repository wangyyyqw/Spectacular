import 'dart:math' as math;

/// 阅读进度权重表（技术方案 §76.1/§76.2）。
///
/// 进度 = (章前累计字符 + 章内已读字符) / 全书正文字符总数。字符数在导入期
/// 统计并落库（`spine_items.char_count` / `char_start`），这里只做纯计算：
/// 与分页、字号、封面大小都无关，重排后同一位置百分比不变。
class ProgressWeights {
  /// 创建权重表。
  const ProgressWeights({
    required this.charCounts,
    required this.charStarts,
    required this.total,
    this.excluded = const <int>{},
    this.estimated = false,
  });

  /// 按每章字符数构建权重表。
  ///
  /// [excluded] 里的 spine 索引不参与进度（封面页、后壳页、`linear="no"`、
  /// nav 目录页，§76.2）；0 字符的章自动排除。全部章都被排除时退回「按章
  /// 等权」估算并把 [estimated] 置为 true，避免进度恒为 0。
  factory ProgressWeights.fromCharCounts(
    List<int> charCounts, {
    Set<int> excluded = const <int>{},
  }) {
    final counts = <int>[
      for (final count in charCounts) math.max(0, count),
    ];
    final starts = List<int>.filled(counts.length, 0);
    var total = 0;
    for (var index = 0; index < counts.length; index++) {
      starts[index] = total;
      if (!excluded.contains(index)) {
        total += counts[index];
      }
    }
    if (total == 0 && counts.isNotEmpty) {
      // 没有字符统计（旧书未统计）：按章等权估算，保证进度可用。
      return ProgressWeights(
        charCounts: List<int>.filled(counts.length, 1),
        charStarts: List<int>.generate(counts.length, (index) => index),
        total: counts.length,
        excluded: excluded,
        estimated: true,
      );
    }
    return ProgressWeights(
      charCounts: counts,
      charStarts: starts,
      total: total,
      excluded: excluded,
    );
  }

  /// 每章正文字符数（被排除的章为 0）。
  final List<int> charCounts;

  /// 每章在全书中的字符起点。
  final List<int> charStarts;

  /// 全书正文字符总数。
  final int total;

  /// 不参与进度的 spine 索引。
  final Set<int> excluded;

  /// 是否因缺少字符统计而按章等权估算。
  final bool estimated;

  /// 章数。
  int get chapterCount => charCounts.length;

  /// 该 spine 是否计入进度。
  bool includes(int spineIndex) =>
      spineIndex >= 0 &&
      spineIndex < charCounts.length &&
      !excluded.contains(spineIndex) &&
      charCounts[spineIndex] > 0;

  /// 某位置的进度比例 0～1。
  ///
  /// [charOffsetInChapter] 是章内已读字符（排版时累计）；超出本章字符数时
  /// 按章内 100% 计，避免负数或越界把进度算过 1。
  double percentOf(int spineIndex, {double charOffsetInChapter = 0}) {
    if (total <= 0 || spineIndex < 0) {
      return 0;
    }
    if (spineIndex >= charCounts.length) {
      return 1;
    }
    final chapterLength = charCounts[spineIndex];
    if (chapterLength <= 0 || excluded.contains(spineIndex)) {
      // 被排除的章：进度落在章首（按下一个计入的章算）。
      return (charStarts[spineIndex] / total).clamp(0.0, 1.0);
    }
    final read = charOffsetInChapter.clamp(0.0, chapterLength.toDouble());
    final percent = (charStarts[spineIndex] + read) / total;
    return percent.clamp(0.0, 1.0);
  }

  /// 百分比整数 0～100（§76.3：只显示整数，存储保留小数）。
  int percentInt(int spineIndex, {double charOffsetInChapter = 0}) =>
      (percentOf(spineIndex, charOffsetInChapter: charOffsetInChapter) * 100)
          .round()
          .clamp(0, 100);

  /// 万分比 0～10000（对齐 Reeden 的 read_progress 口径，便于外部系统对齐）。
  int percentOf10000(int spineIndex, {double charOffsetInChapter = 0}) =>
      (percentOf(spineIndex, charOffsetInChapter: charOffsetInChapter) * 10000)
          .round()
          .clamp(0, 10000);

  /// 全书总字数（含被排除章，书库卡片展示用，§76.2）。
  ///
  /// 估算模式（[estimated]）下没有真实统计，返回计入进度的总量。
  int get totalCharacters =>
      estimated ? total : charCounts.fold<int>(0, (sum, value) => sum + value);
}
