import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/position/cfi.dart';

import 'annotation.dart';
import 'decorations.dart';

/// 一条想法在结束页的页边图标与触控区域。
class ReaderThoughtMarker {
  /// 创建页边标记。
  const ReaderThoughtMarker({required this.annotation, required this.center});

  /// 对应的想法。
  final ReaderAnnotation annotation;

  /// 页内容坐标中的中心。
  final Offset center;

  /// 44dp 触控目标。
  Rect get touchRect => Rect.fromCenter(center: center, width: 44, height: 44);
}

/// 页边图标只在想法终点所在页出现，碰撞后按 18dp 错开。
abstract final class ThoughtMarkerGeometry {
  /// 图标的可见边长。
  static const double iconSize = 12;

  /// 图标中心距正文边缘的距离。
  static const double marginOffset = 8;

  /// 计算当前页的所有图标；横排 LTR 在右，RTL 和竖排在左。
  static List<ReaderThoughtMarker> markersFor(
    PageContent page,
    List<AnnotationLine> lines, {
    double? contentWidth,
  }) {
    final lastLines = <String, AnnotationLine>{};
    for (final line in lines) {
      if (line.annotation.type == ReaderAnnotationType.thought) {
        lastLines[line.annotation.id] = line;
      }
    }
    final width =
        contentWidth ??
        lines.fold<double>(
          0,
          (result, line) => math.max(result, line.line.rect.right),
        );
    final markers = <ReaderThoughtMarker>[];
    for (final line in lastLines.values) {
      if (!_endsOnThisPage(line)) continue;
      final left =
          line.line.isVertical ||
          line.line.slice.block.style?.values['direction'] == 'rtl';
      markers.add(
        ReaderThoughtMarker(
          annotation: line.annotation,
          center: Offset(
            left ? -marginOffset : width + marginOffset,
            line.line.rect.center.dy,
          ),
        ),
      );
    }
    return [
      ..._separate(
        markers.where((marker) => marker.center.dx < 0).toList(),
        page.pageHeight,
      ),
      ..._separate(
        markers.where((marker) => marker.center.dx >= 0).toList(),
        page.pageHeight,
      ),
    ];
  }

  static bool _endsOnThisPage(AnnotationLine line) {
    final base = EpubCfi.parse(line.line.slice.block.startCfi ?? '');
    final end = EpubCfi.parse(line.annotation.endCfi);
    if (base == null || end == null) return false;
    final lineEnd = base.withCharOffset(
      (base.charOffset ?? 0) + line.line.blockTextOffset + line.endOffset,
    );
    return lineEnd.compareTo(end) >= 0;
  }

  static List<ReaderThoughtMarker> _separate(
    List<ReaderThoughtMarker> markers,
    double height,
  ) {
    markers.sort((left, right) => left.center.dy.compareTo(right.center.dy));
    final positions = <double>[];
    final bottom = math.max(iconSize / 2, height - iconSize / 2);
    for (final marker in markers) {
      positions.add(
        math.max(
          marker.center.dy.clamp(iconSize / 2, bottom),
          positions.isEmpty ? iconSize / 2 : positions.last + 18,
        ),
      );
    }
    for (var index = positions.length - 1; index >= 0; index--) {
      positions[index] = math.min(
        positions[index],
        index == positions.length - 1 ? bottom : positions[index + 1] - 18,
      );
    }
    return [
      for (var index = 0; index < markers.length; index++)
        ReaderThoughtMarker(
          annotation: markers[index].annotation,
          center: Offset(
            markers[index].center.dx,
            math.max(iconSize / 2, positions[index]),
          ),
        ),
    ];
  }

  /// 绘制便签轮廓、折角与两行短线。
  static void paint(Canvas canvas, ReaderThoughtMarker marker, Color color) {
    final rect = Rect.fromCenter(
      center: marker.center,
      width: iconSize,
      height: iconSize,
    );
    final border = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeJoin = StrokeJoin.round;
    final outline = Path()
      ..moveTo(rect.left + 2, rect.top)
      ..lineTo(rect.right - 4, rect.top)
      ..lineTo(rect.right, rect.top + 4)
      ..lineTo(rect.right, rect.bottom - 2)
      ..quadraticBezierTo(rect.right, rect.bottom, rect.right - 2, rect.bottom)
      ..lineTo(rect.left + 2, rect.bottom)
      ..quadraticBezierTo(rect.left, rect.bottom, rect.left, rect.bottom - 2)
      ..lineTo(rect.left, rect.top + 2)
      ..quadraticBezierTo(rect.left, rect.top, rect.left + 2, rect.top)
      ..close();
    canvas.drawPath(outline, border);
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - 4, rect.top)
        ..lineTo(rect.right - 4, rect.top + 4)
        ..lineTo(rect.right, rect.top + 4),
      border,
    );
    canvas.drawLine(
      Offset(rect.left + 3, rect.top + 6),
      Offset(rect.right - 3, rect.top + 6),
      border,
    );
    canvas.drawLine(
      Offset(rect.left + 3, rect.top + 9),
      Offset(rect.right - 4, rect.top + 9),
      border,
    );
  }
}
