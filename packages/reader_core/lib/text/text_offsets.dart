/// 实际写出的一个文字片段；相邻恒等片段合并，不按正文字数保存数组。
class TextOffsetSpan {
  const TextOffsetSpan(this.start, this.end, this.outputStart, this.outputEnd);

  final int start;
  final int end;
  final int outputStart;
  final int outputEnd;

  int at(int offset) =>
      outputStart +
      (offset - start) * (outputEnd - outputStart) ~/ (end - start);
}

/// 同一次文字变换记录的输入 UTF-16 边界到显示边界映射。
class TextOffsetMap {
  const TextOffsetMap({
    required this.spans,
    required this.inputLength,
    required this.outputLength,
    this.previous,
    this.following,
  });

  final List<TextOffsetSpan> spans;
  final int inputLength;
  final int outputLength;
  final TextOffsetMap? previous;
  final TextOffsetMap? following;

  int at(int offset) {
    final first = previous;
    final second = following;
    if (first != null && second != null) return second.at(first.at(offset));
    final safe = offset.clamp(0, inputLength);
    var low = 0;
    var high = spans.length - 1;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (spans[middle].end < safe) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return spans.isEmpty ? safe : spans[low].at(safe);
  }

  TextOffsetMap then(TextOffsetMap next) => TextOffsetMap(
    spans: const [],
    inputLength: inputLength,
    outputLength: next.outputLength,
    previous: this,
    following: next,
  );

  static TextOffsetMap? removal(int length, int start, int end) =>
      (TextOffsetMapBuilder()
            ..add(start, start)
            ..add(end - start, 0)
            ..add(length - end, length - end))
          .build();
}

/// 恒等变换不分配映射；扩展、折叠时按实际写出的片段记录。
class TextOffsetMapBuilder {
  List<TextOffsetSpan>? _spans;
  int _inputLength = 0;
  int _outputLength = 0;

  void add(int inputLength, int outputLength) {
    if (inputLength <= 0) return;
    if (_spans == null && inputLength != outputLength) {
      _spans = [
        if (_inputLength > 0) TextOffsetSpan(0, _inputLength, 0, _outputLength),
      ];
    }
    final spans = _spans;
    if (spans != null) {
      final previous = spans.lastOrNull;
      var start = _inputLength;
      var outputStart = _outputLength;
      if (previous != null &&
          previous.end - previous.start ==
              previous.outputEnd - previous.outputStart &&
          inputLength == outputLength) {
        spans.removeLast();
        start = previous.start;
        outputStart = previous.outputStart;
      }
      spans.add(
        TextOffsetSpan(
          start,
          _inputLength + inputLength,
          outputStart,
          _outputLength + outputLength,
        ),
      );
    }
    _inputLength += inputLength;
    _outputLength += outputLength;
  }

  TextOffsetMap? build() {
    final spans = _spans;
    return spans == null
        ? null
        : TextOffsetMap(
            spans: List.unmodifiable(spans),
            inputLength: _inputLength,
            outputLength: _outputLength,
          );
  }
}

TextOffsetMap? composeTextOffsets(
  TextOffsetMap? first,
  TextOffsetMap? second,
) => first == null
    ? second
    : second == null
    ? first
    : first.then(second);
