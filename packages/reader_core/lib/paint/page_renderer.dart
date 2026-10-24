import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../css/computed_style.dart';
import '../layout/paginator.dart';
import '../layout/text_layout.dart';
import 'background_image.dart';
import 'line_spans.dart';
import 'paragraph_cache.dart';

/// 页面绘制阶段（P2-29）：顺序固定为
/// 背景 → 块背景 → 块边框 → 文本 → 装饰 → 选区。
enum PagePaintPhase {
  /// 页面底色与背景。
  background,

  /// 块背景（含背景图）。
  blockBackground,

  /// 块边框。
  blockBorder,

  /// 正文文本。
  text,

  /// 装饰（着重号等附加墨迹）。
  decoration,

  /// 选区高亮，覆盖在所有内容之上。
  selection,
}

/// 页内选区的一段：切片序号 + 块内字符范围（`[start, end)`）。
class SelectedTextRange {
  /// 创建选区段。
  const SelectedTextRange({
    required this.sliceIndex,
    required this.start,
    required this.end,
  });

  /// 页内切片序号。
  final int sliceIndex;

  /// 块内起始字符偏移。
  final int start;

  /// 块内结束字符偏移（不含）。
  final int end;
}

/// 页内选区（P2-29）：按切片序号定位，绘制在文本与装饰之上。
class PageSelection {
  /// 创建选区。
  const PageSelection(this.ranges);

  /// 选区段。
  final List<SelectedTextRange> ranges;
}

/// 按页绘制文本与背景。
class PagePainter {
  /// 列表标记 gutter（P3-23）：标记距文本左缘的距离（UA li margin-left
  /// 40px 的内半区）。
  static const double markerGutter = 20;

  /// 创建绘制器。
  const PagePainter({
    this.background = const Color(0xFFFFFFFF),
    this.imageLookup,
    this.textColor,
    this.selection,
    this.selectionColor = const Color(0x330066FF),
    this.onPhase,
    this.paragraphCache,
  });

  /// 页面背景色。
  final Color background;

  /// 背景图按 URL 取图的回调；返回 null 表示当前没有可用图片（跳过绘制）。
  ///
  /// 图片解码与缓存属于调用方的资源层职责：绘制过程中不碰网络与文件 IO，
  /// 也不在每帧重复解码。默认 null 时 `background-image` 一律不绘制，
  /// 既有页面像素保持不变。
  final ui.Image? Function(String url)? imageLookup;

  /// 正文颜色覆盖（主题用）：只改绘制颜色，不影响布局与分页（P2-23）。
  final Color? textColor;

  /// 页内选区（可选）：最后绘制，覆盖文本与装饰（P2-29）。
  final PageSelection? selection;

  /// 选区高亮色。
  final Color selectionColor;

  /// 阶段回调（测试用）：每个绘制阶段开始时触发一次。
  final void Function(PagePaintPhase phase)? onPhase;

  /// 行排版缓存（可选）：按页/行缓存 TextPainter，重排时由调用方清空（P2-30）。
  final ParagraphCache? paragraphCache;

  /// 绘制一页。
  ///
  /// 行的水平位置由布局阶段按 text-align 算好（[LineBox.offsetX]）；
  /// 行内样式取自 [TextLayoutResult.runs]（混排字号、行内元素）；
  /// justify 行把余量按间隙分摊到左侧字符的字距上（§8.4）。
  void paint(Canvas canvas, PageContent page, {required Size pageSize}) {
    final geometries = _sliceGeometries(page, pageSize);

    _notifyPhase(PagePaintPhase.background);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
      Paint()..color = background,
    );

    _notifyPhase(PagePaintPhase.blockBackground);
    for (final geometry in geometries) {
      if (geometry.hidden) {
        continue;
      }
      // 阴影可溢出块外：画在块裁剪之外（自带透明层），先影后景。
      _withOpacity(canvas, geometry, () {
        _paintBoxShadow(canvas, geometry);
      });
      canvas.save();
      geometry.clip(canvas);
      _withOpacity(canvas, geometry, () {
        _paintBackground(
          canvas,
          geometry.box,
          geometry.style,
          startsBlock: geometry.startsBlock,
          endsBlock: geometry.endsBlock,
        );
      });
      canvas.restore();
    }

    _notifyPhase(PagePaintPhase.blockBorder);
    for (final geometry in geometries) {
      if (geometry.hidden) {
        continue;
      }
      canvas.save();
      geometry.clip(canvas);
      _withOpacity(canvas, geometry, () {
        _paintBorders(
          canvas,
          geometry.box,
          geometry.style,
          startsBlock: geometry.startsBlock,
          endsBlock: geometry.endsBlock,
        );
      });
      canvas.restore();
    }

    _notifyPhase(PagePaintPhase.text);
    for (var sliceIndex = 0; sliceIndex < geometries.length; sliceIndex++) {
      final geometry = geometries[sliceIndex];
      if (geometry.hidden) {
        continue;
      }
      canvas.save();
      geometry.clip(canvas);
      _withOpacity(canvas, geometry, () {
        final layout = geometry.slice.block.layout;
        var lineY = geometry.y + geometry.leading;
        for (
          var lineIndex = geometry.slice.startLine;
          lineIndex < geometry.slice.endLine;
          lineIndex++
        ) {
          final line = layout.lines[lineIndex];
          final lineText = layout.text.substring(line.start, line.end);
          if (lineText.isNotEmpty) {
            final x = line.offsetX + geometry.leftInset;
            // 列表标记（P3-23）：块首行左侧 gutter 内画标记文本。
            if (lineIndex == 0 &&
                geometry.slice.block.listMarker != null) {
              _paintListMarker(
                canvas,
                geometry,
                marker: geometry.slice.block.listMarker!,
                textX: x,
                lineTop: lineY,
                lineHeight: line.height,
              );
            }
            if (_needsEllipsis(geometry, line)) {
              _paintEllipsizedLine(
                canvas,
                page,
                sliceIndex,
                layout,
                line,
                lineText,
                geometry,
                x,
                lineY,
              );
            } else {
              _paintLineText(
                canvas,
                _linePainterFor(
                  page,
                  sliceIndex,
                  lineIndex,
                  layout,
                  line,
                  geometry.textStyle,
                  punctCompression: geometry.punctCompression,
                ),
                lineText,
                _lineRuns(layout, line),
                geometry.textStyle,
                x,
                lineY,
              );
            }
          }
          lineY += line.height;
        }
      });
      canvas.restore();
    }

    _notifyPhase(PagePaintPhase.decoration);
    for (var sliceIndex = 0; sliceIndex < geometries.length; sliceIndex++) {
      final geometry = geometries[sliceIndex];
      if (geometry.hidden ||
          geometry.style.textEmphasisStyle == CssTextEmphasisStyle.none) {
        continue;
      }
      canvas.save();
      geometry.clip(canvas);
      final layout = geometry.slice.block.layout;
      var lineY = geometry.y + geometry.leading;
      for (
        var lineIndex = geometry.slice.startLine;
        lineIndex < geometry.slice.endLine;
        lineIndex++
      ) {
        final line = layout.lines[lineIndex];
        final lineText = layout.text.substring(line.start, line.end);
        if (lineText.isNotEmpty) {
          _paintLineEmphasis(
            canvas,
            _linePainterFor(
              page,
              sliceIndex,
              lineIndex,
              layout,
              line,
              geometry.textStyle,
              punctCompression: geometry.punctCompression,
            ),
            lineText,
            geometry.style,
            line.offsetX + geometry.leftInset,
            lineY,
          );
        }
        lineY += line.height;
      }
      canvas.restore();
    }

    _notifyPhase(PagePaintPhase.selection);
    final selection = this.selection;
    if (selection != null) {
      _paintSelection(canvas, page, geometries, selection);
    }
  }

  void _notifyPhase(PagePaintPhase phase) => onPhase?.call(phase);

  /// 预计算每片切片的几何与样式（P2-29：各阶段共用同一份坐标）。
  List<_SliceGeometry> _sliceGeometries(PageContent page, Size pageSize) {
    // 上下标的基线偏移会超出切片矩形：统计本页最大上下偏移，放宽裁剪。
    var upExtent = 0.0;
    var downExtent = 0.0;
    for (final slice in page.slices) {
      for (final run in slice.block.layout.runs) {
        if (run.baselineShift < 0) {
          upExtent = math.max(upExtent, -run.baselineShift);
        } else if (run.baselineShift > 0) {
          downExtent = math.max(downExtent, run.baselineShift);
        }
      }
    }
    final geometries = <_SliceGeometry>[];
    var y = page.topPadding;
    for (final slice in page.slices) {
      final style = slice.block.style ?? ComputedStyle(<String, String>{});
      geometries.add(
        _SliceGeometry(
          slice: slice,
          y: y,
          style: style,
          textStyle: TextLayoutEngine.textStyleFor(style),
          startsBlock: slice.startLine == 0,
          endsBlock: slice.endLine == slice.block.layout.lineCount,
          hidden: style.visibility != CssVisibility.visible,
          leading: slice.leadingExtent,
          leftInset: slice.leftInset,
          upExtent: upExtent,
          downExtent: downExtent,
          pageWidth: pageSize.width,
        ),
      );
      y += slice.height;
    }
    return geometries;
  }

  /// 画选区（P2-29）：按切片序号 + 块内字符范围取排版盒，最后统一覆盖。
  void _paintSelection(
    Canvas canvas,
    PageContent page,
    List<_SliceGeometry> geometries,
    PageSelection selection,
  ) {
    final paint = Paint()..color = selectionColor;
    for (final range in selection.ranges) {
      if (range.sliceIndex < 0 || range.sliceIndex >= geometries.length) {
        continue;
      }
      final geometry = geometries[range.sliceIndex];
      if (geometry.hidden || range.end <= range.start) {
        continue;
      }
      final layout = geometry.slice.block.layout;
      var lineY = geometry.y + geometry.leading;
      for (
        var lineIndex = geometry.slice.startLine;
        lineIndex < geometry.slice.endLine;
        lineIndex++
      ) {
        final line = layout.lines[lineIndex];
        final start = math.max(range.start, line.start);
        final end = math.min(range.end, line.end);
        if (end > start) {
          final painter = _linePainterFor(
            page,
            range.sliceIndex,
            lineIndex,
            layout,
            line,
            geometry.textStyle,
            punctCompression: geometry.punctCompression,
          textAutospace: geometry.textAutospace,
          );
          final boxes = painter.getBoxesForSelection(
            TextSelection(
              baseOffset: start - line.start,
              extentOffset: end - line.start,
            ),
          );
          final x = line.offsetX + geometry.leftInset;
          for (final box in boxes) {
            canvas.drawRect(
              Rect.fromLTWH(
                x + box.left,
                lineY + box.top,
                box.right - box.left,
                box.bottom - box.top,
              ),
              paint,
            );
          }
        }
        lineY += line.height;
      }
    }
  }

  /// 元素不透明度（P2-37）：opacity < 1 时把本几何的绘制收进透明层，
  /// 块背景/边框/文本三层各自包一层（层内内容互不穿透）。
  void _withOpacity(
    Canvas canvas,
    _SliceGeometry geometry,
    void Function() body,
  ) {
    final opacity = geometry.style.opacity;
    if (opacity >= 1) {
      body();
      return;
    }
    canvas.saveLayer(
      geometry.box.inflate(64),
      Paint()..color = Color.fromRGBO(255, 255, 255, opacity),
    );
    body();
    canvas.restore();
  }

  /// 块阴影（P2-37 限定）：整块落在一页时画偏移投影（先影后景，背景
  /// 覆盖重叠部分）；blur/spread/inset 不支持；跨页切片不重复投影。
  void _paintBoxShadow(Canvas canvas, _SliceGeometry geometry) {
    final shadow = geometry.style.boxShadow;
    if (shadow == null || !geometry.startsBlock || !geometry.endsBlock) {
      return;
    }
    canvas.drawRect(
      geometry.box.translate(shadow.offsetX, shadow.offsetY),
      Paint()..color = shadow.color,
    );
  }

  /// 是否需要省略号截断（P2-37）：ellipsis 模式下行宽超出块内容区。
  bool _needsEllipsis(_SliceGeometry geometry, LineBox line) {
    if (geometry.style.textOverflow != CssTextOverflow.ellipsis) {
      return false;
    }
    final available =
        geometry.box.width - geometry.leftInset - line.offsetX;
    return line.width > available + 0.5;
  }

  /// 省略号截断绘制（P2-37）：裁掉超出部分，右缘补「…」。
  /// 布局结果不改（CFI/选区仍按原文），截断只在绘制层发生。
  /// 列表标记绘制（P3-23）：块首行文本左缘再往左一个 gutter（UA li
  /// margin-left 40px 的内半区），垂直居中于首行。
  void _paintListMarker(
    Canvas canvas,
    _SliceGeometry geometry, {
    required String marker,
    required double textX,
    required double lineTop,
    required double lineHeight,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: marker, style: geometry.textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final x = math.max(
      geometry.box.left + 1,
      geometry.box.left + textX - markerGutter,
    );
    painter.paint(
      canvas,
      Offset(
        x,
        lineTop + (lineHeight - painter.height) / 2,
      ),
    );
    painter.dispose();
  }

  void _paintEllipsizedLine(
    Canvas canvas,
    PageContent page,
    int sliceIndex,
    TextLayoutResult layout,
    LineBox line,
    String lineText,
    _SliceGeometry geometry,
    double x,
    double y,
  ) {
    final available = geometry.box.width - geometry.leftInset - line.offsetX;
    // 省略号占位后，文本可见区再收窄一个省略号宽。
    final ellipsis = TextPainter(
      text: TextSpan(text: '…', style: geometry.textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final visible = available - ellipsis.width;
    if (visible <= 0) {
      ellipsis.paint(
        canvas,
        Offset(geometry.box.right - ellipsis.width, y),
      );
      ellipsis.dispose();
      return;
    }
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(geometry.box.left + x, y, visible, line.height),
    );
    _paintLineText(
      canvas,
      _linePainterFor(
        page,
        sliceIndex,
        geometry.slice.startLine,
        layout,
        line,
        geometry.textStyle,
        punctCompression: geometry.punctCompression,
      ),
      lineText,
      _lineRuns(layout, line),
      geometry.textStyle,
      x,
      y,
    );
    canvas.restore();
    ellipsis.paint(canvas, Offset(geometry.box.left + x + visible, y));
    ellipsis.dispose();
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
      // 背景色按 background-clip 裁剪区域绘制（P3：origin/clip 语义）。
      canvas.save();
      canvas.clipRect(_backgroundClipRect(box, style));
      canvas.drawRRect(rounded, Paint()..color = style.backgroundColor);
      canvas.restore();
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
    canvas.clipRect(_backgroundClipRect(box, style));
    if (roundedCorners) {
      canvas.clipRRect(rounded);
    }
    paintBackgroundImage(
      canvas,
      image,
      _backgroundOriginRect(box, style),
      repeat: style.backgroundRepeat,
      size: style.backgroundSize,
      position: style.backgroundPosition,
    );
    canvas.restore();
  }

  /// 背景裁剪区域：border-box / padding-box / content-box。
  ///
  /// `background-clip: text` 需要按文字轮廓裁剪，当前按 padding-box 降级。
  Rect _backgroundClipRect(Rect box, ComputedStyle style) {
    switch (style.backgroundClip) {
      case CssBackgroundClip.borderBox:
        return box;
      case CssBackgroundClip.text:
      case CssBackgroundClip.paddingBox:
        return _deflateByBox(box, style, includePadding: false);
      case CssBackgroundClip.contentBox:
        return _deflateByBox(box, style, includePadding: true);
    }
  }

  /// 背景定位区域（background-origin）：决定 size/position 的解算基准。
  Rect _backgroundOriginRect(Rect box, ComputedStyle style) {
    switch (style.backgroundOrigin) {
      case CssBackgroundOrigin.borderBox:
        return box;
      case CssBackgroundOrigin.paddingBox:
        return _deflateByBox(box, style, includePadding: false);
      case CssBackgroundOrigin.contentBox:
        return _deflateByBox(box, style, includePadding: true);
    }
  }

  Rect _deflateByBox(
    Rect box,
    ComputedStyle style, {
    required bool includePadding,
  }) {
    final padding = includePadding ? style.padding : CssEdges.zero;
    return Rect.fromLTRB(
      box.left + style.borders.left.width + padding.left,
      box.top + style.borders.top.width + padding.top,
      box.right - style.borders.right.width - padding.right,
      box.bottom - style.borders.bottom.width - padding.bottom,
    );
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
    // 四边一致且实线：整块（首尾都在本页）用整框描边，圆角生效
    //（与阅微整框描边路径一致）。
    if (borders.isUniform && borders.top.style == CssBorderStyle.solid) {
      if (startsBlock && endsBlock) {
        final half = borders.top.width / 2;
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            box.deflate(half),
            topLeft: Radius.circular(borders.topLeftRadius),
            topRight: Radius.circular(borders.topRightRadius),
            bottomRight: Radius.circular(borders.bottomRightRadius),
            bottomLeft: Radius.circular(borders.bottomLeftRadius),
          ),
          Paint()
            ..color = borders.top.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = borders.top.width,
        );
        return;
      }
      // 跨页切片（P3-24，CSS box-decoration-break: slice 语义）：左右
      // 边框全长续绘，顶边只在块首切片、底边只在块尾切片——切片边界
      // 处不画水平边（圆角只在真实首尾出现）。
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

  /// 取一行的排版结果：有段落缓存时复用（P2-30），否则新建并布局。
  TextPainter _linePainterFor(
    PageContent page,
    int sliceIndex,
    int lineIndex,
    TextLayoutResult layout,
    LineBox line,
    TextStyle baseStyle, {
    bool punctCompression = false,
    bool textAutospace = false,
  }) {
    TextPainter build() => TextPainter(
      text: _lineSpan(
        layout,
        line,
        baseStyle,
        punctCompression: punctCompression,
        textAutospace: textAutospace,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final cache = paragraphCache;
    if (cache == null) {
      return build();
    }
    final key =
        '${page.spineIndex}:${page.pageIndex}:$sliceIndex:$lineIndex:'
        '${baseStyle.fontSize}:${baseStyle.height}:'
        '${baseStyle.letterSpacing}:${baseStyle.wordSpacing}:'
        '${baseStyle.color?.toARGB32()}:'
        '${line.justifyExtra.toStringAsFixed(3)}';
    return cache.obtain(key, build: build);
  }

  /// 画一行：有上下标（基线偏移）时按段分别绘制，其余情况整行一次绘制。
  ///
  /// 与阅微 `BaselineShift` 一致：偏移段在正常基线基础上整体上下移动
  /// （super −0.4em、sub +0.15em），行高与行宽不受影响。
  void _paintLineText(
    Canvas canvas,
    TextPainter painter,
    String lineText,
    List<_LineRun> runs,
    TextStyle baseStyle,
    double x,
    double y,
  ) {
    if (lineText.isEmpty) {
      return;
    }
    final hasShift = runs.any((run) => run.baselineShift != 0);
    if (!hasShift) {
      painter.paint(canvas, Offset(x, y));
      return;
    }
    // 上下标：用整行的排版结果取出每段的 x，再按段的基线偏移绘制。
    for (final segment in _lineSegments(lineText.length, runs)) {
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: segment.start, extentOffset: segment.end),
      );
      if (boxes.isEmpty) {
        continue;
      }
      final segmentPainter = TextPainter(
        text: TextSpan(
          text: lineText.substring(segment.start, segment.end),
          style: segment.style == null
              ? baseStyle
              : (textColor == null
                    ? TextLayoutEngine.textStyleFor(segment.style!)
                    : TextLayoutEngine.textStyleFor(segment.style!)
                          .copyWith(color: textColor)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      segmentPainter.paint(
        canvas,
        Offset(x + boxes.first.left, y + segment.baselineShift),
      );
    }
  }

  /// 画一行着重号（装饰阶段，P2-29）。
  void _paintLineEmphasis(
    Canvas canvas,
    TextPainter painter,
    String lineText,
    ComputedStyle style,
    double x,
    double y,
  ) {
    if (lineText.isEmpty ||
        style.textEmphasisStyle == CssTextEmphasisStyle.none) {
      return;
    }
    _paintEmphasis(canvas, lineText, style, painter, x, y);
  }

  /// 画着重号（P2-17）：按字符取排版盒，在上/下方画实心或空心点。
  ///
  /// 参考阅微 `TextEmphasisDisplay`：字号取 `fontSize / 2` 区域，位置 over/under，
  /// 颜色缺省跟随文字颜色。
  void _paintEmphasis(
    Canvas canvas,
    String lineText,
    ComputedStyle style,
    TextPainter painter,
    double x,
    double y,
  ) {
    final emphasis = style.textEmphasisStyle;
    if (emphasis == CssTextEmphasisStyle.none) {
      return;
    }
    final radius = math.max(1.0, style.fontSize * 0.08);
    final paint = Paint()
      ..color = style.textEmphasisColor ?? textColor ?? style.color;
    if (emphasis == CssTextEmphasisStyle.open) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, style.fontSize * 0.05);
    }
    for (var i = 0; i < lineText.length; i++) {
      if (lineText[i].trim().isEmpty) {
        continue;
      }
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1),
      );
      if (boxes.isEmpty) {
        continue;
      }
      final box = boxes.first;
      final centerY = style.textEmphasisPosition == CssTextEmphasisPosition.over
          ? y + box.top + style.fontSize * 0.15
          : y + box.bottom - style.fontSize * 0.15;
      canvas.drawCircle(
        Offset(x + (box.left + box.right) / 2, centerY),
        radius,
        paint,
      );
    }
  }

  /// 取与本行相交的样式区间（行内局部坐标）。
  List<_LineRun> _lineRuns(TextLayoutResult layout, LineBox line) {
    final runs = <_LineRun>[];
    for (final run in layout.runs) {
      final start = math.max(run.start, line.start);
      final end = math.min(run.end, line.end);
      if (end > start) {
        runs.add(
          _LineRun(
            start - line.start,
            end - line.start,
            run.style,
            run.baselineShift,
          ),
        );
      }
    }
    return runs;
  }

  /// 把行文本按样式区间切成连续段，区间外的空隙用基础样式。
  List<_LineSegment> _lineSegments(int length, List<_LineRun> runs) {
    final segments = <_LineSegment>[];
    var cursor = 0;
    for (final run in runs) {
      if (run.start > cursor) {
        segments.add(_LineSegment(cursor, run.start, null, 0));
      }
      final start = math.max(run.start, cursor);
      if (run.end > start) {
        segments.add(
          _LineSegment(start, run.end, run.style, run.baselineShift),
        );
      }
      cursor = math.max(cursor, run.end);
    }
    if (cursor < length) {
      segments.add(_LineSegment(cursor, length, null, 0));
    }
    return segments;
  }

  /// 组装一行的 span：行内样式区间 + justify 间隙字距（实现见 line_spans.dart）。
  InlineSpan _lineSpan(
    TextLayoutResult layout,
    LineBox line,
    TextStyle baseStyle, {
    bool punctCompression = false,
    bool textAutospace = false,
  }) => buildLineSpan(
    layout: layout,
    line: line,
    baseStyle: baseStyle,
    textColor: textColor,
    punctCompression: punctCompression,
    textAutospace: textAutospace,
  );
}

/// 行内一段样式区间（行内局部坐标，带基线偏移）。
class _LineRun {
  const _LineRun(this.start, this.end, this.style, this.baselineShift);

  final int start;
  final int end;
  final ComputedStyle style;
  final double baselineShift;
}

/// 行内绘制段：样式为 null 时用基础样式。
class _LineSegment {
  const _LineSegment(this.start, this.end, this.style, this.baselineShift);

  final int start;
  final int end;
  final ComputedStyle? style;
  final double baselineShift;
}

/// 一片切片在本页的几何与样式（P2-29：各绘制阶段共用同一份坐标）。
class _SliceGeometry {
  _SliceGeometry({
    required this.slice,
    required this.y,
    required this.style,
    required this.textStyle,
    required this.startsBlock,
    required this.endsBlock,
    required this.hidden,
    required this.leading,
    required this.leftInset,
    required this.upExtent,
    required this.downExtent,
    required this.pageWidth,
  });

  final PageBlockSlice slice;
  final double y;
  final ComputedStyle style;
  final TextStyle textStyle;

  /// 标点挤压开关（P7-19，源自 style.textSpacingTrim）。
  bool get punctCompression =>
      style.textSpacingTrim == CssTextSpacingTrim.trimAdjacent;

  /// 中西文自动间距开关（P7-20，源自 style.textAutospace）。
  bool get textAutospace =>
      style.textAutospace == CssTextAutospace.normal;

  final bool startsBlock;
  final bool endsBlock;
  final bool hidden;
  final double leading;
  final double leftInset;
  final double upExtent;
  final double downExtent;
  final double pageWidth;

  /// 背景/边框盒子（含首尾内缩）。
  Rect get box => Rect.fromLTWH(0, y, pageWidth, slice.height);

  /// 按切片裁剪；上下标越界时放宽上下边。
  void clip(Canvas canvas) {
    final clip = slice.clipRect(y, pageWidth);
    canvas.clipRect(
      Rect.fromLTRB(
        clip.left,
        clip.top - upExtent,
        clip.right,
        clip.bottom + downExtent,
      ),
    );
  }
}
