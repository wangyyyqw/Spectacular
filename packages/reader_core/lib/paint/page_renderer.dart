import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../css/computed_style.dart';
import '../layout/paginator.dart';
import '../layout/text_layout.dart';
import '../text/justify.dart';
import 'background_image.dart';

/// 按页绘制文本与背景。
class PagePainter {
  /// 创建绘制器。
  const PagePainter({
    this.background = const Color(0xFFFFFFFF),
    this.imageLookup,
  });

  /// 页面背景色。
  final Color background;

  /// 背景图按 URL 取图的回调；返回 null 表示当前没有可用图片（跳过绘制）。
  ///
  /// 图片解码与缓存属于调用方的资源层职责：绘制过程中不碰网络与文件 IO，
  /// 也不在每帧重复解码。默认 null 时 `background-image` 一律不绘制，
  /// 既有页面像素保持不变。
  final ui.Image? Function(String url)? imageLookup;

  /// 绘制一页。
  ///
  /// 行的水平位置由布局阶段按 text-align 算好（[LineBox.offsetX]）；
  /// 行内样式取自 [TextLayoutResult.runs]（混排字号、行内元素）；
  /// justify 行把余量按间隙分摊到左侧字符的字距上（§8.4）。
  void paint(Canvas canvas, PageContent page, {required Size pageSize}) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
      Paint()..color = background,
    );

    var y = page.topPadding;
    for (final slice in page.slices) {
      final style = slice.block.style ?? ComputedStyle(<String, String>{});
      final textStyle = TextLayoutEngine.textStyleFor(style);
      final startsBlock = slice.startLine == 0;
      final endsBlock = slice.endLine == slice.block.layout.lineCount;
      // 几何全部来自分页切片（P2-14 补全）：段前/段后间距与首尾内缩已计入
      // slice.height，绘制与命中不再各算一套。
      final leading = slice.leadingExtent;
      final leftInset = slice.leftInset;
      // 跨页块只画本页可见的行（§60.8）：裁剪后即使字号/行高有浮点误差，
      // 墨迹也不会越到下一块或下一页。
      canvas.save();
      canvas.clipRect(slice.clipRect(y, pageSize.width));
      // visibility: hidden / collapse 只保留布局空间，不画背景、边框与文字（P2-15）。
      final hidden = style.visibility != CssVisibility.visible;
      // 背景与边框铺满切片盒子（含首尾内缩）。
      final box = Rect.fromLTWH(0, y, pageSize.width, slice.height);
      if (!hidden) {
        _paintBackground(
          canvas,
          box,
          style,
          startsBlock: startsBlock,
          endsBlock: endsBlock,
        );
        _paintBorders(
          canvas,
          box,
          style,
          startsBlock: startsBlock,
          endsBlock: endsBlock,
        );
      }
      var lineY = y + leading;
      for (
        var lineIndex = slice.startLine;
        lineIndex < slice.endLine;
        lineIndex++
      ) {
        final line = slice.block.layout.lines[lineIndex];
        final lineText = slice.block.layout.text.substring(
          line.start,
          line.end,
        );
        if (!hidden && lineText.isNotEmpty) {
          final painter = TextPainter(
            text: _lineSpan(slice.block.layout, line, textStyle),
            textDirection: TextDirection.ltr,
          )..layout();
          painter.paint(canvas, Offset(line.offsetX + leftInset, lineY));
        }
        lineY += line.height;
      }
      canvas.restore();
      y += slice.height;
    }
  }

  /// 画块背景：跨页切片只在块真正开始/结束时带上下圆角。
  ///
  /// 顺序与阅微 `CSSBackgroundNode.draw()` 一致：先铺背景色，再画背景图。
  /// 背景图按 CSS 默认（左上、原生尺寸、repeat）平铺，并裁剪到块盒子；
  /// 有圆角时按同一圆角矩形裁剪，圆角外不露图。
  void _paintBackground(
    Canvas canvas,
    Rect box,
    ComputedStyle style, {
    required bool startsBlock,
    required bool endsBlock,
  }) {
    final rounded = RRect.fromRectAndCorners(
      box,
      topLeft: Radius.circular(startsBlock ? style.borders.topLeftRadius : 0),
      topRight: Radius.circular(startsBlock ? style.borders.topRightRadius : 0),
      bottomRight: Radius.circular(
        endsBlock ? style.borders.bottomRightRadius : 0,
      ),
      bottomLeft: Radius.circular(
        endsBlock ? style.borders.bottomLeftRadius : 0,
      ),
    );
    if (style.backgroundColor.a != 0) {
      canvas.drawRRect(rounded, Paint()..color = style.backgroundColor);
    }
    final image = _resolveBackgroundImage(style);
    if (image == null) {
      return;
    }
    final roundedCorners =
        rounded.tlRadiusX > 0 ||
        rounded.trRadiusX > 0 ||
        rounded.brRadiusX > 0 ||
        rounded.blRadiusX > 0;
    canvas.save();
    if (roundedCorners) {
      canvas.clipRRect(rounded);
    } else {
      canvas.clipRect(box);
    }
    paintTiledBackgroundImage(canvas, image, box);
    canvas.restore();
  }

  /// 取块背景图：未声明 `background-image` 或调用方暂无该图时返回 null。
  ///
  /// 图片解码与缓存由调用方的资源层负责，这里只做一次查表，不做 IO。
  ui.Image? _resolveBackgroundImage(ComputedStyle style) {
    final url = style.backgroundImage;
    final lookup = imageLookup;
    if (url == null || lookup == null) {
      return null;
    }
    return lookup(url);
  }

  /// 画四边边框：贴合块边界，不改变行布局（§65 边框不侵占行布局）。
  void _paintBorders(
    Canvas canvas,
    Rect box,
    ComputedStyle style, {
    required bool startsBlock,
    required bool endsBlock,
  }) {
    final borders = style.borders;
    if (!borders.hasBorder) {
      return;
    }
    // 四边一致且实线：用整框描边，圆角生效（与阅微整框描边路径一致）。
    if (borders.isUniform && borders.top.style == CssBorderStyle.solid) {
      final half = borders.top.width / 2;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          box.deflate(half),
          topLeft: Radius.circular(startsBlock ? borders.topLeftRadius : 0),
          topRight: Radius.circular(startsBlock ? borders.topRightRadius : 0),
          bottomRight: Radius.circular(
            endsBlock ? borders.bottomRightRadius : 0,
          ),
          bottomLeft: Radius.circular(endsBlock ? borders.bottomLeftRadius : 0),
        ),
        Paint()
          ..color = borders.top.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = borders.top.width,
      );
      return;
    }
    // 分边绘制：宽度/线型/颜色不同时按边画，圆角只在圆角样本的整框路径里用。
    if (startsBlock) {
      final inset = borders.top.width / 2;
      _paintSide(
        canvas,
        borders.top,
        Offset(box.left, box.top + inset),
        Offset(box.right, box.top + inset),
      );
    }
    if (endsBlock) {
      final inset = borders.bottom.width / 2;
      _paintSide(
        canvas,
        borders.bottom,
        Offset(box.left, box.bottom - inset),
        Offset(box.right, box.bottom - inset),
      );
    }
    _paintSide(
      canvas,
      borders.left,
      Offset(box.left + borders.left.width / 2, box.top),
      Offset(box.left + borders.left.width / 2, box.bottom),
    );
    _paintSide(
      canvas,
      borders.right,
      Offset(box.right - borders.right.width / 2, box.top),
      Offset(box.right - borders.right.width / 2, box.bottom),
    );
  }

  /// 画一条边：实线/虚线/点线/双线。
  void _paintSide(Canvas canvas, CssBorderSide side, Offset start, Offset end) {
    if (!side.isVisible) {
      return;
    }
    final paint = Paint()
      ..color = side.color
      ..strokeWidth = side.width
      ..strokeCap = StrokeCap.butt;
    switch (side.style) {
      case CssBorderStyle.solid:
        canvas.drawLine(start, end, paint);
      case CssBorderStyle.dashed:
        _paintDashes(canvas, start, end, paint, side.width * 3, side.width * 2);
      case CssBorderStyle.dotted:
        _paintDashes(
          canvas,
          start,
          end,
          paint..strokeCap = StrokeCap.round,
          side.width,
          side.width * 3,
        );
      case CssBorderStyle.double:
        final offset = side.width / 3;
        final third = side.width / 3;
        final normal = Offset(end.dy - start.dy, start.dx - end.dx);
        final length = normal.distance;
        final unit = length == 0 ? Offset.zero : normal / length;
        final inner = Paint()
          ..color = side.color
          ..strokeWidth = third
          ..strokeCap = StrokeCap.butt;
        canvas.drawLine(start + unit * offset, end + unit * offset, inner);
        canvas.drawLine(start - unit * offset, end - unit * offset, inner);
      case CssBorderStyle.none:
        break;
    }
  }

  /// 沿线段画虚线/点线（阅微 straight 边用 dashPathEffect，这里手工切段）。
  void _paintDashes(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
    double dash,
    double gap,
  ) {
    final total = (end - start).distance;
    if (total <= 0 || dash <= 0) {
      return;
    }
    final direction = (end - start) / total;
    var position = 0.0;
    while (position < total) {
      final segmentEnd = math.min(position + dash, total);
      canvas.drawLine(
        start + direction * position,
        start + direction * segmentEnd,
        paint,
      );
      position = segmentEnd + gap;
    }
  }

  /// 组装一行的 span：行内样式区间 + justify 间隙字距。
  InlineSpan _lineSpan(
    TextLayoutResult layout,
    LineBox line,
    TextStyle baseStyle,
  ) {
    final lineText = layout.text.substring(line.start, line.end);
    final runs = layout.runs;
    final gaps = line.justifyExtra > 0
        ? justifyGapOffsets(lineText)
        : const <int>[];
    if (runs.isEmpty && gaps.isEmpty) {
      return TextSpan(text: lineText, style: baseStyle);
    }
    if (gaps.isEmpty) {
      return TextSpan(
        style: baseStyle,
        children: buildStyledSpans(
          text: layout.text,
          start: line.start,
          end: line.end,
          runs: runs,
          baseStyle: baseStyle,
          styleOf: (runStyle) => TextLayoutEngine.textStyleFor(runStyle),
        ),
      );
    }
    // justify 行逐字符铺开，样式区间与间隙字距一起处理。
    final spacing = line.justifyExtra / gaps.length;
    final gapStarts = gaps.toSet();
    final resolved = <int, TextStyle>{};
    TextStyle styleAt(int offset) {
      for (var i = 0; i < runs.length; i++) {
        final run = runs[i];
        if (offset >= run.start && offset < run.end) {
          return resolved[i] ??= TextLayoutEngine.textStyleFor(run.style);
        }
      }
      return baseStyle;
    }

    final children = <InlineSpan>[];
    var offset = 0;
    for (final rune in lineText.runes) {
      final char = String.fromCharCode(rune);
      final style = styleAt(line.start + offset);
      children.add(
        TextSpan(
          text: char,
          style: gapStarts.contains(offset)
              ? style.copyWith(
                  letterSpacing: (style.letterSpacing ?? 0) + spacing,
                )
              : style,
        ),
      );
      offset += char.length;
    }
    return TextSpan(style: baseStyle, children: children);
  }
}
