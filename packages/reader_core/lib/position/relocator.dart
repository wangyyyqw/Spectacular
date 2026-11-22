/// 位置重定位的三级兜底（P7-14，技术方案 §30.4）。
///
/// 顺序：**区间直查**（CFI/偏移仍有效时零成本命中）→ **原文 + 上下文
/// 指纹**（quote 命中；多命中先用前后文指纹消歧，指纹不分胜负按 §30.4
/// 取离原位置最近，候选随结果返回供人工消歧）→ **章内比例兜底**
/// （低置信落点）。三级全失败返回失败分类，由调用方置灰保留——
/// 不删除失效标注。
library;

import 'dart:math' as math;

/// 命中级别（置信度从高到低）。
enum RelocateLevel { direct, fingerprint, fraction }

/// 失败分类（对齐 §30.4；诊断码 `E_ANNOTATION_RELOCATE_FAILED`）。
enum RelocateFailure { quoteNotFound, noAnchor }

/// 重定位请求。
class RelocateRequest {
  /// 创建请求。
  const RelocateRequest({
    required this.quote,
    this.contextBefore,
    this.contextAfter,
    this.directOffset,
    this.chapterFraction,
    this.searchFrom = 0,
  });

  /// 原文快照（标注时的选区文本）。
  final String quote;

  /// 前约 20 字上下文（消歧指纹）。
  final String? contextBefore;

  /// 后约 20 字上下文（消歧指纹）。
  final String? contextAfter;

  /// 一级：仍有效的字符偏移（区间直查）；越界或缺失走二级。
  final int? directOffset;

  /// 三级：章内比例（0..1，进度兜底）。
  final double? chapterFraction;

  /// 原位置附近的搜索起点（多命中时取离原位置最近）。
  final int searchFrom;
}

/// 重定位结果。
class RelocateResult {
  /// 命中结果。
  const RelocateResult.hit({
    required this.offset,
    required this.level,
    this.candidates = const <int>[],
  }) : failure = null;

  /// 失败结果（三级全败；无可用锚点）。
  const RelocateResult.failed({required this.failure})
    : offset = -1,
      level = null,
      candidates = const <int>[];

  /// 命中偏移（章内 UTF-16 偏移）；失败为 -1。
  final int offset;

  /// 命中级别；失败为 null。
  final RelocateLevel? level;

  /// 失败分类；命中为 null。
  final RelocateFailure? failure;

  /// 多命中时的全部候选偏移（按文档顺序，供人工消歧 UI）。
  final List<int> candidates;

  /// 是否命中。
  bool get isHit => failure == null && offset >= 0;
}

/// 标注重定位器：三级解析的纯文本实现（不依赖文档树，任何章文本
/// 均可重放，便于测试与 P4 存储层复用）。
abstract final class AnnotationRelocator {
  /// 执行三级解析。
  static RelocateResult relocate(
    RelocateRequest request, {
    required String chapterText,
  }) {
    // 一级：区间直查（CFI 仍有效时的零成本路径）。
    final direct = request.directOffset;
    if (direct != null && direct >= 0 && direct <= chapterText.length) {
      return RelocateResult.hit(offset: direct, level: RelocateLevel.direct);
    }

    // 二级：quote 搜索 + 指纹消歧。
    final quote = request.quote;
    if (quote.isNotEmpty) {
      final hits = _allOccurrences(chapterText, quote);
      if (hits.length == 1) {
        return RelocateResult.hit(
          offset: hits.single,
          level: RelocateLevel.fingerprint,
        );
      }
      if (hits.length > 1) {
        // 指纹严格领先者胜出；否则按 §30.4 取离原位置最近。
        final best =
            _disambiguate(chapterText, hits, request) ??
            _nearestTo(hits, request.searchFrom);
        return RelocateResult.hit(
          offset: best,
          level: RelocateLevel.fingerprint,
          candidates: hits,
        );
      }
      // quote 未命中：继续三级比例兜底。
      final fractionHit = _fractionHit(request, chapterText);
      if (fractionHit != null) {
        return fractionHit;
      }
      return const RelocateResult.failed(
        failure: RelocateFailure.quoteNotFound,
      );
    }

    // 三级：比例兜底。
    return _fractionHit(request, chapterText) ??
        const RelocateResult.failed(failure: RelocateFailure.noAnchor);
  }

  static List<int> _allOccurrences(String text, String needle) {
    final result = <int>[];
    if (needle.isEmpty || needle.length > text.length) {
      return result;
    }
    var start = 0;
    while (true) {
      final index = text.indexOf(needle, start);
      if (index < 0) {
        return result;
      }
      result.add(index);
      start = index + 1;
    }
  }

  /// 指纹消歧：命中窗口与前后文比对打分，**严格领先**的唯一命中胜出；
  /// 平分或零分返回 null（调用方按最近原则兜底）。
  static int? _disambiguate(
    String text,
    List<int> hits,
    RelocateRequest request,
  ) {
    final before = request.contextBefore;
    final after = request.contextAfter;
    if (before == null && after == null) {
      return null;
    }
    final scores = <int>[];
    for (final hit in hits) {
      var score = 0;
      if (before != null && before.isNotEmpty) {
        final window = text.substring(
          math.max(0, hit - before.length),
          hit,
        );
        if (window == before) {
          score += 2;
        } else if (window.contains(before)) {
          score += 1;
        }
      }
      if (after != null && after.isNotEmpty) {
        final windowEnd = math.min(
          text.length,
          hit + request.quote.length + after.length,
        );
        final window = text.substring(hit + request.quote.length, windowEnd);
        if (window == after) {
          score += 2;
        } else if (window.contains(after)) {
          score += 1;
        }
      }
      scores.add(score);
    }
    final best = scores.reduce(math.max);
    if (best == 0) {
      return null;
    }
    final leaders = <int>[
      for (var i = 0; i < hits.length; i++)
        if (scores[i] == best) hits[i],
    ];
    return leaders.length == 1 ? leaders.single : null;
  }

  static RelocateResult? _fractionHit(
    RelocateRequest request,
    String chapterText,
  ) {
    final fraction = request.chapterFraction;
    if (fraction == null || fraction.isNaN || chapterText.isEmpty) {
      return null;
    }
    final clamped = fraction.clamp(0.0, 1.0);
    return RelocateResult.hit(
      offset: (clamped * chapterText.length).round(),
      level: RelocateLevel.fraction,
    );
  }

  static int _nearestTo(List<int> offsets, int target) {
    var best = offsets.first;
    var bestDistance = (best - target).abs();
    for (final offset in offsets.skip(1)) {
      final distance = (offset - target).abs();
      if (distance < bestDistance) {
        best = offset;
        bestDistance = distance;
      }
    }
    return best;
  }
}
