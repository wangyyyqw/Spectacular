import 'dart:math' as math;

import '../text/text_offsets.dart';
import 'cfi.dart';

/// 一段显示文字与原始字符块之间的 UTF-16 坐标关系。
///
/// 折叠空白可把多个源字符映射到一个显示字符；元素占位没有字符偏移。
class TextCfiRun {
  const TextCfiRun({
    required this.start,
    required this.end,
    required this.cfi,
    required this.sourceStart,
    required this.sourceEnd,
  });

  final int start;
  final int end;
  final EpubCfi cfi;
  final int sourceStart;
  final int sourceEnd;

  bool get _isElement => cfi.segments.last.steps.last.index.isEven;
  bool get _linear => !_isElement && end - start == sourceEnd - sourceStart;

  int sourceOffset(int offset, {bool endPoint = false}) {
    if (offset <= start || end <= start) return sourceStart;
    if (offset >= end) return sourceEnd;
    final delta = (offset - start) * (sourceEnd - sourceStart) / (end - start);
    return sourceStart + (endPoint ? delta.ceil() : delta.floor());
  }

  EpubCfi pointAt(int offset, {bool endPoint = false}) => _isElement
      ? cfi
      : cfi.withCharOffset(sourceOffset(offset, endPoint: endPoint));

  int? offsetFor(EpubCfi point, {bool endPoint = false}) {
    final offset = point.charOffset ?? 0;
    if (_elementPoint(point) && _hasAncestor(cfi, point)) {
      return endPoint ? end : start;
    }
    if (!_samePath(cfi, point)) return null;
    if (_isElement) return offset == 0 ? (endPoint ? end : start) : null;
    if (offset < sourceStart || offset > sourceEnd) return null;
    if (offset == sourceStart) return start;
    if (offset == sourceEnd) return end;
    if (_linear) return start + offset - sourceStart;
    return endPoint ? end : start;
  }
}

/// 聚合、分页和选区共用的显示偏移与标准 CFI 双向映射。
class TextCfiMap {
  const TextCfiMap({
    required this.runs,
    required this.textLength,
    this.parent,
    this.originStart = 0,
  });

  /// 调用方直接构造的单字符块仍可使用线性坐标。
  factory TextCfiMap.linear(EpubCfi cfi, int length) => TextCfiMap(
    textLength: length,
    runs: [
      TextCfiRun(
        start: 0,
        end: length,
        cfi: cfi,
        sourceStart: cfi.charOffset ?? 0,
        sourceEnd: cfi.segments.last.steps.last.index.isEven
            ? 0
            : (cfi.charOffset ?? 0) + length,
      ),
    ],
  );

  final List<TextCfiRun> runs;
  final int textLength;
  final TextCfiMap? parent;
  final int originStart;
  TextCfiMap get origin => parent ?? this;

  /// 同一原段切片之间的显示位置；手工单字符块按真实源偏移比较。
  int? offsetFrom(TextCfiMap other) {
    if (identical(origin, other.origin)) return originStart - other.originStart;
    if (runs.length != 1 || other.runs.length != 1) return null;
    final first = runs.single;
    final second = other.runs.single;
    return first._linear && second._linear && _samePath(first.cfi, second.cfi)
        ? first.sourceStart - second.sourceStart
        : null;
  }

  /// 起点偏向下一来源字符，终点偏向上一来源字符。
  String? cfiAt(int offset, {bool end = false}) {
    if (offset < 0 || offset > textLength || runs.isEmpty) return null;
    if (end) {
      for (final run in runs.reversed) {
        if (offset > run.start && offset <= run.end) {
          return run.pointAt(offset, endPoint: true).serialize();
        }
      }
    } else {
      for (final run in runs) {
        if (offset >= run.start && offset < run.end) {
          return run.pointAt(offset).serialize();
        }
      }
    }
    // 伪内容没有 XML 字符位置，定位到相邻实际来源的边界。
    final before = runs.where((run) => run.end <= offset).lastOrNull;
    final after = runs.where((run) => run.start >= offset).firstOrNull;
    final nearest = end ? before ?? after : after ?? before;
    if (nearest == null) return null;
    final atEnd = identical(nearest, before);
    return nearest.pointAt(atEnd ? nearest.end : nearest.start).serialize();
  }

  int? offsetFor(String cfi, {bool end = false}) {
    final point = EpubCfi.parse(cfi);
    if (point == null || point.isRange) return null;
    final element = _elementPoint(point);
    int? result;
    for (final run in runs) {
      final offset = run.offsetFor(point, endPoint: end);
      if (offset == null) continue;
      result = result == null
          ? offset
          : end != element
          ? math.min(result, offset)
          : math.max(result, offset);
    }
    return result;
  }

  /// 标注与装饰的半开原文区间在本段显示文字中的交集。
  (int, int)? rangeFor(String startCfi, String endCfi) {
    final start = EpubCfi.parse(startCfi);
    final end = EpubCfi.parse(endCfi);
    if (start == null || end == null || _comparePoints(start, end) >= 0) {
      return null;
    }
    int? from;
    int? until;
    for (final run in runs) {
      final first = run.pointAt(run.start);
      final last = run.pointAt(run.end, endPoint: true);
      if (run._isElement) {
        if (_comparePoints(start, first) <= 0 &&
            _comparePoints(end, first) > 0) {
          from = from == null ? run.start : math.min(from, run.start);
          until = until == null ? run.end : math.max(until, run.end);
        }
        continue;
      }
      if (_comparePoints(end, first) <= 0 || _comparePoints(start, last) >= 0) {
        continue;
      }
      final a = _comparePoints(start, first) <= 0
          ? run.start
          : run.offsetFor(start) ?? run.start;
      final b = _comparePoints(end, last) >= 0
          ? run.end
          : run.offsetFor(end, endPoint: true) ?? run.end;
      if (b <= a) continue;
      from = from == null ? a : math.min(from, a);
      until = until == null ? b : math.max(until, b);
    }
    return from == null || until == null ? null : (from, until);
  }

  /// 切片只改变显示坐标，不改变原始字符块及源偏移。
  TextCfiMap slice(int start, int end) {
    final builder = TextCfiMapBuilder();
    for (final run in runs) {
      final from = math.max(start, run.start);
      final until = math.min(end, run.end);
      if (until <= from) continue;
      builder.add(
        from - start,
        until - start,
        cfi: run.cfi,
        sourceStart: run.sourceOffset(from),
        sourceEnd: run.sourceOffset(until, endPoint: true),
      );
    }
    return builder.build(
      math.max(0, end - start),
      parent: origin,
      originStart: originStart + start,
    );
  }

  /// 插入伪文字或移除首字后，沿用同一次文字变换的起止坐标。
  TextCfiMap remap({
    required int length,
    required int Function(int) start,
    required int Function(int) end,
  }) {
    final builder = TextCfiMapBuilder();
    for (final _ in _remapSteps(builder, start, end)) {}
    return builder.build(length);
  }

  /// 大段文字变换沿用章节预算；取消不会发布半成品映射。
  Future<TextCfiMap> remapAsync({
    required int length,
    required int Function(int) start,
    required int Function(int) end,
    required Future<void> Function() checkpoint,
  }) async {
    final builder = TextCfiMapBuilder();
    await checkpoint();
    for (final _ in _remapSteps(builder, start, end)) {
      await checkpoint();
    }
    await checkpoint();
    return builder.build(length);
  }

  Iterable<bool> _remapSteps(
    TextCfiMapBuilder builder,
    int Function(int) start,
    int Function(int) end,
  ) sync* {
    var checked = 0;
    for (final run in runs) {
      for (var offset = run.start; offset < run.end; offset++) {
        final from = start(offset);
        final until = end(offset + 1);
        if (until > from) {
          builder.add(
            from,
            until,
            cfi: run.cfi,
            sourceStart: run.sourceOffset(offset),
            sourceEnd: run.sourceOffset(offset + 1, endPoint: true),
          );
        }
        if (++checked % 256 == 0) yield false;
      }
    }
  }

  TextCfiMap transformed(TextOffsetMap? offsets) => offsets == null
      ? this
      : remap(length: offsets.outputLength, start: offsets.at, end: offsets.at);

  Future<TextCfiMap> transformedAsync(
    TextOffsetMap? offsets, {
    required Future<void> Function() checkpoint,
  }) async => offsets == null
      ? this
      : remapAsync(
          length: offsets.outputLength,
          start: offsets.at,
          end: offsets.at,
          checkpoint: checkpoint,
        );
}

/// 相邻线性片段立即合并，保存量按来源字符块而非正文字数增长。
class TextCfiMapBuilder {
  final List<TextCfiRun> _runs = [];

  void add(
    int start,
    int end, {
    required EpubCfi cfi,
    required int sourceStart,
    required int sourceEnd,
  }) {
    if (end <= start) return;
    final previous = _runs.lastOrNull;
    final linear =
        cfi.segments.last.steps.last.index.isOdd &&
        end - start == sourceEnd - sourceStart;
    if (previous != null &&
        previous._linear &&
        linear &&
        (identical(previous.cfi, cfi) || _samePath(previous.cfi, cfi)) &&
        previous.end == start &&
        previous.sourceEnd == sourceStart) {
      _runs.removeLast();
      start = previous.start;
      sourceStart = previous.sourceStart;
    }
    _runs.add(
      TextCfiRun(
        start: start,
        end: end,
        cfi: cfi,
        sourceStart: sourceStart,
        sourceEnd: sourceEnd,
      ),
    );
  }

  void addMap(TextCfiMap map, {int offset = 0}) {
    for (final run in map.runs) {
      add(
        offset + run.start,
        offset + run.end,
        cfi: run.cfi,
        sourceStart: run.sourceStart,
        sourceEnd: run.sourceEnd,
      );
    }
  }

  TextCfiMap build(int length, {TextCfiMap? parent, int originStart = 0}) =>
      TextCfiMap(
        runs: List.unmodifiable(_runs),
        textLength: length,
        parent: parent,
        originStart: originStart,
      );

  void clear() => _runs.clear();
}

bool _samePath(EpubCfi left, EpubCfi right) {
  if (left.segments.length != right.segments.length) return false;
  for (var segment = 0; segment < left.segments.length; segment++) {
    final a = left.segments[segment].steps;
    final b = right.segments[segment].steps;
    if (a.length != b.length) return false;
    for (var step = 0; step < a.length; step++) {
      if (a[step].index != b[step].index) return false;
      final id = b[step].assertion;
      if (id != null && id.isNotEmpty && id != a[step].assertion) return false;
    }
  }
  return true;
}

bool _elementPoint(EpubCfi point) =>
    point.segments.last.steps.last.index.isEven && (point.charOffset ?? 0) == 0;

bool _hasAncestor(EpubCfi child, EpubCfi ancestor) {
  if (child.segments.length != ancestor.segments.length) return false;
  for (var segment = 0; segment < child.segments.length; segment++) {
    final source = child.segments[segment].steps;
    final prefix = ancestor.segments[segment].steps;
    if (source.length < prefix.length ||
        segment < child.segments.length - 1 && source.length != prefix.length) {
      return false;
    }
    for (var step = 0; step < prefix.length; step++) {
      if (source[step].index != prefix[step].index) return false;
      final id = prefix[step].assertion;
      if (id != null && id.isNotEmpty && id != source[step].assertion) {
        return false;
      }
    }
  }
  return true;
}

int _comparePoints(EpubCfi left, EpubCfi right) {
  final count = math.min(left.segments.length, right.segments.length);
  for (var segment = 0; segment < count; segment++) {
    final a = left.segments[segment].steps;
    final b = right.segments[segment].steps;
    for (var step = 0; step < math.min(a.length, b.length); step++) {
      final comparison = a[step].index.compareTo(b[step].index);
      if (comparison != 0) return comparison;
    }
    if (a.length != b.length) return a.length.compareTo(b.length);
  }
  if (left.segments.length != right.segments.length) {
    return left.segments.length.compareTo(right.segments.length);
  }
  return (left.charOffset ?? 0).compareTo(right.charOffset ?? 0);
}
