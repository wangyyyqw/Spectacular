import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:reader_core/layout/paginator.dart';

import 'selection/text_range_geometry.dart';

/// 正在朗读的原文区间；只用于绘制，不生成标注记录。
@immutable
class ReaderReadingHighlight {
  const ReaderReadingHighlight({
    required this.spineIndex,
    required this.startCfi,
    required this.endCfi,
    this.wordStartCfi,
    this.wordEndCfi,
  });

  final int spineIndex;
  final String startCfi;
  final String endCfi;
  final String? wordStartCfi;
  final String? wordEndCfi;

  @override
  bool operator ==(Object other) =>
      other is ReaderReadingHighlight &&
      spineIndex == other.spineIndex &&
      startCfi == other.startCfi &&
      endCfi == other.endCfi &&
      wordStartCfi == other.wordStartCfi &&
      wordEndCfi == other.wordEndCfi;

  @override
  int get hashCode =>
      Object.hash(spineIndex, startCfi, endCfi, wordStartCfi, wordEndCfi);
}

/// 独立重绘朗读区间，避免字词回调使正文重排或失效翻页位图。
class ReaderReadingHighlightLayer extends StatelessWidget {
  const ReaderReadingHighlightLayer({
    super.key,
    required this.page,
    required this.highlight,
    required this.color,
    this.inkMode = false,
  });

  final PageContent page;
  final ValueListenable<ReaderReadingHighlight?> highlight;
  final Color color;
  final bool inkMode;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: ReaderReadingHighlightPainter(
            page: page,
            highlight: highlight,
            color: color,
            inkMode: inkMode,
          ),
        ),
      ),
    ),
  );
}

/// 复用选区几何，保留跨行、跨块、跨页及竖排的真实字形位置。
class ReaderReadingHighlightPainter extends CustomPainter {
  ReaderReadingHighlightPainter({
    required this.page,
    required this.highlight,
    required this.color,
    this.inkMode = false,
  }) : super(repaint: highlight);

  final PageContent page;
  final ValueListenable<ReaderReadingHighlight?> highlight;
  final Color color;
  final bool inkMode;

  @override
  void paint(Canvas canvas, Size size) {
    final range = highlight.value;
    if (range == null || range.spineIndex != page.spineIndex) return;
    _paintRange(canvas, range.startCfi, range.endCfi, word: false);
    if (range.wordStartCfi != null && range.wordEndCfi != null) {
      _paintRange(canvas, range.wordStartCfi!, range.wordEndCfi!, word: true);
    }
  }

  void _paintRange(
    Canvas canvas,
    String start,
    String end, {
    required bool word,
  }) {
    final paint = Paint()
      ..color = color.withValues(alpha: inkMode ? 1 : (word ? 0.24 : 0.12));
    for (final line in ReaderTextRangeGeometry.linesFor(
      page,
      startCfi: start,
      endCfi: end,
    )) {
      for (final rect in line.rects) {
        if (inkMode) {
          canvas.drawRect(
            line.line.isVertical
                ? Rect.fromLTWH(rect.right - 1.5, rect.top, 1.5, rect.height)
                : Rect.fromLTWH(rect.left, rect.bottom - 1.5, rect.width, 1.5),
            paint,
          );
        } else {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(2)),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant ReaderReadingHighlightPainter oldDelegate) =>
      page != oldDelegate.page ||
      highlight != oldDelegate.highlight ||
      color != oldDelegate.color ||
      inkMode != oldDelegate.inkMode;
}
