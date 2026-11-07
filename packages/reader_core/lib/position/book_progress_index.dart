/// 全书比例对应的原文章节位置，与分页结果和字号无关。
class BookProgressLocation {
  const BookProgressLocation({
    required this.spineIndex,
    required this.chapterRatio,
  });

  final int spineIndex;
  final double chapterRatio;
}

/// 轻量阅读进度索引：章节未压缩字节权重 × 章内原文位置比例。
///
/// 本索引不持有章节原文或归档。调用方仅需准备目标章的原文坐标，
/// 百分比显示、跳转与存储共用同一套算法，字号变化不改变同一 CFI 的比例。
class BookProgressIndex {
  BookProgressIndex._(List<int> weights, Set<int> excluded, this.estimated)
    : chapterWeights = List<int>.unmodifiable(weights),
      chapterStarts = List<int>.unmodifiable(_prefixSums(weights)),
      excluded = Set<int>.unmodifiable(excluded),
      totalWeight = weights.fold<int>(0, (sum, weight) => sum + weight),
      _readableSpines = List<int>.unmodifiable([
        for (var spine = 0; spine < weights.length; spine++)
          if (weights[spine] > 0) spine,
      ]);

  /// 进度算法版本独立于 CFI 和原文锚点语义版本。
  static const int algorithmVersion = 1;

  /// 从归档条目大小建立权重；排除目录、非正文和确认缺失的章节。
  ///
  /// 可读章存在未知或非法大小时，整本按可读章等权降级，避免混用
  /// 字节数与单位权重。已知空条目不占权重；全部为空时仍按可读章等权。
  factory BookProgressIndex.fromUncompressedSizes(
    List<int?> sizes, {
    Set<int> excluded = const <int>{},
  }) {
    final omitted = <int>{
      for (final spine in excluded)
        if (spine >= 0 && spine < sizes.length) spine,
    };
    final unknown = sizes.indexed.any(
      (entry) =>
          !omitted.contains(entry.$1) && (entry.$2 == null || entry.$2! < 0),
    );
    final weights = <int>[
      for (var spine = 0; spine < sizes.length; spine++)
        omitted.contains(spine) ? 0 : (sizes[spine] ?? 0),
    ];
    final estimated = unknown || weights.every((weight) => weight == 0);
    return BookProgressIndex._(
      estimated
          ? [
              for (var spine = 0; spine < sizes.length; spine++)
                omitted.contains(spine) ? 0 : 1,
            ]
          : weights,
      omitted,
      estimated,
    );
  }

  /// 每章的进度权重；不写入书库的字数统计字段。
  final List<int> chapterWeights;

  /// 各章之前的累计权重。
  final List<int> chapterStarts;

  final int totalWeight;
  final Set<int> excluded;

  /// 是否因条目大小不可用而使用等权估算。
  final bool estimated;
  final List<int> _readableSpines;

  int get chapterCount => chapterWeights.length;

  bool includes(int spineIndex) =>
      spineIndex >= 0 &&
      spineIndex < chapterCount &&
      chapterWeights[spineIndex] > 0;

  /// 全书比例 0～1；[chapterRatio] 由该章原文 CFI 偏移和长度提供。
  ///
  /// 排除章停留在章前累计比例，越界位置安全钳制到书首或书尾。
  double percentOf(int spineIndex, double chapterRatio) {
    if (totalWeight <= 0 || spineIndex < 0) return 0;
    if (spineIndex >= chapterCount) return 1;
    return ((chapterStarts[spineIndex] +
                chapterWeights[spineIndex] * _unitRatio(chapterRatio)) /
            totalWeight)
        .clamp(0.0, 1.0);
  }

  /// 先按权重定位目标章，调用方再异步准备该章原文索引。
  ///
  /// 精确章边界指向下一可读章的章首；100% 指向最后可读章的章尾。
  /// 空书或全部章节被排除时返回 null。使用二分查找，不遍历章节内容。
  BookProgressLocation? locate(double percent) {
    if (totalWeight <= 0) return null;
    final target = _unitRatio(percent) * totalWeight;
    if (target >= totalWeight) {
      return BookProgressLocation(
        spineIndex: _readableSpines.last,
        chapterRatio: 1,
      );
    }
    var lower = 0;
    var upper = _readableSpines.length - 1;
    while (lower < upper) {
      final middle = (lower + upper) ~/ 2;
      final spine = _readableSpines[middle];
      final end = chapterStarts[spine] + chapterWeights[spine];
      if (target >= end) {
        lower = middle + 1;
      } else {
        upper = middle;
      }
    }
    final spine = _readableSpines[lower];
    return BookProgressLocation(
      spineIndex: spine,
      chapterRatio: ((target - chapterStarts[spine]) / chapterWeights[spine])
          .clamp(0.0, 1.0),
    );
  }

  static List<int> _prefixSums(List<int> weights) {
    final starts = <int>[];
    var total = 0;
    for (final weight in weights) {
      starts.add(total);
      total += weight;
    }
    return starts;
  }

  static double _unitRatio(double value) =>
      value.isNaN ? 0 : value.clamp(0.0, 1.0);
}
