/// EPUB CFI 的位置解析与序列化（P0-18 原型）。
///
/// 当前覆盖：普通步进、ID 断言、`!` 间接引用、字符偏移。
/// 区间（range）与文本断言留到 P1-09/P1-10 扩展；非法输入返回 null。
library;

/// CFI 中的一步，例如 `/4[chap01]`。
class CfiStep {
  /// 创建一步。
  const CfiStep(this.index, {this.assertion});

  /// 节点序号。
  final int index;

  /// 方括号内的原始断言文本（可为空）。
  final String? assertion;

  /// 序列化。
  String toCfi() {
    final assertion = this.assertion;
    if (assertion == null || assertion.isEmpty) {
      return '/$index';
    }
    return '/$index[$assertion]';
  }
}

/// 一个 CFI 路径段，步进之间用 `/` 连接，段之间用 `!` 连接。
class CfiSegment {
  /// 创建路径段。
  const CfiSegment(this.steps, {this.offset});

  /// 步进列表。
  final List<CfiStep> steps;

  /// 字符偏移（终端偏移），可为空。
  final int? offset;

  /// 序列化。
  String toCfi() {
    final buffer = StringBuffer();
    for (final step in steps) {
      buffer.write(step.toCfi());
    }
    final offset = this.offset;
    if (offset != null) {
      buffer.write(':$offset');
    }
    return buffer.toString();
  }
}

/// 已解析的 EPUB CFI。
class EpubCfi {
  const EpubCfi(this.raw, this.segments);

  /// 原始字符串（规范化前）。
  final String raw;

  /// 路径段（用 `!` 分隔）。
  final List<CfiSegment> segments;

  static final RegExp _wrapper = RegExp(r'^epubcfi\((.*)\)$');
  static final RegExp _step = RegExp(r'/(\d+)(?:\[([^\[\]]*)\])?');

  /// 解析 CFI；非法输入返回 null，不抛异常。
  static EpubCfi? parse(String value) {
    final match = _wrapper.firstMatch(value);
    if (match == null) {
      return null;
    }
    final body = match.group(1)!;
    if (body.isEmpty) {
      return null;
    }

    final segments = <CfiSegment>[];
    for (final rawSegment in body.split('!')) {
      if (rawSegment.isEmpty) {
        return null;
      }

      var index = 0;
      final steps = <CfiStep>[];
      while (index < rawSegment.length && rawSegment[index] == '/') {
        final stepMatch = _step.matchAsPrefix(rawSegment, index);
        if (stepMatch == null) {
          return null;
        }
        final number = stepMatch.group(1)!;
        final assertion = stepMatch.group(2);
        steps.add(CfiStep(int.parse(number), assertion: assertion));
        index = stepMatch.end;
      }
      if (steps.isEmpty) {
        return null;
      }

      int? offset;
      if (index < rawSegment.length) {
        if (rawSegment[index] != ':') {
          return null;
        }
        final offsetText = rawSegment.substring(index + 1);
        final parsed = int.tryParse(offsetText);
        if (parsed == null || parsed < 0) {
          return null;
        }
        offset = parsed;
        index = rawSegment.length;
      }

      if (index != rawSegment.length) {
        return null;
      }
      segments.add(CfiSegment(steps, offset: offset));
    }

    if (segments.isEmpty) {
      return null;
    }
    return EpubCfi(value, segments);
  }

  /// 序列化为标准字符串。
  String serialize() {
    final body = segments.map((segment) => segment.toCfi()).join('!');
    return 'epubcfi($body)';
  }

  /// 按路径与偏移做字典序比较。
  int compareTo(EpubCfi other) {
    final length = segments.length < other.segments.length
        ? segments.length
        : other.segments.length;
    for (var i = 0; i < length; i++) {
      final result = _compareSegment(segments[i], other.segments[i]);
      if (result != 0) {
        return result;
      }
    }
    return segments.length.compareTo(other.segments.length);
  }

  static int _compareSegment(CfiSegment a, CfiSegment b) {
    final length = a.steps.length < b.steps.length
        ? a.steps.length
        : b.steps.length;
    for (var i = 0; i < length; i++) {
      final indexResult = a.steps[i].index.compareTo(b.steps[i].index);
      if (indexResult != 0) {
        return indexResult;
      }
      final assertionResult = (a.steps[i].assertion ?? '')
          .compareTo(b.steps[i].assertion ?? '');
      if (assertionResult != 0) {
        return assertionResult;
      }
    }
    if (a.steps.length != b.steps.length) {
      return a.steps.length.compareTo(b.steps.length);
    }
    return (a.offset ?? -1).compareTo(b.offset ?? -1);
  }

  @override
  String toString() => serialize();
}
