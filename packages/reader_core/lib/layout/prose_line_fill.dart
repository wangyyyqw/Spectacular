import '../css/computed_style.dart';
import 'cjk_justify.dart';
import 'line_breaker.dart';

/// 普通正文的行尾微调；不改 CSS、断点或缓存中的原始测量结果。
TextLayoutResult fillProseLines(TextLayoutResult layout, ComputedStyle style) {
  if (layout.lines.length < 2 ||
      layout.isVertical ||
      layout.isRtl ||
      (style.textAlign != CssTextAlign.left &&
          style.textAlign != CssTextAlign.start) ||
      style.letterSpacing != 0 ||
      style.wordSpacing != 0 ||
      layout.runs.any(
        (run) =>
            run.baselineShift != 0 ||
            run.style.fontSize != style.fontSize ||
            run.style.letterSpacing != 0 ||
            run.style.wordSpacing != 0,
      )) {
    return layout;
  }
  var changed = false;
  final lines = <LineBox>[];
  for (final line in layout.lines) {
    final filled = _fillLine(layout, line, style.fontSize);
    changed = changed || !identical(filled, line);
    lines.add(filled);
  }
  return changed ? _withLines(layout, lines) : layout;
}

TextLayoutResult _withLines(TextLayoutResult layout, List<LineBox> lines) =>
    TextLayoutResult(
      text: layout.text,
      lines: List.unmodifiable(lines),
      width: layout.width,
      height: layout.height,
      maxWidth: layout.maxWidth,
      runs: layout.runs,
      isRtl: layout.isRtl,
      writingMode: layout.writingMode,
      plainTextLayout: layout.plainTextLayout,
      firstLineStyle: layout.firstLineStyle,
      firstLineRuns: layout.firstLineRuns,
      sourceRuns: layout.sourceRuns,
    );

LineBox _fillLine(TextLayoutResult layout, LineBox line, double em) {
  if (!_canFillLine(line)) return line;
  final slack = layout.maxWidth - line.offsetX - line.width;
  if (!slack.isFinite || slack <= .01) return line;
  final text = layout.text.substring(line.start, line.end);
  if (text.runes.where(_isHan).length < 12) return line;
  final spacing = line.spacing ?? LineSpacing.empty;
  // 只在连续汉字之间分配，标点、英文、数字及字簇内部均不追加间距。
  final gaps = cjkJustifyGapOffsets(text).where((offset) {
    if (spacing.lockedGaps.contains(offset)) return false;
    final left = text.runesAt(offset);
    final next = offset + (left > 0xffff ? 2 : 1);
    return _isHan(left) && _isHan(text.runesAt(next));
  }).toList();
  // 大空白保持原样，避免把短句拉成稀疏行。
  if (gaps.length < 8 || slack / gaps.length > em * .1) return line;
  return line.copyWith(
    justifyExtra: slack,
    spacing: spacing.withJustifyGaps(gaps),
  );
}

bool _canFillLine(LineBox line) =>
    !line.isLastLine &&
    !line.isHardBreak &&
    !line.ellipsized &&
    !line.hyphenated &&
    line.justifyExtra == 0 &&
    line.inlineBoxes.isEmpty &&
    line.offsetX == line.indent;

bool _isHan(int code) =>
    code >= 0x3400 && code <= 0x4dbf ||
    code >= 0x4e00 && code <= 0x9fff ||
    code >= 0xf900 && code <= 0xfaff ||
    code >= 0x20000 && code <= 0x2fa1f;

extension on String {
  int runesAt(int offset) {
    final first = codeUnitAt(offset);
    if (first >= 0xd800 && first <= 0xdbff && offset + 1 < length) {
      return 0x10000 +
          ((first - 0xd800) << 10) +
          codeUnitAt(offset + 1) -
          0xdc00;
    }
    return first;
  }
}
