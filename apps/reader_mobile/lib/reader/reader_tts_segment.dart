import 'package:reader_core/position/location_anchor.dart' show utf16Boundary;

/// 朗读片段的类型。
enum ReaderTtsSegmentKind { narration, dialogue }

/// 朗读文字及其每个 UTF-16 单元对应的原文位置。
class ReaderTtsSegment {
  const ReaderTtsSegment({
    required this.text,
    required this.kind,
    this.sourceOffsets = const [],
    this.continuesOnNextPage = false,
  });

  final String text;
  final ReaderTtsSegmentKind kind;
  final List<int> sourceOffsets;

  /// 只有分页拆开的同一句段需要连续播放，句读与对白切换仍保留停顿。
  final bool continuesOnNextPage;

  bool get isDialogue => kind == ReaderTtsSegmentKind.dialogue;

  int rawStart(int offset) => sourceOffsets.isEmpty
      ? offset
      : sourceOffsets[offset.clamp(0, sourceOffsets.length - 1)];

  int rawEnd(int offset) => sourceOffsets.isEmpty
      ? offset
      : offset <= 0
      ? sourceOffsets.first
      : sourceOffsets[offset.clamp(1, sourceOffsets.length) - 1] + 1;
}

/// 按引号、句读、页末与长度分段，同时保留清理空白后的原文坐标。
abstract final class ReaderTtsSegmentation {
  static final _noise = RegExp(r'[※＊*·•●○◆◇■□━─—=~]{2,}');
  static final _space = RegExp(r'\s|\u00a0', unicode: true);
  static const _ends = '。！？!?；;';
  static const _soft = '，,、：: ';

  static List<ReaderTtsSegment> split(
    String text, {
    Iterable<int> paragraphStarts = const [],
    Iterable<int> pageEnds = const [],
  }) {
    final normalized = _normalize(text);
    final breaks = _mappedBreaks(normalized, paragraphStarts);
    final pages = _mappedBreaks(normalized, pageEnds);
    final result = <ReaderTtsSegment>[];
    for (final chunk in _quoteRanges(normalized.text)) {
      for (final range in _sentenceRanges(
        normalized.text,
        chunk.start,
        chunk.end,
        breaks,
      )) {
        for (final part in _pageRanges(range, pages)) {
          result.add(
            ReaderTtsSegment(
              text: normalized.text.substring(part.$1, part.$2),
              kind: chunk.dialogue
                  ? ReaderTtsSegmentKind.dialogue
                  : ReaderTtsSegmentKind.narration,
              sourceOffsets: normalized.offsets.sublist(part.$1, part.$2),
              continuesOnNextPage: part.$2 < range.$2,
            ),
          );
        }
      }
    }
    return result;
  }

  static Set<int> _mappedBreaks(
    ({String text, List<int> offsets}) normalized,
    Iterable<int> rawBreaks,
  ) {
    final breaks = <int>{};
    var index = 0;
    for (final start in rawBreaks.toSet().toList()..sort()) {
      while (index < normalized.offsets.length &&
          normalized.offsets[index] < start) {
        index++;
      }
      breaks.add(utf16Boundary(normalized.text, index));
    }
    return breaks;
  }

  static Iterable<(int, int)> _pageRanges(
    (int, int) range,
    Set<int> pages,
  ) sync* {
    var start = range.$1;
    for (final stop in pages) {
      if (stop <= start || stop >= range.$2) continue;
      yield (start, stop);
      start = stop;
    }
    yield (start, range.$2);
  }

  static ({String text, List<int> offsets}) _normalize(String text) {
    final buffer = StringBuffer();
    final offsets = <int>[];
    final noise = {
      for (final match in _noise.allMatches(text)) match.start: match.end,
    };
    var space = true;
    for (var i = 0; i < text.length; i++) {
      final noiseEnd = noise[i];
      final whitespace = noiseEnd != null || _space.hasMatch(text[i]);
      if (!whitespace || !space) {
        buffer.write(whitespace ? ' ' : text[i]);
        offsets.add(i);
      }
      space = whitespace;
      if (noiseEnd != null) i = noiseEnd - 1;
    }
    var normalized = buffer.toString();
    if (normalized.endsWith(' ')) {
      normalized = normalized.substring(0, normalized.length - 1);
      offsets.removeLast();
    }
    return (text: normalized, offsets: offsets);
  }

  static Iterable<({int start, int end, bool dialogue})> _quoteRanges(
    String text,
  ) sync* {
    const quotes = {'“': '”', '「': '」', '『': '』', '"': '"'};
    String? closer;
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (closer != null && char == closer) {
        if (start < i) yield (start: start, end: i, dialogue: true);
        closer = null;
        start = i + 1;
      } else if (closer == null && quotes.containsKey(char)) {
        if (start < i) yield (start: start, end: i, dialogue: false);
        closer = quotes[char];
        start = i + 1;
      }
    }
    if (start < text.length) {
      yield (start: start, end: text.length, dialogue: closer != null);
    }
  }

  static Iterable<(int, int)> _sentenceRanges(
    String text,
    int start,
    int end,
    Set<int> breaks,
  ) sync* {
    var cursor = start;
    while (cursor < end) {
      while (cursor < end && text[cursor] == ' ') {
        cursor++;
      }
      if (cursor == end) break;
      var limit = cursor;
      while (limit < end &&
          !_ends.contains(text[limit]) &&
          (limit == cursor || !breaks.contains(limit))) {
        limit++;
      }
      while (limit < end &&
          _ends.contains(text[limit]) &&
          (limit == cursor || !breaks.contains(limit))) {
        limit++;
      }
      yield* _boundedRanges(text, cursor, limit);
      cursor = limit;
    }
  }

  static Iterable<(int, int)> _boundedRanges(
    String text,
    int cursor,
    int limit,
  ) sync* {
    while (cursor < limit) {
      var stop = limit;
      if (stop - cursor > 160) {
        stop = utf16Boundary(text, cursor + 160);
        for (var i = stop - 1; i >= cursor + 80; i--) {
          if (_soft.contains(text[i])) {
            stop = i + 1;
            break;
          }
        }
      }
      var trimmedEnd = stop;
      while (trimmedEnd > cursor && text[trimmedEnd - 1] == ' ') {
        trimmedEnd--;
      }
      if (trimmedEnd > cursor) yield (cursor, trimmedEnd);
      cursor = stop;
      while (cursor < limit && text[cursor] == ' ') {
        cursor++;
      }
    }
  }
}
