/// EPUB CFI 的解析、构造、序列化与比较。
///
/// 支持：普通步进、ID 断言（含 `^` 转义）、`!` 间接引用、字符偏移、
/// 范围形式 `epubcfi(parent,start,end)`、side bias；时间/空间偏移解析后忽略。
/// 非法输入一律返回 null，不抛异常。
library;

/// CFI 侧偏：同一位置的前/后侧。
enum CfiSide { before, none, after }

/// CFI 中的一步，例如 `/4[chap01]`。
class CfiStep {
  /// 创建一步。
  const CfiStep(this.index, {this.assertion});

  /// 节点序号。
  final int index;

  /// 方括号内的断言文本（已去转义）。
  final String? assertion;

  /// 序列化。
  String toCfi() {
    final value = assertion;
    if (value == null || value.isEmpty) {
      return '/$index';
    }
    return '/$index[${_escapeAssertion(value)}]';
  }

  @override
  bool operator ==(Object other) =>
      other is CfiStep && other.index == index && other.assertion == assertion;

  @override
  int get hashCode => Object.hash(index, assertion);
}

/// 一个路径段，段之间用 `!` 分隔。
class CfiSegment {
  /// 创建路径段。
  const CfiSegment(
    this.steps, {
    this.offset,
    this.offsetEnd,
    this.side = CfiSide.none,
  });

  /// 步进列表。
  final List<CfiStep> steps;

  /// 字符偏移。
  final int? offset;

  /// 范围结束偏移（`:start,end` 形式）。
  final int? offsetEnd;

  /// 段级 side bias。
  final CfiSide side;

  /// 序列化。
  String toCfi() {
    final buffer = StringBuffer();
    for (final step in steps) {
      buffer.write(step.toCfi());
    }
    if (offset != null) {
      buffer.write(':$offset');
      if (offsetEnd != null) {
        buffer.write(',$offsetEnd');
      }
    }
    switch (side) {
      case CfiSide.before:
        buffer.write('[;s=b]');
      case CfiSide.after:
        buffer.write('[;s=a]');
      case CfiSide.none:
        break;
    }
    return buffer.toString();
  }
}

/// 去掉点 CFI 的终止偏移及侧向断言，得到块级 CFI。
String cfiBase(String cfi) {
  final trimmed = cfi.trim();
  final parsed = EpubCfi.parse(trimmed);
  if (parsed == null || parsed.isRange) return trimmed;
  return EpubCfi([
    ...parsed.segments.take(parsed.segments.length - 1),
    CfiSegment(parsed.segments.last.steps),
  ]).serialize();
}

/// 外部客户端可能省略 spine 与正文之间的 `!`。
///
/// 返回原始位置和按标准 EPUB CFI 补齐间接引用后的候选；无法安全拆分时
/// 只返回原值，避免把合法 CFI 改成错误路径。
Iterable<String> epubCfiCandidates(String cfi) sync* {
  final trimmed = cfi.trim();
  if (trimmed.isEmpty) return;
  final parsed = EpubCfi.parse(trimmed);
  if (parsed == null || parsed.isRange || trimmed.contains('!')) {
    yield trimmed;
    return;
  }
  final first = parsed.segments.first;
  if (first.steps.length < 3) {
    yield trimmed;
    return;
  }
  final normalized = EpubCfi(<CfiSegment>[
    CfiSegment(first.steps.take(2).toList()),
    CfiSegment(
      first.steps.skip(2).toList(),
      offset: first.offset,
      offsetEnd: first.offsetEnd,
      side: first.side,
    ),
    ...parsed.segments.skip(1),
  ]).serialize();
  yield normalized;
  if (normalized != trimmed) yield trimmed;
}

/// 取 CFI 末尾的字符偏移；没有偏移时返回 null。
int? cfiCharOffset(String cfi) {
  final parsed = EpubCfi.parse(cfi.trim());
  return parsed == null || parsed.isRange ? null : parsed.charOffset;
}

/// 给块级 CFI 追加/替换字符偏移（标注区间端点用，§30.2）。
///
/// `epubcfi(/6/4!/4/2/1)` + 3 → `epubcfi(/6/4!/4/2/1:3)`；已有偏移时替换。
/// 输入不是 `epubcfi(...)` 形态时原样返回。
String cfiWithCharOffset(String cfi, int charOffset) {
  final trimmed = cfi.trim();
  final parsed = EpubCfi.parse(trimmed);
  if (parsed == null || parsed.isRange || charOffset < 0) {
    return cfi;
  }
  return parsed.withCharOffset(charOffset).serialize();
}

/// CFI → spine 序号（§34.2）。
///
/// 规范形态 `epubcfi(/6/4!/4/2/1)`：第一段第一步是 package 的 spine 元素，
/// 第二步才是 itemref（步进 = (spineIndex + 1) × 2）；只有单步时按 itemref
/// 处理。解析失败返回 null。
int? spineIndexOfCfi(EpubCfi cfi) {
  if (cfi.segments.isEmpty) {
    return null;
  }
  final steps = cfi.segments.first.steps;
  if (steps.isEmpty) {
    return null;
  }
  final itemRef = steps.length >= 2 ? steps[1] : steps[0];
  final index = itemRef.index ~/ 2 - 1;
  return index < 0 ? null : index;
}

/// 已解析的 EPUB CFI。
class EpubCfi implements Comparable<EpubCfi> {
  /// 从路径段创建。
  EpubCfi(
    this.segments, {
    this.rangeParentBody,
    this.rangeStartBody,
    this.rangeEndBody,
    this.rangeStart,
    this.rangeEnd,
  });

  /// 路径段（用 `!` 分隔）。
  final List<CfiSegment> segments;

  /// 范围形式的原始 parent body（用于稳定序列化）。
  final String? rangeParentBody;

  /// 范围形式的原始 start 片段。
  final String? rangeStartBody;

  /// 范围形式的原始 end 片段。
  final String? rangeEndBody;

  /// 范围起点。
  final EpubCfi? rangeStart;

  /// 范围终点。
  final EpubCfi? rangeEnd;

  /// 是否为范围。
  bool get isRange => rangeStart != null && rangeEnd != null;

  /// `/6` 步进（结构校验）。
  int get spine => segments.first.steps.first.index;

  /// itemref 步进。
  int? get itemref =>
      segments.first.steps.length > 1 ? segments.first.steps[1].index : null;

  /// itemref 断言。
  String? get itemrefAssertion => segments.first.steps.length > 1
      ? segments.first.steps[1].assertion
      : null;

  /// 间接引用后的 body 步进。
  int? get body => segments.length > 1 ? segments[1].steps.first.index : null;

  /// body 之后的所有步进（含后续 `!` 段）。
  List<CfiStep> get steps {
    final result = <CfiStep>[];
    for (var i = 1; i < segments.length; i++) {
      final segment = segments[i];
      result.addAll(i == 1 ? segment.steps.skip(1) : segment.steps);
    }
    return List<CfiStep>.unmodifiable(result);
  }

  /// 最后一个路径段的字符偏移。
  int? get charOffset => segments.last.offset;

  /// 范围形式结束偏移。
  int? get charOffsetEnd => segments.last.offsetEnd;

  /// side bias。
  CfiSide get side => segments.last.side;

  /// 解析 CFI；非法输入返回 null。
  static EpubCfi? parse(String value) {
    if (!value.startsWith('epubcfi(') || !value.endsWith(')')) {
      return null;
    }
    final body = value.substring(8, value.length - 1);
    if (body.isEmpty) {
      return null;
    }

    final parts = _splitTop(body, ',');
    if (parts == null) {
      return null;
    }
    if (parts.length == 3) {
      final parent = _parsePoint(parts[0]);
      if (parent == null || parts[1].isEmpty || parts[2].isEmpty) {
        return null;
      }
      final start = _parsePoint(parts[0] + parts[1]);
      final end = _parsePoint(parts[0] + parts[2]);
      if (start == null || end == null) {
        return null;
      }
      return EpubCfi(
        parent.segments,
        rangeParentBody: parts[0],
        rangeStartBody: parts[1],
        rangeEndBody: parts[2],
        rangeStart: start,
        rangeEnd: end,
      );
    }
    if (parts.length != 1) {
      return null;
    }
    return _parsePoint(body);
  }

  static EpubCfi? _parsePoint(String body) {
    final rawSegments = _splitTop(body, '!');
    if (rawSegments == null || rawSegments.isEmpty) {
      return null;
    }
    final segments = <CfiSegment>[];
    for (final raw in rawSegments) {
      final segment = _parseSegment(raw);
      if (segment == null) {
        return null;
      }
      segments.add(segment);
    }
    if (segments.first.steps.isEmpty) {
      return null;
    }
    return EpubCfi(segments);
  }

  static CfiSegment? _parseSegment(String raw) {
    if (raw.isEmpty) {
      return null;
    }
    final steps = <CfiStep>[];
    var i = 0;
    while (i < raw.length && raw[i] == '/') {
      i += 1;
      final start = i;
      while (i < raw.length && _isDigit(raw[i])) {
        i += 1;
      }
      if (i == start) {
        return null;
      }
      final index = int.tryParse(raw.substring(start, i));
      if (index == null) {
        return null;
      }
      String? assertion;
      if (i < raw.length && raw[i] == '[') {
        final close = _findClosingBracket(raw, i);
        if (close < 0) {
          return null;
        }
        assertion = _unescape(raw.substring(i + 1, close));
        i = close + 1;
      }
      steps.add(CfiStep(index, assertion: assertion));
    }
    if (steps.isEmpty) {
      return null;
    }

    int? offset;
    int? offsetEnd;
    if (i < raw.length && raw[i] == ':') {
      i += 1;
      final start = i;
      while (i < raw.length && _isDigit(raw[i])) {
        i += 1;
      }
      if (i == start) {
        return null;
      }
      offset = int.tryParse(raw.substring(start, i));
      if (offset == null) {
        return null;
      }
      if (i < raw.length && raw[i] == ',') {
        i += 1;
        final endStart = i;
        while (i < raw.length && _isDigit(raw[i])) {
          i += 1;
        }
        if (i == endStart) {
          return null;
        }
        offsetEnd = int.tryParse(raw.substring(endStart, i));
        if (offsetEnd == null) {
          return null;
        }
      }
    }

    var side = CfiSide.none;
    if (i < raw.length && (raw[i] == '~' || raw[i] == '@')) {
      // 时间/空间偏移：解析后忽略其余内容。
      return CfiSegment(
        steps,
        offset: offset,
        offsetEnd: offsetEnd,
        side: side,
      );
    }
    if (i < raw.length && raw[i] == '[') {
      final close = _findClosingBracket(raw, i);
      if (close < 0) {
        return null;
      }
      final marker = raw.substring(i + 1, close);
      side = switch (marker) {
        ';s=b' => CfiSide.before,
        ';s=a' => CfiSide.after,
        _ => CfiSide.none,
      };
      if (side == CfiSide.none) {
        return null;
      }
      i = close + 1;
    }
    if (i != raw.length) {
      return null;
    }
    return CfiSegment(steps, offset: offset, offsetEnd: offsetEnd, side: side);
  }

  /// 序列化为标准字符串。
  String serialize() {
    if (isRange) {
      return 'epubcfi($rangeParentBody,$rangeStartBody,$rangeEndBody)';
    }
    return 'epubcfi(${segments.map((segment) => segment.toCfi()).join('!')})';
  }

  /// 全序比较：spine → itemref → 步进 → 偏移 → side。
  @override
  int compareTo(EpubCfi other) {
    if (isRange || other.isRange) {
      final left = isRange ? rangeStart! : this;
      final right = other.isRange ? other.rangeStart! : other;
      final startCompare = left._comparePoint(right);
      if (startCompare != 0) {
        return startCompare;
      }
      final leftEnd = isRange ? rangeEnd! : this;
      final rightEnd = other.isRange ? other.rangeEnd! : other;
      return leftEnd._comparePoint(rightEnd);
    }
    return _comparePoint(other);
  }

  int _comparePoint(EpubCfi other) {
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
      final assertionResult = (a.steps[i].assertion ?? '').compareTo(
        b.steps[i].assertion ?? '',
      );
      if (assertionResult != 0) {
        return assertionResult;
      }
    }
    if (a.steps.length != b.steps.length) {
      return a.steps.length.compareTo(b.steps.length);
    }
    final offsetResult = (a.offset ?? -1).compareTo(b.offset ?? -1);
    if (offsetResult != 0) {
      return offsetResult;
    }
    final endResult = (a.offsetEnd ?? -1).compareTo(b.offsetEnd ?? -1);
    if (endResult != 0) {
      return endResult;
    }
    return a.side.index.compareTo(b.side.index);
  }

  /// 当前 CFI 是否包含 [other]（点或范围）。
  bool contains(EpubCfi other) {
    if (!isRange) {
      return compareTo(other) == 0;
    }
    final otherStart = other.isRange ? other.rangeStart! : other;
    final otherEnd = other.isRange ? other.rangeEnd! : other;
    return rangeStart!.compareTo(otherStart) <= 0 &&
        rangeEnd!.compareTo(otherEnd) >= 0;
  }

  /// 在最后一个路径段上设置字符偏移，不重建步骤。
  EpubCfi withCharOffset(int offset, {int? end}) {
    final copied = <CfiSegment>[];
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      copied.add(
        CfiSegment(
          segment.steps,
          offset: i == segments.length - 1 ? offset : segment.offset,
          offsetEnd: i == segments.length - 1 ? end : segment.offsetEnd,
          side: segment.side,
        ),
      );
    }
    return EpubCfi(
      copied,
      rangeParentBody: rangeParentBody,
      rangeStartBody: rangeStartBody,
      rangeEndBody: rangeEndBody,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
    );
  }

  /// 仅替换 side，不重建步骤。
  EpubCfi copyWithSide(CfiSide value) {
    if (segments.isEmpty) {
      return this;
    }
    final copied = <CfiSegment>[];
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      copied.add(
        CfiSegment(
          segment.steps,
          offset: segment.offset,
          offsetEnd: segment.offsetEnd,
          side: i == segments.length - 1 ? value : segment.side,
        ),
      );
    }
    return EpubCfi(
      copied,
      rangeParentBody: rangeParentBody,
      rangeStartBody: rangeStartBody,
      rangeEndBody: rangeEndBody,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
    );
  }

  @override
  String toString() => serialize();
}

/// CFI 构造器。
class CfiBuilder {
  /// 创建构造器。
  CfiBuilder();

  int? _itemref;
  String? _itemrefAssertion;
  final List<List<CfiStep>> _segmentSteps = <List<CfiStep>>[];
  final List<int?> _offsets = <int?>[];
  final List<int?> _offsetEnds = <int?>[];
  int _current = -1;
  CfiSide _side = CfiSide.none;

  /// 设置 itemref 步进。
  CfiBuilder itemRef(int index, {String? assertion}) {
    _itemref = index;
    _itemrefAssertion = assertion;
    return this;
  }

  /// 设置 body 步进（自动开启 `!` 后的新段）。
  CfiBuilder body(int index, {String? assertion}) {
    _startSegment();
    _segmentSteps[_current].add(CfiStep(index, assertion: assertion));
    return this;
  }

  /// 添加一个步进。
  CfiBuilder step(int index, {String? assertion}) {
    if (_current < 0) {
      _startSegment();
    }
    _segmentSteps[_current].add(CfiStep(index, assertion: assertion));
    return this;
  }

  /// 开启新的间接段。
  CfiBuilder indirection() {
    _startSegment();
    return this;
  }

  /// 设置字符偏移。
  CfiBuilder charOffset(int offset, {int? end}) {
    if (_current < 0) {
      _startSegment();
    }
    _offsets[_current] = offset;
    _offsetEnds[_current] = end;
    return this;
  }

  /// 设置 side bias。
  CfiBuilder side(CfiSide value) {
    _side = value;
    return this;
  }

  /// 构造 CFI；结构不完整时抛 [StateError]。
  EpubCfi build() {
    if (_itemref == null) {
      throw StateError('CFI 缺少 itemref');
    }
    final first = CfiSegment(<CfiStep>[
      const CfiStep(6),
      CfiStep(_itemref!, assertion: _itemrefAssertion),
    ]);
    final segments = <CfiSegment>[first];
    for (var i = 0; i < _segmentSteps.length; i++) {
      final steps = _segmentSteps[i];
      if (steps.isEmpty) {
        continue;
      }
      final isLast = _segmentSteps.skip(i + 1).every((s) => s.isEmpty);
      segments.add(
        CfiSegment(
          List<CfiStep>.of(steps),
          offset: _offsets[i],
          offsetEnd: _offsetEnds[i],
          side: isLast ? _side : CfiSide.none,
        ),
      );
    }
    return EpubCfi(segments);
  }

  void _startSegment() {
    _segmentSteps.add(<CfiStep>[]);
    _offsets.add(null);
    _offsetEnds.add(null);
    _current = _segmentSteps.length - 1;
  }
}

bool _isDigit(String value) =>
    value.codeUnitAt(0) >= 48 && value.codeUnitAt(0) <= 57;

int _findClosingBracket(String value, int open) {
  var escape = false;
  for (var i = open + 1; i < value.length; i++) {
    final char = value[i];
    if (escape) {
      escape = false;
    } else if (char == '^') {
      escape = true;
    } else if (char == ']') {
      return i;
    }
  }
  return -1;
}

String _unescape(String value) {
  final buffer = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    if (value[i] == '^' && i + 1 < value.length) {
      buffer.write(value[i + 1]);
      i += 1;
    } else {
      buffer.write(value[i]);
    }
  }
  return buffer.toString();
}

String _escapeAssertion(String value) {
  final buffer = StringBuffer();
  for (final char in value.split('')) {
    if ('^/[](),'.contains(char)) {
      buffer.write('^');
    }
    buffer.write(char);
  }
  return buffer.toString();
}

List<String>? _splitTop(String value, String separator) {
  final parts = <String>[];
  var depth = 0;
  var escape = false;
  var start = 0;
  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    if (escape) {
      escape = false;
      continue;
    }
    if (char == '^') {
      escape = true;
      continue;
    }
    if (char == '[') {
      depth += 1;
    } else if (char == ']') {
      depth -= 1;
      if (depth < 0) {
        return null;
      }
    } else if (char == separator && depth == 0) {
      parts.add(value.substring(start, i));
      start = i + 1;
    }
  }
  if (depth != 0) {
    return null;
  }
  parts.add(value.substring(start));
  return parts;
}
