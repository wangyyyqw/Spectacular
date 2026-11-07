import 'dart:math' as math;

import 'package:reader_core/layout/line_breaker.dart';

bool isHighSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

bool isLowSurrogate(int codeUnit) => codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

List<StyledRun> sliceTextRuns(TextLayoutResult layout, int start, int end) {
  final runs = <StyledRun>[];
  for (final run in layout.runs) {
    final runStart = math.max(run.start, start);
    final runEnd = math.min(run.end, end);
    if (runEnd <= runStart) continue;
    runs.add(
      StyledRun(
        start: runStart - start,
        end: runEnd - start,
        style: run.style,
        baselineShift: run.baselineShift,
        syntheticFontFallback: run.syntheticFontFallback,
      ),
    );
  }
  return runs;
}
