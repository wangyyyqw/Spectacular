import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../css/computed_style.dart';
import '../layout/box_model.dart';
import '../layout/line_breaker.dart';
import '../layout/image_gallery.dart';
import '../layout/paginator.dart';
import '../layout/table_layout.dart';
import '../layout/text_spacing.dart';
import '../text/reader_text_overlay.dart';
import 'background_image.dart';
import 'background_tiles.dart';
import 'line_spans.dart';
import 'paragraph_cache.dart';
import 'text_emphasis.dart';

/// 页面与普通流盒背景先绘制，再绘制内容和独立合成组，最后绘制选区。
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
    this.pageBackgroundImage,
    this.pageBackgroundImageTint,
    this.pageBackgroundImageCover = false,
    this.pageBackgroundImageOpacity = 1,
    this.imageLookup,
    this.listMarkerImageOf,
    this.textColor,
    this.inkMode = false,
    this.selection,
    this.selectionColor = const Color(0x330066FF),
    this.onPhase,
    this.paragraphCache,
    this.textOverlays = const [],
    this.beforeBlockText,
    this.galleryFrameOf,
    this.galleryPositionOf,
  });

  /// 页面背景色。
  final Color background;

  /// 整页背景纹理（P4-22）：平铺绘制在背景色之上、正文之下。
  ///
  /// 只影响绘制层，不进入排版指纹——换背景图不触发重排（§31.4）。
  final ui.Image? pageBackgroundImage;

  /// 背景纹理混色；null 表示保留纹理原色。
  final Color? pageBackgroundImageTint;

  /// 用户照片居中裁切铺满页面；内置纹理使用平铺。
  final bool pageBackgroundImageCover;

  /// 背景图可见强度，弱化后仍由主题底色保证正文可读。
  final double pageBackgroundImageOpacity;

  /// 背景图按 URL 取图的回调；返回 null 表示当前没有可用图片（跳过绘制）。
  ///
  /// 图片解码与缓存属于调用方的资源层职责：绘制过程中不碰网络与文件 IO，
  /// 也不在每帧重复解码。默认 null 时 `background-image` 一律不绘制，
  /// 既有页面像素保持不变。
  final ui.Image? Function(String url)? imageLookup;

  /// 列表标记图片（W6）：按块解析 `list-style-image` 的 url；null/空串表示
  /// 该块无标记图片，退回 [PageBlock.listMarker] 的文字/几何标记。
  ///
  /// 章节源接线后传入（`(block) => block.listMarkerImage`）；绘制层只做绘制，
  /// 图片解码与缓存仍由 [imageLookup] 背后的资源层负责。
  final String? Function(PageBlock block)? listMarkerImageOf;

  /// 正文颜色覆盖（主题用）：只改绘制颜色，不影响布局与分页（P2-23）。
  final Color? textColor;

  /// 墨水屏模式：把正文文字与行内标记压成纯黑/纯白。
  ///
  /// 与 [textColor] 不同，这项会覆盖作者显式声明的颜色；按所在背景的
  /// 明度选择黑色或白色，避免深色标记上的浅色字被压成黑字。
  final bool inkMode;

  /// 页内选区（可选）：最后绘制，覆盖文本与装饰（P2-29）。
  final PageSelection? selection;

  /// 选区高亮色。
  final Color selectionColor;

  /// 阶段回调（测试用）：块内阶段随每个元素重复，页面背景和选区各触发一次。
  final void Function(PagePaintPhase phase)? onPhase;

  /// 行排版缓存（可选）：按页/行缓存 TextPainter，重排时由调用方清空（P2-30）。
  final ParagraphCache? paragraphCache;

  /// 原文文字色覆盖；顺序决定优先级，不改变行宽、行高或分页。
  final List<ReaderTextOverlay> textOverlays;

  /// 作者块背景与边框之后、正文之前的绘制钩子，沿用页内坐标。
  ///
  /// 可用于阅读器装饰底层；调用前后独立保存画布状态，不影响后续绘制。
  final void Function(Canvas, PageContent, PageBlockSlice)? beforeBlockText;

  /// UI 提供画廊当前帧；缺省显示第一帧，不改动排版结果。
  final int Function(PageGallery gallery)? galleryFrameOf;

  /// 拖动中的连续帧位置；仅影响绘制，整数位置与静态帧一致。
  final double? Function(PageGallery gallery)? galleryPositionOf;

  /// 只绘制阅读主题的纸底，供卷页背面的背景纹理复用。
  void paintBackground(
    Canvas canvas, {
    required Size pageSize,
    EdgeInsets pageInsets = EdgeInsets.zero,
  }) {
    final rect = Rect.fromLTWH(
      -pageInsets.left,
      -pageInsets.top,
      pageSize.width,
      pageSize.height,
    );
    canvas.save();
    canvas.translate(pageInsets.left, pageInsets.top);
    _paintPaperBackground(canvas, rect);
    canvas.restore();
  }

  /// 绘制一页。
  ///
  /// 行的水平位置由布局阶段按 text-align 算好（[LineBox.offsetX]）；
  /// 行内样式取自 [TextLayoutResult.runs]（混排字号、行内元素）；
  /// justify 行把余量按间隙分摊到左侧字符的字距上（§8.4）。
  ///
  /// [pageInsets] 是正文区相对整页的内缩（阅读器页边距 + 页眉页脚槽）：
  /// 传非零值时画布按整页给尺寸、内容整体偏移 [pageInsets]，页面底色与
  /// 背景图铺满整页，出血块的盒子扩到页边（不再被内缩裁掉）。
  void paint(
    Canvas canvas,
    PageContent page, {
    required Size pageSize,
    EdgeInsets pageInsets = EdgeInsets.zero,
  }) {
    final contentSize = Size(
      math.max(0, pageSize.width - pageInsets.horizontal),
      math.max(0, pageSize.height - pageInsets.vertical),
    );
    // 整页矩形（内容坐标：左上角为 -insets）。
    final pageRect = Rect.fromLTWH(
      -pageInsets.left,
      -pageInsets.top,
      pageSize.width,
      pageSize.height,
    );
    final geometries = _sliceGeometries(
      page,
      contentSize,
      pageInsets: pageInsets,
    );
    // 叠放顺序（CSS 2.1 §9.9）：`z-index` 升序绘制，同层保持文档序。
    // 只影响绘制次序；`geometries` 本身仍按文档序用于命中/选区。
    final paintIndexOf = <_SliceGeometry, int>{
      for (var i = 0; i < geometries.length; i++) geometries[i]: i,
    };

    canvas.save();
    canvas.translate(pageInsets.left, pageInsets.top);
    _notifyPhase(PagePaintPhase.background);
    _paintPaperBackground(canvas, pageRect);

    // 书籍整页背景图（P9-04）：平铺在背景色/纹理之上、正文之下。
    _paintBookPageBackground(canvas, page, pageRect);

    _paintContents(
      _PagePaintContext(canvas, page, pageRect, paintIndexOf),
      geometries,
      0,
      1,
    );

    _notifyPhase(PagePaintPhase.selection);
    final selection = this.selection;
    if (selection != null) {
      _paintSelection(canvas, page, geometries, selection);
    }
    canvas.restore();
  }

  /// 按共享容器身份保留嵌套关系，每层内部独立决定叠放顺序。
  void _paintContents(
    _PagePaintContext context,
    List<_SliceGeometry> geometries,
    int depth,
    double parentOpacity, {
    _FlowPaintPhase phase = _FlowPaintPhase.all,
  }) {
    final groups = _paintGroups(geometries, depth);
    if (phase != _FlowPaintPhase.all) {
      for (final group in groups) {
        _paintGroup(context, group, depth, parentOpacity, phase);
      }
      return;
    }
    for (final next in [
      _FlowPaintPhase.negative,
      _FlowPaintPhase.background,
      _FlowPaintPhase.foreground,
    ]) {
      for (final group in groups) {
        _paintGroup(context, group, depth, parentOpacity, next);
      }
    }
  }

  List<_PaintGroup> _paintGroups(List<_SliceGeometry> geometries, int depth) {
    final groups = <_PaintGroup>[];
    for (final geometry in geometries) {
      final fragments = geometry.slice.block.containers;
      final container = depth < fragments.length
          ? fragments[depth].container
          : null;
      if (container != null &&
          groups.isNotEmpty &&
          identical(groups.last.container, container)) {
        groups.last.geometries.add(geometry);
      } else {
        groups.add(_PaintGroup(groups.length, container, [geometry]));
      }
    }
    groups.sort((a, b) {
      final byZ = a.style.zIndex.compareTo(b.style.zIndex);
      return byZ != 0 ? byZ : a.order.compareTo(b.order);
    });
    return groups;
  }

  /// 普通流背景先于替换图片和行内文字；定位与合成组仍作为整体绘制。
  void _paintGroup(
    _PagePaintContext context,
    _PaintGroup group,
    int depth,
    double parentOpacity,
    _FlowPaintPhase phase,
  ) {
    final split = group.canSplitFlowPaint;
    final negative = group.style.zIndex < 0;
    if (negative &&
        phase != _FlowPaintPhase.negative &&
        phase != _FlowPaintPhase.all) {
      return;
    }
    if (!negative && phase == _FlowPaintPhase.negative && !split) return;
    if (phase == _FlowPaintPhase.background && !split) return;
    final effectivePhase = split && !negative ? phase : _FlowPaintPhase.all;
    if (group.container != null) {
      _paintContainer(
        context,
        group,
        depth,
        parentOpacity,
        phase: effectivePhase,
      );
    } else if (!group.geometries.single.hidden &&
        effectivePhase != _FlowPaintPhase.negative) {
      _paintBlock(
        context,
        group.geometries.single,
        parentOpacity,
        phase: effectivePhase,
      );
    }
  }

  void _paintContainer(
    _PagePaintContext context,
    _PaintGroup group,
    int depth,
    double parentOpacity, {
    _FlowPaintPhase phase = _FlowPaintPhase.all,
  }) {
    final canvas = context.canvas;
    final geometry = _containerGeometry(group, depth, context.page.pageHeight);
    _inBlockSpace(canvas, geometry, clip: false, () {
      _withClipPath(
        canvas,
        geometry,
        () => _withEffects(canvas, geometry, parentOpacity: parentOpacity, () {
          if (!geometry.hidden &&
              (phase == _FlowPaintPhase.all ||
                  phase == _FlowPaintPhase.background)) {
            _paintBoxShadow(canvas, geometry);
            _paintBlockBackground(
              canvas,
              geometry,
              context.page,
              context.pageRect,
            );
            _paintBlockBorder(canvas, geometry);
          }
          _paintContainerContents(context, group, geometry, depth, phase);
          if (!geometry.hidden &&
              (phase == _FlowPaintPhase.all ||
                  phase == _FlowPaintPhase.foreground)) {
            _paintBlockOutline(canvas, geometry);
          }
        }),
      );
    });
  }

  void _paintContainerContents(
    _PagePaintContext context,
    _PaintGroup group,
    _SliceGeometry geometry,
    int depth,
    _FlowPaintPhase phase,
  ) {
    final canvas = context.canvas;
    canvas.save();
    if (geometry.clipsOverflow) {
      // 根容器承担页级裁剪；普通容器仍按 padding-box 限制后代内容。
      canvas.clipRect(
        group.container!.isPageRoot ? context.pageRect : geometry.paddingBox,
      );
    }
    _paintContents(
      context,
      group.geometries,
      depth + 1,
      geometry.style.effectiveOpacity,
      phase: phase,
    );
    canvas.restore();
  }

  /// 真实首尾按内容收口；克隆续页封到页底，外层留白逐层扣除。
  Rect _containerBounds(_PaintGroup group, int depth, double pageHeight) {
    final container = group.container!;
    // 页首浮动已避让续框内边距，祖先外框仍应从在流片段的页首起画。
    final first = container.cloneDecoration
        ? group.geometries.firstWhere(
            (geometry) => !geometry.slice.overlay,
            orElse: () => group.geometries.first,
          )
        : group.geometries.first;
    final last = group.geometries.last;
    final start = first.slice.block.containers[depth];
    final end = last.slice.block.containers[depth];
    final starts = start.startsHere && first.startsBlock;
    final ends = end.endsHere && last.endsBlock;
    final outerTop = first.slice.block.containerTopInset(
      first.slice.startLine,
      beforeDepth: depth,
    );
    final outerBottom = last.slice.block.containerBottomInset(
      last.slice.endLine,
      beforeDepth: depth,
    );
    final top = starts
        ? first.y + first.leading - start.topInset
        : first.y + outerTop;
    final bottom = ends
        ? last.y +
              last.slice.height -
              last.slice.trailingExtent +
              end.bottomInset
        : (container.cloneDecoration
                  ? pageHeight
                  : last.y + last.slice.height) -
              outerBottom;
    return Rect.fromLTWH(
      container.left,
      top,
      container.width,
      math.max(0, bottom - top),
    );
  }

  _SliceGeometry _containerGeometry(
    _PaintGroup group,
    int depth,
    double pageHeight,
  ) {
    final first = group.geometries.first;
    final last = group.geometries.last;
    final start = first.slice.block.containers[depth];
    final end = last.slice.block.containers[depth];
    final container = group.container!;
    final bounds = _containerBounds(group, depth, pageHeight);
    return _SliceGeometry(
      slice: first.slice,
      y: bounds.top,
      style: container.style,
      textStyle: first.textStyle,
      startsBlock:
          container.cloneDecoration || start.startsHere && first.startsBlock,
      endsBlock: container.cloneDecoration || end.endsHere && last.endsBlock,
      hidden: container.style.visibility != CssVisibility.visible,
      leading: 0,
      leftInset: container.left,
      rightInset: 0,
      upExtent: 0,
      downExtent: 0,
      pageWidth: first.pageWidth,
      pageHeight: first.pageHeight,
      pageInsets: first.pageInsets,
      paintBox: bounds,
    );
  }

  /// 有合成效果的元素完整绘制，普通流元素按背景和前景阶段绘制。
  void _paintBlock(
    _PagePaintContext context,
    _SliceGeometry geometry,
    double parentOpacity, {
    _FlowPaintPhase phase = _FlowPaintPhase.all,
  }) {
    final canvas = context.canvas;
    _inBlockSpace(canvas, geometry, clip: false, () {
      _withClipPath(
        canvas,
        geometry,
        () => _withEffects(canvas, geometry, parentOpacity: parentOpacity, () {
          if (phase != _FlowPaintPhase.foreground) {
            _paintBlockBox(context, geometry);
          }
          if (phase == _FlowPaintPhase.background) return;
          _paintBlockForeground(context, geometry);
        }),
      );
    });
  }

  void _paintBlockBox(_PagePaintContext context, _SliceGeometry geometry) {
    final canvas = context.canvas;
    _notifyPhase(PagePaintPhase.blockBackground);
    _paintBoxShadow(canvas, geometry);
    _clipBlock(canvas, geometry, clip: true, decoration: true, () {
      _paintBlockBackground(canvas, geometry, context.page, context.pageRect);
    });
    _notifyPhase(PagePaintPhase.blockBorder);
    _clipBlock(canvas, geometry, clip: true, decoration: true, () {
      _paintBlockBorder(canvas, geometry);
    });
  }

  void _paintBlockForeground(
    _PagePaintContext context,
    _SliceGeometry geometry,
  ) {
    final canvas = context.canvas;
    final page = context.page;
    final sliceIndex = context.indexOf[geometry]!;
    if (beforeBlockText != null) {
      canvas.save();
      beforeBlockText!(canvas, page, geometry.slice);
      canvas.restore();
    }
    _notifyPhase(PagePaintPhase.text);
    _paintBlockText(canvas, page, geometry, sliceIndex, context.pageRect);
    _notifyPhase(PagePaintPhase.decoration);
    _paintBlockEmphasis(canvas, page, geometry, sliceIndex);
    _paintBlockRubies(canvas, geometry);
    _paintBlockOutline(canvas, geometry);
  }

  void _paintBlockBackground(
    Canvas canvas,
    _SliceGeometry geometry,
    PageContent page,
    Rect pageRect,
  ) {
    _paintBackdropFilter(
      canvas,
      (box: geometry.borderBox, style: geometry.style),
      page,
      pageRect,
    );
    _paintBackground(
      canvas,
      geometry.containerPaintBox,
      geometry.style,
      startsBlock: geometry.startsBlock,
      endsBlock: geometry.endsBlock,
    );
    _paintInsetBoxShadow(canvas, geometry);
    _paintColumnRules(canvas, geometry);
  }

  void _paintBlockBorder(Canvas canvas, _SliceGeometry geometry) {
    if (geometry.style.borderImage != null) {
      if (geometry.startsBlock && geometry.endsBlock) {
        _paintBorderImage(canvas, geometry.borderBox, geometry.style);
      }
      return;
    }
    _paintBorders(
      canvas,
      geometry.containerPaintBox,
      geometry.style,
      fragment: (starts: geometry.startsBlock, ends: geometry.endsBlock),
    );
  }

  /// 轮廓不影响布局，绘制在边框盒外侧并覆盖在本块内容之上。
  void _paintBlockOutline(Canvas canvas, _SliceGeometry geometry) {
    final outline = geometry.style.outline;
    if (!outline.isVisible) {
      return;
    }
    final half = outline.width / 2;
    final extra = outline.offset + half;
    final borders = geometry.style.borders;
    final box = geometry.borderBox;
    final strokeBox = box.inflate(extra);
    final radii = borders.radiiFor(box.size);
    Radius grow(Radius radius) {
      // 直角边框的 outline 也必须保持直角；只有实际存在的圆角才随
      // outline-offset 和线宽向外扩展。
      if (radius.x == 0 && radius.y == 0) {
        return Radius.zero;
      }
      return Radius.elliptical(
        math.max(0, radius.x + extra),
        math.max(0, radius.y + extra),
      );
    }

    final strokeRRect = RRect.fromRectAndCorners(
      strokeBox,
      topLeft: grow(radii.topLeft),
      topRight: grow(radii.topRight),
      bottomRight: grow(radii.bottomRight),
      bottomLeft: grow(radii.bottomLeft),
    );
    final side = CssBorderSide(
      width: outline.width,
      style: outline.style,
      color: outline.color,
    );
    if (outline.style == CssBorderStyle.solid) {
      canvas.drawRRect(
        strokeRRect,
        Paint()
          ..color = outline.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = outline.width,
      );
      return;
    }
    final rounded =
        radii.topLeft.x > 0 ||
        radii.topRight.x > 0 ||
        radii.bottomRight.x > 0 ||
        radii.bottomLeft.x > 0;
    if (rounded &&
        (outline.style == CssBorderStyle.dashed ||
            outline.style == CssBorderStyle.dotted)) {
      final paint = Paint()
        ..color = outline.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = outline.width
        ..strokeCap = StrokeCap.butt;
      final dash = outline.style == CssBorderStyle.dotted
          ? outline.width
          : outline.width < 3
          ? outline.width * 3
          : outline.width * 2;
      final gap = outline.style == CssBorderStyle.dotted
          ? outline.width
          : outline.width < 3
          ? outline.width * 2
          : outline.width;
      _paintPathDashes(canvas, Path()..addRRect(strokeRRect), paint, dash, gap);
      return;
    }
    _paintSide(
      canvas,
      side,
      strokeBox.topLeft,
      strokeBox.topRight,
      outward: const Offset(0, -1),
    );
    _paintSide(
      canvas,
      side,
      strokeBox.topRight,
      strokeBox.bottomRight,
      outward: const Offset(1, 0),
    );
    _paintSide(
      canvas,
      side,
      strokeBox.bottomRight,
      strokeBox.bottomLeft,
      outward: const Offset(0, 1),
    );
    _paintSide(
      canvas,
      side,
      strokeBox.bottomLeft,
      strokeBox.topLeft,
      outward: const Offset(-1, 0),
    );
  }

  void _paintBlockText(
    Canvas canvas,
    PageContent page,
    _SliceGeometry geometry,
    int sliceIndex,
    Rect pageRect,
  ) {
    final gallery = geometry.slice.block.gallery;
    if (gallery != null) {
      _paintGallery(canvas, geometry, gallery);
      return;
    }
    final fontMetricsCache = <TextStyle, ({double ascent, double descent})>{};
    // 表格切片（flat 管线接入）：网格线 + 逐格文字，不走行文本路径。
    final tableSpec = geometry.slice.block.table;
    if (tableSpec != null) {
      _clipBlock(canvas, geometry, clip: true, contentClip: true, () {
        _paintTable(canvas, geometry, tableSpec, page, pageRect);
      });
      return;
    }
    // 竖排注音画在列右侧，可能越出块的内容盒；此时不按内容盒裁剪，
    // 否则注音会被切掉（Chrome 的注音同样允许横向溢出）。
    final verticalRuby =
        geometry.isVerticalBlock &&
        (geometry.slice.block.rubies?.isNotEmpty ?? false);
    _clipBlock(
      canvas,
      geometry,
      clip: !verticalRuby,
      contentClip: !verticalRuby,
      () {
        final layout = geometry.slice.block.layout;
        final paintingLayout = _textOverlayLayout(geometry.slice.block);
        if (geometry.isVerticalBlock) {
          // 竖排：每行 = 一列，逐字符自上而下绘制（W22）。
          _paintVerticalColumns(
            canvas,
            paintingLayout,
            geometry.style,
            textColorOverride: geometry.textColorOverride,
            contentLeft:
                geometry.leftInset + geometry.slice.block.verticalColumnOffset,
            contentTop: geometry.y + geometry.leading,
            startLine: geometry.slice.startLine,
            endLine: geometry.slice.endLine,
          );
          return;
        }
        var lineY = geometry.y + geometry.leading;
        for (
          var lineIndex = geometry.slice.startLine;
          lineIndex < geometry.slice.endLine;
          lineIndex++
        ) {
          final line = layout.lines[lineIndex];
          final lineText = layout.text.substring(line.start, line.end);
          final x = line.offsetX + geometry.leftInset;
          // 列表标记属于块首行，显式换行形成的空行也必须绘制。
          if (lineIndex == 0 && geometry.slice.block.listMarker != null) {
            _paintListMarker(
              canvas,
              geometry,
              marker: geometry.slice.block.listMarker!,
              textX: x,
              lineTop: lineY,
              lineHeight: line.height,
            );
          }
          if (lineText.isNotEmpty || line.inlineBoxes.isNotEmpty) {
            final painter = _linePainterFor(
              page,
              sliceIndex,
              lineIndex,
              layout,
              line,
              geometry.textStyle,
              punctCompression: geometry.punctCompression,
              textColorOverride: geometry.textColorOverride,
              paintingLayout: paintingLayout,
            );
            final lineRuns = _lineRuns(layout, line);
            final textY = lineY + textLineBaselineOffset(layout, line, painter);
            // 普通 run 与独立行内盒都在文字之前绘制，不能互相替代。
            _paintInlineBoxes(
              canvas,
              painter,
              lineRuns,
              x,
              textY,
              line: line,
              textAlign: geometry.style.textAlign,
              isRtl: layout.isRtl,
            );
            if (line.inlineBoxes.isNotEmpty) {
              _paintInlineBoxPlacements(
                canvas,
                geometry.style,
                line,
                lineRuns,
                x,
                lineY,
              );
            }
            _paintLineText(
              canvas,
              painter,
              lineText,
              lineRuns,
              geometry.textStyle,
              x,
              textY,
              line: line,
              textAlign: geometry.style.textAlign,
              isRtl: layout.isRtl,
            );
            // 装饰线（P2-17/P9-18）：line-through / overline 的实线按
            // 浏览器几何重画，画在文字之上（浏览器同样在文字之后绘制）。
            _paintLineDecoration(
              canvas,
              painter,
              layout,
              line,
              geometry.style,
              x,
              textY,
              fontMetricsCache,
            );
            _paintInlineImages(
              canvas,
              painter,
              geometry,
              line,
              lineText,
              x,
              textY,
            );
            // 行尾字形（W13）：布局层只截断/计宽不画字——
            // 省略号 `…`（行宽含省略号 advance）与断词连字符 U+2010 都由
            // 绘制层按行宽末端补画，start/end 仍是原文坐标。
            if (line.ellipsized) {
              _paintLineTailGlyph(
                canvas,
                geometry,
                line: line,
                glyph: '…',
                advance: line.ellipsisWidth,
                x: x,
                y: lineY,
              );
            } else if (line.hyphenated) {
              _paintLineTailGlyph(
                canvas,
                geometry,
                line: line,
                glyph: cssAutoHyphen,
                advance: line.hyphenWidth,
                x: x,
                y: lineY,
              );
            }
          }
          lineY += line.height;
        }
      },
    );
  }

  void _paintGallery(
    Canvas canvas,
    _SliceGeometry geometry,
    PageGallery gallery,
  ) {
    if (gallery.frames.isEmpty ||
        gallery.scale <= 0 ||
        gallery.contentHeight <= 0) {
      return;
    }
    final selected = (galleryFrameOf?.call(gallery) ?? 0).clamp(
      0,
      gallery.frames.length - 1,
    );
    final requested = galleryPositionOf?.call(gallery);
    final position = requested != null && requested.isFinite
        ? requested.clamp(-1.0, gallery.frames.length.toDouble())
        : selected.toDouble();
    final index = position.floor().clamp(0, gallery.frames.length - 1);
    final offset = (index - position) * gallery.width;
    final top = geometry.y + geometry.leading;
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(gallery.left, top, gallery.width, gallery.contentHeight),
    );
    _paintGalleryAt(canvas, geometry, gallery, index, Offset(offset, top));
    if (offset < 0 && index + 1 < gallery.frames.length) {
      _paintGalleryAt(
        canvas,
        geometry,
        gallery,
        index + 1,
        Offset(offset + gallery.width, top),
      );
    }
    canvas.restore();
  }

  void _paintGalleryAt(
    Canvas canvas,
    _SliceGeometry geometry,
    PageGallery gallery,
    int index,
    Offset position,
  ) {
    final left = gallery.left + gallery.width * (1 - gallery.scale) / 2;
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(
        gallery.left + position.dx,
        position.dy,
        gallery.width,
        gallery.contentHeight,
      ),
    );
    canvas.translate(left + position.dx, position.dy);
    canvas.scale(gallery.scale);
    canvas.translate(-gallery.left, 0);
    _paintGalleryFrame(canvas, geometry, gallery.frames[index].content);
    canvas.restore();
  }

  void _paintGalleryFrame(
    Canvas canvas,
    _SliceGeometry geometry,
    PageContent page,
  ) {
    final size = Size(geometry.pageWidth, geometry.pageHeight);
    final slices = _sliceGeometries(
      page,
      size,
      pageInsets: geometry.pageInsets,
    );
    _paintContents(
      _PagePaintContext(
        canvas,
        page,
        Rect.fromLTWH(0, 0, size.width, page.pageHeight),
        {for (var i = 0; i < slices.length; i++) slices[i]: i},
      ),
      slices,
      0,
      geometry.style.effectiveOpacity,
    );
  }

  void _paintBlockEmphasis(
    Canvas canvas,
    PageContent page,
    _SliceGeometry geometry,
    int sliceIndex,
  ) {
    final marks = HorizontalTextEmphasis(
      geometry.slice.block.layout,
      geometry.style,
      _textColorFor,
    );
    if (!marks.hasMarks || geometry.isVerticalBlock) return;
    try {
      _clipBlock(canvas, geometry, clip: true, contentClip: true, () {
        _paintEmphasisLines(canvas, page, geometry, sliceIndex, marks);
      });
    } finally {
      marks.dispose();
    }
  }

  void _paintEmphasisLines(
    Canvas canvas,
    PageContent page,
    _SliceGeometry geometry,
    int sliceIndex,
    HorizontalTextEmphasis marks,
  ) {
    final layout = geometry.slice.block.layout;
    var lineY = geometry.y + geometry.leading;
    for (var i = geometry.slice.startLine; i < geometry.slice.endLine; i++) {
      final line = layout.lines[i];
      final lineText = layout.text.substring(line.start, line.end);
      if (lineText.isNotEmpty) {
        final painter = _linePainterFor(
          page,
          sliceIndex,
          i,
          layout,
          line,
          geometry.textStyle,
          punctCompression: geometry.punctCompression,
          textColorOverride: geometry.textColorOverride,
        );
        final origin = Offset(
          line.offsetX + geometry.leftInset,
          lineY + textLineBaselineOffset(layout, line, painter),
        );
        try {
          marks.paint(canvas, painter, line, origin);
        } finally {
          if (paragraphCache == null) painter.dispose();
        }
      }
      lineY += line.height;
    }
  }

  void _paintBlockRubies(Canvas canvas, _SliceGeometry geometry) {
    final rubies = geometry.slice.block.rubies;
    if (rubies == null || rubies.isEmpty) {
      return;
    }
    // 竖排块的注音画在列右侧（_paintVerticalRubies）：可能越出块的内容盒，
    // 因此单独一趟、不按块盒裁剪，否则注音会被切掉。
    if (geometry.isVerticalBlock) {
      final layout = geometry.slice.block.layout;
      _clipBlock(
        canvas,
        geometry,
        clip: false,
        () => _paintVerticalRubies(
          canvas,
          layout,
          geometry.style,
          rubies,
          contentLeft:
              geometry.leftInset + geometry.slice.block.verticalColumnOffset,
          contentTop: geometry.y + geometry.leading,
          startLine: geometry.slice.startLine,
          endLine: geometry.slice.endLine,
          metrics: TextLayoutEngine.verticalGlyphMetrics(
            layout.text,
            geometry.style,
          ),
        ),
      );
      return;
    }
    // 注音画在行顶上方/行底下，可能越出块盒；按内容盒裁剪会把它切掉，
    // 因此这一趟不裁剪（与竖排注音同一处理）。
    _clipBlock(
      canvas,
      geometry,
      clip: false,
      () => _paintRubies(canvas, geometry, rubies),
    );
  }

  /// 元素变换已在外层应用；各绘制部分只处理自己的裁剪范围。
  void _clipBlock(
    Canvas canvas,
    _SliceGeometry geometry,
    void Function() body, {
    required bool clip,
    bool contentClip = false,
    bool decoration = false,
  }) {
    canvas.save();
    if (clip && geometry.style.transforms.isEmpty) {
      geometry.clip(canvas, decoration: decoration);
    }
    if (contentClip && geometry.clipsOverflow) {
      canvas.clipRect(geometry.paddingBox);
    }
    body();
    canvas.restore();
  }

  void _notifyPhase(PagePaintPhase phase) => onPhase?.call(phase);

  /// 行内样式也独立执行主题色策略，避免对齐或基线偏移改变作者配色。
  TextStyle _paintTextStyleFor(ComputedStyle style) {
    final textStyle = TextLayoutEngine.textStyleFor(style);
    final color = _textColorFor(style);
    return color == null ? textStyle : textStyle.copyWith(color: color);
  }

  TextLayoutResult _textOverlayLayout(PageBlock block) {
    final layout = block.layout;
    if (textOverlays.isEmpty || block.startCfi == null) return layout;
    final runs = ReaderTextOverlayResolver(textOverlays, typography: false)
        .resolve(
          blockCfi: block.startCfi,
          text: layout.text,
          style: block.style ?? ComputedStyle(const {}),
          runs: layout.runs,
        );
    if (identical(runs, layout.runs)) return layout;
    return TextLayoutResult(
      text: layout.text,
      lines: layout.lines,
      width: layout.width,
      height: layout.height,
      maxWidth: layout.maxWidth,
      runs: runs,
      isRtl: layout.isRtl,
      writingMode: layout.writingMode,
      plainTextLayout: layout.plainTextLayout,
    );
  }

  /// 主题文字色是否覆盖某个块（P9-02）。
  ///
  /// 普通主题下书籍显式声明的颜色（含继承）始终照书，日间/夜间都不替换；
  /// 只有未声明颜色的文字才跟随主题色。[inkMode] 为真时例外，
  /// 所有非透明文字按背景压成纯黑或纯白。
  Color? _textColorFor(ComputedStyle style) {
    // 透明字是书籍用于封面排版的隐藏文本，不能因为对比度低就画出来。
    if (style.color.a == 0) {
      return null;
    }
    // 块自带背景时按块内的有效底色判断：主题色在浅色页是深字，直接套到
    // 深色卡片上会隐形，此时需要一个浅色兜底（P9-23）。
    final blendedBackground = style.backgroundColor.a > 0
        ? Color.alphaBlend(style.backgroundColor, background)
        : background;
    if (inkMode) {
      return _monochromeForeground(blendedBackground);
    }
    final theme = textColor;
    if (theme == null) {
      return null;
    }
    if (style.hasExplicitTextColor) {
      return null;
    }
    final darkText = style.color.computeLuminance() <= 0.179;
    final darkBackground = blendedBackground.computeLuminance() < 0.35;
    final fallback = darkBackground && theme.computeLuminance() >= 0.35
        ? const Color(0xFFE6E6E6)
        : theme;
    if (darkText) {
      return fallback;
    }
    final foreground = Color.alphaBlend(style.color, blendedBackground);
    // 2:1 只用于拦截“换主题后仍接近不可见”的浅字；金色、橙色等作者
    // 强调色通常高于该阈值，继续保留。
    return _contrastRatio(foreground, blendedBackground) < 2 ? fallback : null;
  }

  static double _contrastRatio(Color foreground, Color background) {
    final fg = _relativeLuminance(foreground);
    final bg = _relativeLuminance(background);
    final lighter = math.max(fg, bg);
    final darker = math.min(fg, bg);
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// 纯黑白前景：深底用白、浅底用黑。
  static Color _monochromeForeground(Color background) =>
      background.computeLuminance() < 0.5
      ? const Color(0xFFFFFFFF)
      : const Color(0xFF000000);

  /// 墨迹背景压成纯黑或纯白，避免半透明色块在墨水屏上留下灰阶。
  Color _monochromeBackground(Color color) {
    final blended = color.a < 1 ? Color.alphaBlend(color, background) : color;
    return blended.computeLuminance() < 0.5
        ? const Color(0xFF000000)
        : const Color(0xFFFFFFFF);
  }

  /// 墨水屏行内标记图的亮度阈值滤镜：亮部保留白色、暗部压成黑色。
  ///
  /// 史记等 EPUB 用橙色圆底图片充当注号，只改文字颜色覆盖不到图片。
  /// 40 倍增益把阈值附近的灰阶过渡带压到约 2.5%，避免整块图变灰；
  /// 阈值取 0.78，让常见橙色标记落入暗部，同时保留米白底色。
  static const ColorFilter _inkImageFilter = ColorFilter.matrix(<double>[
    8.504, 28.608, 2.888, 0, -7828.5, //
    8.504, 28.608, 2.888, 0, -7828.5, //
    8.504, 28.608, 2.888, 0, -7828.5, //
    0, 0, 0, 1, 0, //
  ]);

  /// 画书籍整页背景图（P9-04）：`body`/`html` 的 `background-image`。
  ///
  /// 图片由调用方（阅读视图的图片缓存）在帧外解码，这里只查表 + 按
  /// `background-size/repeat/position` 铺满页面矩形。
  void _paintBookPageBackground(
    Canvas canvas,
    PageContent page,
    Rect pageRect,
  ) {
    final spec = page.background;
    if (spec == null) {
      return;
    }
    final color = spec.backgroundColor;
    if (color != null && color.a > 0) {
      canvas.drawRect(pageRect, Paint()..color = color);
    }
    canvas.save();
    canvas.clipRect(pageRect);
    for (final layer in spec.effectiveLayers.reversed) {
      _paintBackgroundLayer(canvas, layer, pageRect);
    }
    canvas.restore();
  }

  /// 预计算每片切片的几何与样式（P2-29：各阶段共用同一份坐标）。
  List<_SliceGeometry> _sliceGeometries(
    PageContent page,
    Size pageSize, {
    EdgeInsets pageInsets = EdgeInsets.zero,
  }) {
    // 上下标的基线偏移会超出切片矩形：统计本页最大上下偏移，放宽裁剪。
    var upExtent = 0.0;
    var downExtent = 0.0;
    for (final slice in page.slices) {
      final style = slice.block.style;
      if (style != null &&
          style.textEmphasisStyle != CssTextEmphasisStyle.none) {
        if (style.textEmphasisPosition.isUnder) {
          downExtent = math.max(downExtent, style.fontSize * 0.55);
        } else {
          upExtent = math.max(upExtent, style.fontSize * 0.4);
        }
      }
      for (final run in slice.block.layout.runs) {
        final marked = run.style.textEmphasisStyle != CssTextEmphasisStyle.none;
        final above = marked && run.style.textEmphasisPosition.isOver
            ? run.style.fontSize * 0.4
            : 0.0;
        final below = marked && run.style.textEmphasisPosition.isUnder
            ? run.style.fontSize * 0.55
            : 0.0;
        upExtent = math.max(upExtent, above - run.baselineShift);
        downExtent = math.max(downExtent, below + run.baselineShift);
      }
    }
    final geometries = <_SliceGeometry>[];
    final borderMetrics = <TextStyle, ({double ascent, double descent})>{};
    var y = page.topPadding;
    var chapterLeading = page.pageIndex == 0;
    for (final slice in page.slices) {
      final style = slice.block.style ?? ComputedStyle(<String, String>{});
      // 浮动覆盖切片（flat 管线接入）：绝对定位，不推进流游标。
      final sliceY = slice.overlay ? slice.absoluteTop! : y;
      final borderOverflow = _inlineBorderOverflow(
        slice,
        pageSize,
        sliceY,
        borderMetrics,
      );
      geometries.add(
        _SliceGeometry(
          slice: slice,
          y: sliceY,
          style: style,
          textStyle: TextLayoutEngine.textStyleFor(style),
          textColorOverride: _textColorFor(style),
          startsBlock: slice.startLine == 0,
          endsBlock: slice.endLine == slice.block.layout.lineCount,
          hidden: style.visibility != CssVisibility.visible,
          leading: slice.leadingExtent,
          // flat 管线（P3-30 真机验收）：box.left 恒 0，块级 margin.left
          // 折算进左内缩——文本 x、标记 gutter、选区、省略宽度同步右移。
          // P8-05：margin.right/padding.right 同步折算右内缩。
          leftInset:
              slice.leftInset +
              style.margin.left +
              (slice.overlay && style.isOutOfFlow
                  ? (style.borders.left.isVisible
                            ? style.borders.left.width
                            : 0) +
                        style.padding.left
                  : 0),
          rightInset: style.margin.right + style.padding.right,
          upExtent: math.max(upExtent, borderOverflow.top),
          downExtent: math.max(downExtent, borderOverflow.bottom),
          pageWidth: pageSize.width,
          pageHeight: pageSize.height,
          pageInsets: pageInsets,
          chapterLeading: chapterLeading && !slice.overlay,
        ),
      );
      if (!slice.overlay) {
        y += slice.height;
        chapterLeading = false;
      }
    }
    return geometries;
  }

  /// 行内边框可超出行盒；只扩展所属切片的绘制范围，并在页内容区收边。
  ({double top, double bottom}) _inlineBorderOverflow(
    PageBlockSlice slice,
    Size pageSize,
    double sliceY,
    Map<TextStyle, ({double ascent, double descent})> metricsCache,
  ) {
    final layout = slice.block.layout;
    if (layout.isVertical || layout.lines.any((line) => line.vertical)) {
      return (top: 0, bottom: 0);
    }
    final runs = layout.runs
        .where(
          (run) => !run.syntheticFontFallback && run.style.borders.hasBorder,
        )
        .toList();
    if (runs.isEmpty) return (top: 0, bottom: 0);
    final clip = slice.clipRect(0, pageSize.width);
    var top = 0.0, bottom = 0.0, lineTop = slice.leadingExtent;
    for (final line in slice.lines) {
      for (final run in runs) {
        if (run.end <= line.start || run.start >= line.end) continue;
        final extents = _inlineBorderVerticalExtents(run.style, metricsCache);
        final baseline = lineTop + line.baseline - line.top;
        top = math.max(top, clip.top - baseline + extents.top);
        bottom = math.max(bottom, baseline + extents.bottom - clip.bottom);
      }
      lineTop += line.height;
    }
    return (
      top: math.min(top.ceilToDouble(), math.max(0, sliceY + clip.top)),
      bottom: math.min(
        bottom.ceilToDouble(),
        math.max(0, pageSize.height - sliceY - clip.bottom),
      ),
    );
  }

  /// 相对基线的上下边界：字体内容盒、内边距及可见边框依次向外扩。
  ({double top, double bottom}) _inlineBorderVerticalExtents(
    ComputedStyle style,
    Map<TextStyle, ({double ascent, double descent})> metricsCache,
  ) {
    final font = _fontMetricsOf(style, metricsCache);
    final borders = style.borders;
    return (
      top:
          font.ascent +
          style.padding.top +
          (borders.top.isVisible ? borders.top.width : 0),
      bottom:
          font.descent +
          style.padding.bottom +
          (borders.bottom.isVisible ? borders.bottom.width : 0),
    );
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
            textColorOverride: geometry.textColorOverride,
            textAutospace: geometry.textAutospace,
          );
          final boxes = _lineRangeRects(
            painter,
            line,
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

  /// 布局结果对应的文字方向（RTL 段落测量按 rtl，绘制必须同向）。
  static TextDirection _textDirectionOf(TextLayoutResult layout) =>
      layout.isRtl ? TextDirection.rtl : TextDirection.ltr;

  /// 在块坐标系里执行 [body]。
  ///
  /// - 有 `transform`：先把画布变换到块空间（旋转/缩放后的 ink 允许越出切片，
  ///   页外由画布光栅天然裁剪；Chromium 也只按视口裁），不再按切片裁，
  ///   否则旋转块的四角会被切片矩形切掉。
  /// - 无 `transform`：[clip] 为真时按切片裁剪（跨页块不画到相邻块地盘）。
  /// - [contentClip] 为真且 `overflow != visible` 时再裁到 padding-box
  ///   （文字/装饰/行内盒/表格 ink 不得画到盒外）。
  void _inBlockSpace(
    Canvas canvas,
    _SliceGeometry geometry,
    void Function() body, {
    required bool clip,
    bool contentClip = false,
  }) {
    final matrix = _transformMatrixOf(geometry);
    canvas.save();
    if (matrix != null) {
      canvas.transform(matrix);
    } else if (clip) {
      geometry.clip(canvas);
    }
    if (contentClip && geometry.clipsOverflow) {
      canvas.clipRect(geometry.paddingBox);
    }
    body();
    canvas.restore();
  }

  /// 块的 2D 仿射矩阵（4×4 列主序），无 `transform` 时返回 null。
  ///
  /// CSS 语义：函数按声明顺序合成（左乘累积），整体绕 `transform-origin`
  /// （默认边框盒中心，百分比以边框盒宽/高为基准）应用；`translate` 的
  /// 百分比同样以边框盒宽/高为基准。
  Float64List? _transformMatrixOf(_SliceGeometry geometry) {
    final transforms = geometry.style.transforms;
    if (transforms.isEmpty) {
      return null;
    }
    final style = geometry.style;
    final box = geometry.borderBox;
    var matrix = _affineIdentity;
    for (final transform in transforms) {
      final next = _affineOfTransform(transform, box);
      if (next == null) {
        continue;
      }
      matrix = _affineMultiply(matrix, next);
    }
    final originX = style.transformOriginX.resolve(box.width) ?? box.width / 2;
    final originY =
        style.transformOriginY.resolve(box.height) ?? box.height / 2;
    // 绕原点：T(原点) · M · T(−原点)；原点用页面坐标（盒子左上角 + 本地原点）。
    final px = box.left + originX;
    final py = box.top + originY;
    final centered = _affineMultiply(
      _affineTranslate(px, py),
      _affineMultiply(matrix, _affineTranslate(-px, -py)),
    );
    return Float64List.fromList(<double>[
      centered[0], centered[1], 0, 0, //
      centered[2], centered[3], 0, 0, //
      0, 0, 1, 0, //
      centered[4], centered[5], 0, 1, //
    ]);
  }

  /// 单个 transform 函数的仿射矩阵（a,b,c,d,e,f：x' = a·x + c·y + e）。
  List<double>? _affineOfTransform(CssTransform transform, Rect box) {
    switch (transform.kind) {
      case CssTransformKind.translate:
        final tx = transform.x?.resolve(box.width) ?? 0;
        final ty = transform.y?.resolve(box.height) ?? 0;
        return _affineTranslate(tx, ty);
      case CssTransformKind.scale:
        final sx = transform.sx ?? 1;
        return _affineScale(sx, transform.sy ?? sx);
      case CssTransformKind.rotate:
        return _affineRotate(transform.angleDeg ?? 0);
      case CssTransformKind.skew:
        return _affineSkew(transform.axDeg, transform.ayDeg);
      case CssTransformKind.matrix:
        final values = transform.values;
        if (values == null || values.length < 6) {
          return null;
        }
        return <double>[
          values[0],
          values[1],
          values[2],
          values[3],
          values[4],
          values[5],
        ];
    }
  }

  static const List<double> _affineIdentity = <double>[1, 0, 0, 1, 0, 0];

  static List<double> _affineTranslate(double tx, double ty) => <double>[
    1,
    0,
    0,
    1,
    tx,
    ty,
  ];

  static List<double> _affineScale(double sx, double sy) => <double>[
    sx,
    0,
    0,
    sy,
    0,
    0,
  ];

  /// 旋转矩阵：屏幕 y 轴向下，CSS 正角为顺时针。
  static List<double> _affineRotate(double angleDeg) {
    final radians = angleDeg * math.pi / 180;
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    return <double>[cos, sin, -sin, cos, 0, 0];
  }

  static List<double> _affineSkew(double axDeg, double ayDeg) => <double>[
    1,
    math.tan(ayDeg * math.pi / 180),
    math.tan(axDeg * math.pi / 180),
    1,
    0,
    0,
  ];

  /// 仿射合成 [m]∘[n]：先应用 [n]，再应用 [m]。
  static List<double> _affineMultiply(List<double> m, List<double> n) =>
      <double>[
        m[0] * n[0] + m[2] * n[1],
        m[1] * n[0] + m[3] * n[1],
        m[0] * n[2] + m[2] * n[3],
        m[1] * n[2] + m[3] * n[3],
        m[0] * n[4] + m[2] * n[5] + m[4],
        m[1] * n[4] + m[3] * n[5] + m[5],
      ];

  /// 行尾字形（W13）：省略号 `…` 与断词连字符 U+2010。
  ///
  /// 布局层的 `LineBox.width` 已含该字形的 advance（[advance]），`start/end`
  /// 仍是原文坐标，所以绘制层只需把字形画在
  /// `行左缘 + 行宽 − advance`，不做截断、不改文本。
  void _paintLineTailGlyph(
    Canvas canvas,
    _SliceGeometry geometry, {
    required LineBox line,
    required String glyph,
    required double advance,
    required double x,
    required double y,
  }) {
    if (advance <= 0) {
      return;
    }
    final painter = TextPainter(
      text: TextSpan(text: glyph, style: geometry.textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(x + line.width - advance, y));
    painter.dispose();
  }

  /// 元素效果合成（W6）：`filter` 链 + 组不透明度。
  ///
  /// CSS 语义：filter 列表从左到右依次作用于元素结果；opacity 最后作用于
  /// 整个元素组。实现为嵌套 saveLayer——先声明的滤镜在内层、后声明的在外层，
  /// 每层只带一个滤镜：
  /// - 颜色类（grayscale/sepia/brightness/contrast/saturate/hue-rotate/
  ///   invert/opacity）→ [ColorFilter.matrix]；
  /// - `blur()` → [ui.ImageFilter.blur]（CSS 参数即高斯标准差；Chromium
  ///   实测 blur(2px) 的 σ≈2）；
  /// - `drop-shadow()` → 「内容副本 + 偏移 + 模糊 + 染色」垫在元素下方近似
  ///   （本版 Skia 无 dropShadow image filter）。
  ///
  /// 不透明度读 [ComputedStyle.effectiveOpacity]（沿级联父链乘积），因此
  /// 父级半透明会连带作用于子块，与 Chromium 的元素组合成一致。
  ///
  /// 背景、边框、文字与附加装饰共享同一合成层，重叠部分不会重复混色。
  void _withEffects(
    Canvas canvas,
    _SliceGeometry geometry,
    void Function() body, {
    double parentOpacity = 1,
  }) {
    final filters = geometry.style.filters;
    // 累计不透明度有两个来源：PageBlock（章节源按级联链乘积传入，W3 已接线）
    // 与 ComputedStyle.effectiveOpacity（样式层按父链乘积）。取两者较小值，
    // 既不会重复相乘，也能覆盖「只有一边带了祖先值」的调用路径。
    final cumulative = geometry.paintBox != null
        ? geometry.style.effectiveOpacity
        : math.min(
            geometry.slice.block.effectiveOpacity,
            geometry.style.effectiveOpacity,
          );
    final opacity = parentOpacity > 0
        ? (cumulative / parentOpacity).clamp(0.0, 1.0)
        : 0.0;
    if (filters.isEmpty && opacity >= 1) {
      body();
      return;
    }
    final bounds = geometry.box.inflate(128);
    // drop-shadow 先作为元素下方的投影副本绘制，再叠其余滤镜与内容。
    for (final filter in filters) {
      if (filter.kind == CssFilterKind.dropShadow) {
        _paintFilterDropShadow(canvas, filter, body, bounds);
      }
    }
    var layers = 0;
    for (var i = filters.length - 1; i >= 0; i--) {
      final paint = _filterLayerPaint(filters[i]);
      if (paint == null) {
        continue;
      }
      canvas.saveLayer(bounds, paint);
      layers += 1;
    }
    if (opacity < 1) {
      canvas.saveLayer(
        bounds,
        Paint()..color = Color.fromRGBO(255, 255, 255, opacity),
      );
      layers += 1;
    }
    body();
    for (var i = 0; i < layers; i++) {
      canvas.restore();
    }
  }

  /// 按 `clip-path` 基本形状裁剪元素的全部绘制结果（含阴影与轮廓）。
  void _withClipPath(
    Canvas canvas,
    _SliceGeometry geometry,
    void Function() body,
  ) {
    final clip = geometry.style.clipPath;
    if (clip == null) {
      body();
      return;
    }
    final reference = _clipReferenceBox(
      clip,
      geometry.borderBox,
      geometry.style,
    );
    _withClipShape(canvas, clip, reference, body);
  }

  Rect _clipReferenceBox(CssClipPath clip, Rect box, ComputedStyle style) =>
      switch (clip.geometryBox) {
        CssGeometryBox.marginBox => Rect.fromLTRB(
          box.left - style.margin.left,
          box.top - style.margin.top,
          box.right + style.margin.right,
          box.bottom + style.margin.bottom,
        ),
        CssGeometryBox.borderBox => box,
        CssGeometryBox.paddingBox => Rect.fromLTRB(
          box.left + style.borders.left.width,
          box.top + style.borders.top.width,
          box.right - style.borders.right.width,
          box.bottom - style.borders.bottom.width,
        ),
        CssGeometryBox.contentBox => Rect.fromLTRB(
          box.left + style.borders.left.width + style.padding.left,
          box.top + style.borders.top.width + style.padding.top,
          box.right - style.borders.right.width - style.padding.right,
          box.bottom - style.borders.bottom.width - style.padding.bottom,
        ),
      };

  void _withClipShape(
    Canvas canvas,
    CssClipPath clip,
    Rect reference,
    void Function() body,
  ) {
    if (reference.width <= 0 || reference.height <= 0) {
      return;
    }
    final path = _clipPathFor(clip, reference);
    if (path == null) {
      return;
    }
    canvas.save();
    canvas.clipPath(path, doAntiAlias: true);
    body();
    canvas.restore();
  }

  Path? _clipPathFor(CssClipPath clip, Rect box) {
    final width = box.width;
    final height = box.height;
    double resolve(CssLength value, double base) => value.resolve(base) ?? 0;
    final path = Path();
    switch (clip.kind) {
      case CssClipPathKind.inset:
        final rect = Rect.fromLTRB(
          box.left + resolve(clip.insetLeft, width),
          box.top + resolve(clip.insetTop, height),
          box.right - resolve(clip.insetRight, width),
          box.bottom - resolve(clip.insetBottom, height),
        );
        if (clip.insetRadiiX.isEmpty) {
          path.addRect(rect);
          return path;
        }
        CssLength radiusAt(List<CssLength> values, int index) {
          if (values.length == 1) {
            return values[0];
          }
          if (values.length == 2) {
            return values[index.isEven ? 0 : 1];
          }
          if (values.length == 3) {
            return values[index == 2 ? 2 : (index.isEven ? 0 : 1)];
          }
          return values[index];
        }

        Radius corner(int index) {
          final x = resolve(radiusAt(clip.insetRadiiX, index), width);
          final ySource = clip.insetRadiiY.isEmpty
              ? radiusAt(clip.insetRadiiX, index)
              : radiusAt(clip.insetRadiiY, index);
          return Radius.elliptical(x, resolve(ySource, height));
        }

        path.addRRect(
          RRect.fromRectAndCorners(
            rect,
            topLeft: corner(0),
            topRight: corner(1),
            bottomRight: corner(2),
            bottomLeft: corner(3),
          ),
        );
      case CssClipPathKind.circle:
        final center = Offset(
          box.left + resolve(clip.centerX, width),
          box.top + resolve(clip.centerY, height),
        );
        final distances = <double>[
          center.dx - box.left,
          box.right - center.dx,
          center.dy - box.top,
          box.bottom - center.dy,
        ];
        final normalizedDiagonal = math.sqrt(
          (width * width + height * height) / 2,
        );
        final radius =
            clip.circleRadius?.resolve(normalizedDiagonal) ??
            switch (clip.circleExtent) {
              CssClipRadiusExtent.farthestSide => distances.reduce(math.max),
              _ => distances.reduce(math.min),
            };
        if (radius <= 0) {
          return null;
        }
        path.addOval(Rect.fromCircle(center: center, radius: radius));
      case CssClipPathKind.ellipse:
        final center = Offset(
          box.left + resolve(clip.centerX, width),
          box.top + resolve(clip.centerY, height),
        );
        double extent(CssClipRadiusExtent? value, double near, double far) =>
            value == CssClipRadiusExtent.farthestSide
            ? math.max(near, far)
            : math.min(near, far);
        final radiusX =
            clip.ellipseRadiusX?.resolve(width) ??
            extent(
              clip.ellipseExtentX,
              center.dx - box.left,
              box.right - center.dx,
            );
        final radiusY =
            clip.ellipseRadiusY?.resolve(height) ??
            extent(
              clip.ellipseExtentY,
              center.dy - box.top,
              box.bottom - center.dy,
            );
        if (radiusX <= 0 || radiusY <= 0) {
          return null;
        }
        path.addOval(
          Rect.fromCenter(
            center: center,
            width: radiusX * 2,
            height: radiusY * 2,
          ),
        );
      case CssClipPathKind.polygon:
        if (clip.points.isEmpty) {
          return null;
        }
        final first = clip.points.first;
        path.moveTo(
          box.left + resolve(first.x, width),
          box.top + resolve(first.y, height),
        );
        for (final point in clip.points.skip(1)) {
          path.lineTo(
            box.left + resolve(point.x, width),
            box.top + resolve(point.y, height),
          );
        }
        path.close();
        path.fillType = clip.evenOdd
            ? PathFillType.evenOdd
            : PathFillType.nonZero;
    }
    return path;
  }

  /// `backdrop-filter`：把元素背后区域按「页背景」近似铺一层并应用滤镜。
  ///
  /// 已知限制：纯 Canvas 绘制无法采样已画内容（Flutter 的 BackdropFilter 需要
  /// widget 层），因此 backdrop 用页面背景色/背景图代替；真书里该属性只用于
  /// 半透明装饰框，观感接近。
  void _paintBackdropFilter(
    Canvas canvas,
    ({Rect box, ComputedStyle style}) target,
    PageContent page,
    Rect pageRect,
  ) {
    final filters = target.style.backdropFilters;
    if (filters.isEmpty) {
      return;
    }
    final box = target.box;
    if (box.width <= 0 || box.height <= 0) {
      return;
    }
    canvas.save();
    canvas.clipRRect(_shadowRRect(target.style.borders, box, 0));
    var layers = 0;
    for (var i = filters.length - 1; i >= 0; i--) {
      final paint = _filterLayerPaint(filters[i]);
      if (paint == null) {
        continue;
      }
      canvas.saveLayer(box, paint);
      layers += 1;
    }
    canvas.drawRect(pageRect, Paint()..color = background);
    _paintReaderBackground(canvas, pageRect);
    _paintBookPageBackground(canvas, page, pageRect);
    for (var i = 0; i < layers; i++) {
      canvas.restore();
    }
    canvas.restore();
  }

  void _paintPaperBackground(Canvas canvas, Rect pageRect) {
    canvas.drawRect(pageRect, Paint()..color = background);
    _paintReaderBackground(canvas, pageRect);
  }

  void _paintReaderBackground(Canvas canvas, Rect pageRect) {
    final image = pageBackgroundImage;
    if (image == null || pageRect.isEmpty) return;
    final tint = pageBackgroundImageTint;
    final paint = Paint()
      ..filterQuality = FilterQuality.low
      ..colorFilter = tint == null
          ? null
          : ColorFilter.mode(tint, BlendMode.multiply);
    if (pageBackgroundImageCover) {
      final fitted = applyBoxFit(
        BoxFit.cover,
        Size(image.width.toDouble(), image.height.toDouble()),
        pageRect.size,
      );
      final source = Alignment.center.inscribe(
        fitted.source,
        Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      );
      canvas.drawImageRect(image, source, pageRect, paint);
    } else {
      final shader = ImageShader(
        image,
        TileMode.repeated,
        TileMode.repeated,
        _identityMatrix4(),
      );
      canvas.drawRect(pageRect, paint..shader = shader);
      shader.dispose();
    }
    canvas.drawRect(
      pageRect,
      Paint()
        ..color = background.withValues(
          alpha: 1 - pageBackgroundImageOpacity.clamp(0.0, 1.0),
        ),
    );
  }

  /// 单个滤镜对应的图层 Paint；返回 null 表示该滤镜由别的路径实现
  /// （drop-shadow 走 [_paintFilterDropShadow]）。
  Paint? _filterLayerPaint(CssFilter filter) {
    switch (filter.kind) {
      case CssFilterKind.blur:
        final sigma = math.max(0.0, filter.amount);
        if (sigma <= 0) {
          return null;
        }
        return Paint()
          ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
      case CssFilterKind.dropShadow:
        return null;
      default:
        return Paint()..colorFilter = ColorFilter.matrix(_filterMatrix(filter));
    }
  }

  /// 颜色类滤镜的 4×5 颜色矩阵（按 CSS filter-effects-1 的等价矩阵）。
  ///
  /// grayscale/sepia/invert/opacity 的 amount 先钳到 0..1，再与单位矩阵线性
  /// 插值（CSS 里 `sepia(0.6)` 就是 60% 的完整 sepia 效果）。
  List<double> _filterMatrix(CssFilter filter) {
    final amount = filter.amount;
    switch (filter.kind) {
      case CssFilterKind.grayscale:
        final t = amount.clamp(0.0, 1.0);
        return _lerpMatrix(_identityColorMatrix, _grayscaleMatrix, t);
      case CssFilterKind.sepia:
        final t = amount.clamp(0.0, 1.0);
        return _lerpMatrix(_identityColorMatrix, _sepiaMatrix, t);
      case CssFilterKind.invert:
        final t = amount.clamp(0.0, 1.0);
        return _lerpMatrix(_identityColorMatrix, _invertMatrix, t);
      case CssFilterKind.brightness:
        // [b,0,0,0,0] 三行，alpha 保持 1。
        return <double>[
          amount, 0, 0, 0, 0, //
          0, amount, 0, 0, 0, //
          0, 0, amount, 0, 0, //
          0, 0, 0, 1, 0, //
        ];
      case CssFilterKind.contrast:
        // 斜率 c、截距 0.5·(1−c)（0..1 域，换到 0..255 即 127.5·(1−c)）。
        final offset = 127.5 * (1 - amount);
        return <double>[
          amount, 0, 0, 0, offset, //
          0, amount, 0, 0, offset, //
          0, 0, amount, 0, offset, //
          0, 0, 0, 1, 0, //
        ];
      case CssFilterKind.saturate:
        final s = amount;
        return <double>[
          0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0, //
          0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0, //
          0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0, //
          0, 0, 0, 1, 0, //
        ];
      case CssFilterKind.hueRotate:
        final radians = amount * math.pi / 180;
        final cos = math.cos(radians);
        final sin = math.sin(radians);
        return <double>[
          0.213 + cos * 0.787 - sin * 0.213,
          0.715 - cos * 0.715 - sin * 0.715,
          0.072 - cos * 0.072 + sin * 0.928,
          0, 0, //
          0.213 - cos * 0.213 + sin * 0.143,
          0.715 + cos * 0.285 + sin * 0.140,
          0.072 - cos * 0.072 - sin * 0.283,
          0, 0, //
          0.213 - cos * 0.213 - sin * 0.787,
          0.715 - cos * 0.715 + sin * 0.715,
          0.072 + cos * 0.928 + sin * 0.072,
          0, 0, //
          0, 0, 0, 1, 0, //
        ];
      case CssFilterKind.opacity:
        final alpha = amount.clamp(0.0, 1.0);
        return <double>[
          1, 0, 0, 0, 0, //
          0, 1, 0, 0, 0, //
          0, 0, 1, 0, 0, //
          0, 0, 0, alpha, 0, //
        ];
      case CssFilterKind.blur:
      case CssFilterKind.dropShadow:
        return _identityColorMatrix;
    }
  }

  /// drop-shadow 近似：把内容副本按 offset 平移，模糊后染成阴影色，垫在下方。
  ///
  /// CSS 顺序上 drop-shadow 处在滤镜链中间时，其前面的滤镜也应作用于投影、
  /// 后面的滤镜应作用于「投影+元素」合成结果；这里统一按「元素最底层的投影」
  /// 处理（书内 drop-shadow 少见，观感差别仅限特殊链路）。
  void _paintFilterDropShadow(
    Canvas canvas,
    CssFilter filter,
    void Function() body,
    Rect bounds,
  ) {
    final shadow = filter.shadow;
    if (shadow == null) {
      return;
    }
    final sigma = math.max(0.0, shadow.blur / 2);
    canvas.saveLayer(bounds, Paint());
    canvas.saveLayer(
      bounds,
      Paint()..colorFilter = ColorFilter.mode(shadow.color, BlendMode.srcIn),
    );
    if (sigma > 0) {
      canvas.saveLayer(
        bounds,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      );
    }
    canvas.save();
    canvas.translate(shadow.offsetX, shadow.offsetY);
    body();
    canvas.restore();
    if (sigma > 0) {
      canvas.restore();
    }
    canvas.restore();
    canvas.restore();
  }

  /// 列表标记图片（W6）：按块解析 `list-style-image` 的 url；null 表示无图或
  /// 当前不可用，回退文字/几何标记（CSS 同样在图片加载失败时回退）。
  ///
  /// 尺寸按 1em 方框等比缩放、右缘贴正文左缘、垂直居中于行盒；图片由调用方
  /// （章节源 + 图片缓存）经 [imageLookup] 提供，绘制层不做 IO。
  ui.Image? _listMarkerImageFor(_SliceGeometry geometry) {
    final source = listMarkerImageOf;
    final lookup = imageLookup;
    if (source == null || lookup == null) {
      return null;
    }
    final url = source(geometry.slice.block);
    if (url == null || url.isEmpty) {
      return null;
    }
    return lookup(url);
  }

  static const List<double> _identityColorMatrix = <double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  static const List<double> _grayscaleMatrix = <double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  static const List<double> _sepiaMatrix = <double>[
    0.393, 0.769, 0.189, 0, 0, //
    0.349, 0.686, 0.168, 0, 0, //
    0.272, 0.534, 0.131, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  static const List<double> _invertMatrix = <double>[
    -1, 0, 0, 0, 255, //
    0, -1, 0, 0, 255, //
    0, 0, -1, 0, 255, //
    0, 0, 0, 1, 0, //
  ];

  static List<double> _lerpMatrix(
    List<double> from,
    List<double> to,
    double t,
  ) {
    return <double>[
      for (var i = 0; i < from.length; i++) from[i] + (to[i] - from[i]) * t,
    ];
  }

  /// 多列分隔线（`column-rule`，CSS Multicol §4）。
  ///
  /// 几何来自首列块的 [PageBlock.multicol]（其余列是 overlay 块，不重复画）；
  /// 竖线 x = 上一列左缘 + 列宽 + gap/2（= 下一列左缘 − gap/2），高度 = 列带
  /// 内容高（首列块的内容盒就是本页列带高）。线型复用边框的 [_paintSide]
  /// （solid / double / dotted / dashed 与 `border-style` 同口径）。
  void _paintColumnRules(Canvas canvas, _SliceGeometry geometry) {
    final multicol = geometry.slice.block.multicol;
    final rule = geometry.style.columnRule;
    if (multicol == null || multicol.count < 2) {
      return;
    }
    if (rule == null || !rule.isVisible) {
      return;
    }
    final borders = geometry.style.borders;
    final padding = geometry.style.padding;
    final box = geometry.borderBox;
    final left =
        box.left +
        (borders.left.isVisible ? borders.left.width : 0) +
        padding.left;
    final top =
        box.top + (borders.top.isVisible ? borders.top.width : 0) + padding.top;
    final bottom =
        box.bottom -
        (borders.bottom.isVisible ? borders.bottom.width : 0) -
        padding.bottom;
    if (bottom <= top) {
      return;
    }
    // 设备像素吸附（Chromium 同样吸附）：1px 线落在 x.5 上才覆盖整整一个像素，
    // 否则会摊成两列半透明灰。
    final oddWidth = rule.width.round().isOdd;
    for (var index = 1; index < multicol.count; index++) {
      var x = left + multicol.leftOf(index) - multicol.gap / 2;
      x = oddWidth ? (x - 0.5).roundToDouble() + 0.5 : x.roundToDouble();
      _paintSide(canvas, rule, Offset(x, top), Offset(x, bottom));
    }
  }

  /// 外阴影（W2）：blur / spread 支持，多阴影取首个（样式层语义）。
  ///
  /// 形状 = 边框盒 + spread（圆角同比放大，Chromium 口径），再按
  /// (offsetX, offsetY) 平移；blur 用 MaskFilter（σ = blur/2，CSS 口径）。
  /// 外阴影裁掉原始圆角边框盒内部，避免污染透明或半透明背景。
  /// 内阴影由 [_paintInsetBoxShadow] 在背景之后绘制。
  /// 跨页切片不重复投影（首尾都在本页才画）。
  void _paintBoxShadow(Canvas canvas, _SliceGeometry geometry) {
    if (!geometry.startsBlock || !geometry.endsBlock) {
      return;
    }
    _paintOuterShadow(canvas, geometry.containerPaintBox, geometry.style);
  }

  void _paintOuterShadow(Canvas canvas, Rect box, ComputedStyle style) {
    final shadow = style.boxShadow;
    if (shadow == null || shadow.inset) {
      return;
    }
    final borders = style.borders;
    final blur = math.max(0.0, shadow.blur);
    final paint = Paint()..color = shadow.color;
    if (blur > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2);
    }
    final shadowBox = box
        .inflate(shadow.spread)
        .translate(shadow.offsetX, shadow.offsetY);
    canvas.save();
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(box.expandToInclude(shadowBox).inflate(blur * 2 + 1))
        ..addRRect(_shadowRRect(borders, box, 0)),
    );
    canvas.drawRRect(_shadowRRect(borders, shadowBox, shadow.spread), paint);
    canvas.restore();
  }

  /// 内阴影（W2）：裁到 padding-box（Chromium 实测：透明边框下阴影不进入
  /// 边框区域），用「padding-box 外框 − 偏移/收缩后的洞」even-odd 挖洞后
  /// 一起模糊；圆角内阴影按直角洞近似（书内罕见）。
  void _paintInsetBoxShadow(Canvas canvas, _SliceGeometry geometry) {
    if (!geometry.startsBlock || !geometry.endsBlock) {
      return;
    }
    _paintInnerShadow(canvas, geometry.containerPaintBox, geometry.style);
  }

  void _paintInnerShadow(Canvas canvas, Rect box, ComputedStyle style) {
    final shadow = style.boxShadow;
    if (shadow == null || !shadow.inset) {
      return;
    }
    final paddingBox = _deflateByBox(box, style, includePadding: false);
    final blur = math.max(0.0, shadow.blur);
    final hole = paddingBox
        .translate(shadow.offsetX, shadow.offsetY)
        .inflate(-shadow.spread);
    final margin = blur * 2 + 2;
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(paddingBox.inflate(margin))
      ..addRRect(_shadowRRect(style.borders, hole, 0));
    final paint = Paint()..color = shadow.color;
    if (blur > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2);
    }
    canvas.save();
    canvas.clipRect(paddingBox);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  /// 阴影形状：边框盒矩形 + 边框圆角（spread 沿半径同比放大，负值收敛到 0）。
  RRect _shadowRRect(CssBorders borders, Rect rect, double radiusDelta) {
    final radii = borders.radiiFor(rect.size);
    Radius grow(Radius radius) => Radius.elliptical(
      math.max(0, radius.x + radiusDelta),
      math.max(0, radius.y + radiusDelta),
    );
    return RRect.fromRectAndCorners(
      rect,
      topLeft: grow(radii.topLeft),
      topRight: grow(radii.topRight),
      bottomRight: grow(radii.bottomRight),
      bottomLeft: grow(radii.bottomLeft),
    );
  }

  /// 注音复用实际行内样式的基字坐标，并消费作者 rt 的最终样式。
  void _paintRubies(
    Canvas canvas,
    _SliceGeometry geometry,
    List<RubyAnnotation> rubies,
  ) {
    for (final ruby in rubies) {
      final host = _rubyHost(geometry, ruby);
      if (host == null) continue;
      final base = _rubyBaseRange(geometry, host.line, ruby);
      if (base != null) _paintRuby(canvas, geometry, ruby, host, base);
    }
  }

  ({LineBox line, double top})? _rubyHost(
    _SliceGeometry geometry,
    RubyAnnotation ruby,
  ) {
    var top = geometry.y + geometry.leading;
    final layout = geometry.slice.block.layout;
    for (
      var index = geometry.slice.startLine;
      index < geometry.slice.endLine;
      index++
    ) {
      final line = layout.lines[index];
      if (ruby.start >= line.start && ruby.start < line.end) {
        return (line: line, top: top);
      }
      top += line.height;
    }
    return null;
  }

  ({double left, double width})? _rubyBaseRange(
    _SliceGeometry geometry,
    LineBox line,
    RubyAnnotation ruby,
  ) {
    final layout = geometry.slice.block.layout;
    final painter = TextPainter(
      text: _lineSpan(layout, line, geometry.textStyle),
      textDirection: _textDirectionOf(layout),
    )..layout();
    try {
      final boxes = painter.getBoxesForSelection(
        TextSelection(
          baseOffset: ruby.start - line.start,
          extentOffset: math.min(ruby.end, line.end) - line.start,
        ),
      );
      if (boxes.isEmpty) return null;
      final left = boxes.map((box) => box.left).reduce(math.min);
      final right = boxes.map((box) => box.right).reduce(math.max);
      return (left: left, width: right - left);
    } finally {
      painter.dispose();
    }
  }

  TextStyle _rubyTextStyle(RubyAnnotation ruby, TextStyle fallback) =>
      ruby.style == null
      ? fallback.copyWith(
          fontSize: fallback.fontSize == null ? null : fallback.fontSize! * .5,
        )
      : _paintTextStyleFor(ruby.style!);

  void _paintRuby(
    Canvas canvas,
    _SliceGeometry geometry,
    RubyAnnotation ruby,
    ({LineBox line, double top}) host,
    ({double left, double width}) base,
  ) {
    final computed = ruby.style ?? geometry.style;
    final painter = TextPainter(
      text: TextSpan(
        text: ruby.text,
        style: _rubyTextStyle(ruby, geometry.textStyle),
      ),
      textDirection: _textDirectionOf(geometry.slice.block.layout),
    )..layout();
    final slack = base.width - painter.width;
    final offset = computed.rubyAlign == CssRubyAlign.start
        ? (computed.isRtl ? slack : 0.0)
        : slack / 2;
    final top = computed.rubyPosition == CssRubyPosition.under
        ? host.top + host.line.height
        : host.top - painter.height;
    painter.paint(
      canvas,
      Offset(geometry.leftInset + host.line.offsetX + base.left + offset, top),
    );
    painter.dispose();
  }

  /// 表格切片绘制（P9-16）：表格/单元格底色与边框按 CSS 画，
  /// 单元格文字按 padding + border 内缩、按 vertical-align 对齐。
  ///
  /// 不再无条件画 1px 灰色网格线：书籍常用 `td { border: none }` 的
  /// 无框表（时间线/信息卡），统一补灰线会把无框表画成表格栅格。
  void _paintTable(
    Canvas canvas,
    _SliceGeometry geometry,
    TableRenderSpec spec,
    PageContent page,
    Rect pageRect,
  ) {
    final top = geometry.y + geometry.leading;
    // 表格原点与正文左缘对齐（P9-16）：列坐标是表格内的相对坐标，
    // 左内缩（容器内边距）与 margin 必须叠加，否则表格压到页边距外。
    final left = geometry.leftInset;
    // 整表背景已由元素背景阶段绘制，此处仅绘制单元格自身背景。
    for (final cell in spec.cells) {
      final style = cell.style;
      final cellRect = Rect.fromLTWH(
        left + cell.rect.left,
        top + cell.rect.top,
        cell.rect.width,
        cell.rect.height,
      );
      final hideEmpty =
          cell.layout.lineCount == 0 &&
          style.emptyCells == CssEmptyCells.hide &&
          style.borderCollapse == CssBorderCollapse.separate;
      if (!hideEmpty) {
        if (spec.flex) {
          _paintFlexCellBox(canvas, cellRect, style, page, pageRect);
        } else {
          _paintBackground(
            canvas,
            cellRect,
            style,
            startsBlock: true,
            endsBlock: true,
          );
          _paintCellBorders(canvas, cellRect, style.borders);
        }
      }
    }
    for (final cell in spec.cells) {
      if (cell.layout.lineCount == 0) {
        continue;
      }
      final style = cell.style;
      final cellRect = Rect.fromLTWH(
        left + cell.rect.left,
        top + cell.rect.top,
        cell.rect.width,
        cell.rect.height,
      );
      final textOrigin = cell.textOrigin.translate(left, top);
      // 单元格文字同样走主题色策略（P9-23）：书籍没显式声明颜色的格
      // （如 RANK 标签）此前用初始黑色，深色底上直接看不见。
      final textStyleBase = TextLayoutEngine.textStyleFor(style);
      final override = _textColorFor(style);
      final textStyle = override == null
          ? textStyleBase
          : textStyleBase.copyWith(color: override);
      var lineY = textOrigin.dy;
      canvas.save();
      canvas.clipRect(cellRect);
      if (cell.layout.isVertical) {
        // Flex 的竖排子项保留列布局，不能用横排 TextPainter 再画整列文字。
        _paintVerticalColumns(
          canvas,
          cell.layout,
          style,
          textColorOverride: override,
          contentLeft: textOrigin.dx,
          contentTop: lineY,
          startLine: 0,
          endLine: cell.layout.lineCount,
        );
        canvas.restore();
        continue;
      }
      for (var i = 0; i < cell.layout.lineCount; i++) {
        final line = cell.layout.lines[i];
        final text = cell.layout.text.substring(line.start, line.end);
        if (text.isNotEmpty || line.inlineBoxes.isNotEmpty) {
          // 单元格里的行内 span（P9-26）：按 run 组装 span，颜色/字号/边框
          // 才和书籍一致（RANK 金框、标签 chip）。
          final cellRuns = _lineRuns(cell.layout, line);
          final painter =
              TextPainter(
                text:
                    line.spacing == null &&
                        cellRuns.isEmpty &&
                        line.inlineBoxes.isEmpty
                    ? TextSpan(text: text, style: textStyle)
                    : buildLineSpan(
                        layout: cell.layout,
                        line: line,
                        baseStyle: textStyle,
                        styleOf: _paintTextStyleFor,
                      ),
                textDirection: cell.layout.isRtl
                    ? TextDirection.rtl
                    : TextDirection.ltr,
              )..layout(
                // 行已在测量阶段完成换行；单元格绘制的是单行切片，再次按内宽
                // 约束会把行尾字距重新拆成下一行，造成文字重叠或错位。
                // 越界仍由下方 clipRect 兜底。
                maxWidth: double.infinity,
              );
          final textY =
              lineY + textLineBaselineOffset(cell.layout, line, painter);
          final contentLeft = textOrigin.dx;
          // 水平对齐已在排版阶段写入 LineBox.offsetX。绘制器按无限宽重排
          // 后，painter.width 不再代表单元格可用宽度，不能据此二次居中。
          final x = contentLeft + line.offsetX;
          _paintInlineBoxes(
            canvas,
            painter,
            cellRuns,
            x,
            textY - (painter.height - line.height) / 2,
            line: line,
            textAlign: style.textAlign,
            isRtl: cell.layout.isRtl,
          );
          if (line.inlineBoxes.isNotEmpty) {
            _paintInlineBoxPlacements(
              canvas,
              geometry.style,
              line,
              cellRuns,
              x,
              lineY,
            );
          }
          _paintLineText(
            canvas,
            painter,
            text,
            cellRuns,
            textStyle,
            x,
            textY,
            line: line,
            textAlign: style.textAlign,
            isRtl: cell.layout.isRtl,
          );
          painter.dispose();
        }
        lineY += line.height;
      }
      canvas.restore();
    }
  }

  /// Flex 子项保留普通盒的装饰；真实表格仍沿用单元格边框规则。
  void _paintFlexCellBox(
    Canvas canvas,
    Rect rect,
    ComputedStyle style,
    PageContent page,
    Rect pageRect,
  ) {
    _paintOuterShadow(canvas, rect, style);
    _paintBackdropFilter(canvas, (box: rect, style: style), page, pageRect);
    _paintBackground(canvas, rect, style, startsBlock: true, endsBlock: true);
    _paintInnerShadow(canvas, rect, style);
    if (style.borderImage != null) {
      _paintBorderImage(canvas, rect, style);
    } else {
      _paintBorders(canvas, rect, style, fragment: (starts: true, ends: true));
    }
  }

  /// 单元格四边边框（P9-16）：只画可见边，颜色/线型取自单元格样式。
  void _paintCellBorders(Canvas canvas, Rect rect, CssBorders borders) {
    if (borders.top.isVisible) {
      final inset = borders.top.width / 2;
      _paintSide(
        canvas,
        borders.top,
        ui.Offset(rect.left, rect.top + inset),
        ui.Offset(rect.right, rect.top + inset),
        outward: const Offset(0, -1),
      );
    }
    if (borders.bottom.isVisible) {
      final inset = borders.bottom.width / 2;
      _paintSide(
        canvas,
        borders.bottom,
        ui.Offset(rect.left, rect.bottom - inset),
        ui.Offset(rect.right, rect.bottom - inset),
        outward: const Offset(0, 1),
      );
    }
    if (borders.left.isVisible) {
      final inset = borders.left.width / 2;
      _paintSide(
        canvas,
        borders.left,
        ui.Offset(rect.left + inset, rect.top),
        ui.Offset(rect.left + inset, rect.bottom),
        outward: const Offset(-1, 0),
      );
    }
    if (borders.right.isVisible) {
      final inset = borders.right.width / 2;
      _paintSide(
        canvas,
        borders.right,
        ui.Offset(rect.right - inset, rect.top),
        ui.Offset(rect.right - inset, rect.bottom),
        outward: const Offset(1, 0),
      );
    }
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
    final markerImage = _listMarkerImageFor(geometry);
    if (markerImage != null) {
      _paintMarkerImage(
        canvas,
        markerImage,
        boxLeft: geometry.box.left,
        textX: textX,
        lineTop: lineTop,
        lineHeight: lineHeight,
        fontSize: geometry.textStyle.fontSize ?? 0,
      );
      return;
    }
    final painter = TextPainter(
      text: TextSpan(text: marker, style: geometry.textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final x = math.max(
      geometry.box.left + 1,
      geometry.box.left + textX - markerGutter,
    );
    final y = lineTop + (lineHeight - painter.height) / 2;
    // 无序列表的 disc/circle/square：Chromium 不画字体里的项目符号字形
    // （思源宋体的 • 只有 2px），而是画几何图形——直径约 0.4em、中心在
    // 基线上方约 0.43em。这里按同一几何画形状，其余标记（数字/罗马/字母）
    // 仍走文字绘制。显式字符串也按字体字形绘制，即使内容恰好是内建符号。
    final shape = geometry.style.listStyleType == CssListStyleType.custom
        ? null
        : _markerShapeOf(marker);
    final fontSize = geometry.textStyle.fontSize ?? 0;
    if (shape != null && fontSize > 0) {
      final baseline = painter.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      _paintMarkerShape(
        canvas,
        shape,
        left: x,
        baseline: y + baseline,
        fontSize: fontSize,
        color: geometry.textStyle.color ?? const Color(0xFF000000),
      );
      painter.dispose();
      return;
    }
    painter.paint(canvas, Offset(x, y));
    painter.dispose();
  }

  /// 画列表标记图片：等比缩进 1em 方框、右缘贴正文左缘、行盒内垂直居中。
  void _paintMarkerImage(
    Canvas canvas,
    ui.Image image, {
    required double boxLeft,
    required double textX,
    required double lineTop,
    required double lineHeight,
    required double fontSize,
  }) {
    final box = fontSize > 0 ? fontSize : 16.0;
    final width = image.width.toDouble();
    final height = image.height.toDouble();
    if (width <= 0 || height <= 0) {
      return;
    }
    final scale = math.min(box / width, box / height);
    final drawWidth = width * scale;
    final drawHeight = height * scale;
    // 右缘贴正文左缘；版心外无空间时与文字标记一样退到盒内 1px（防止整幅
    // 图片被页边裁掉）。
    final left = math.max(boxLeft + 1, textX - drawWidth);
    final top = lineTop + (lineHeight - drawHeight) / 2;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, width, height),
      Rect.fromLTWH(left, top, drawWidth, drawHeight),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  /// 项目符号字形 → 几何形状；非符号标记返回 null。
  _MarkerShape? _markerShapeOf(String marker) => switch (marker) {
    '•' => _MarkerShape.disc,
    '○' => _MarkerShape.circle,
    '▪' => _MarkerShape.square,
    _ => null,
  };

  /// 按 Chromium 的列表项目符号几何画形状（直径 0.4em、中心在基线上
  /// 0.43em；空心圆再描 1/16em 的边）。
  void _paintMarkerShape(
    Canvas canvas,
    _MarkerShape shape, {
    required double left,
    required double baseline,
    required double fontSize,
    required Color color,
  }) {
    final diameter = fontSize * 0.4;
    final centerY = baseline - fontSize * 0.43;
    final rect = Rect.fromLTWH(
      left,
      centerY - diameter / 2,
      diameter,
      diameter,
    );
    switch (shape) {
      case _MarkerShape.disc:
        canvas.drawOval(rect, Paint()..color = color);
      case _MarkerShape.square:
        canvas.drawRect(rect, Paint()..color = color);
      case _MarkerShape.circle:
        canvas.drawOval(
          rect,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.0, fontSize / 16),
        );
    }
  }

  /// 行内盒（W16）：按布局层 [LineBox.inlineBoxes] 的放置画盒背景/边框与内容。
  ///
  /// 样式优先级：payload 为 [ComputedStyle] 时用 payload；否则回退到插入点
  /// 所在 run 的样式（inline-block span 的样式）。内容：payload 为 [String]
  /// 时按盒居中单行绘制；[PageBlock] 载荷绘制内部文字与嵌套原子盒。
  void _paintInlineBoxPlacements(
    Canvas canvas,
    ComputedStyle baseStyle,
    LineBox line,
    List<_LineRun> runs,
    double x,
    double lineY,
  ) {
    if (line.inlineBoxes.isEmpty) {
      return;
    }
    for (final placement in line.inlineBoxes) {
      if (placement.spec.payload is InlineSpacingEdge) continue;
      final style = _inlineBoxStyleOf(placement, runs) ?? baseStyle;
      final Rect rect;
      if (placement.vertical) {
        // 竖排 placement（W22）：`left` = 列内纵向偏移；`ascent` = 列的右延伸、
        // `descent` = 列的左延伸；盒宽 = ascent + descent，基线取列中线。
        final columnLeft = x + (line.columnX ?? line.offsetX);
        final baselineX = columnLeft + line.width / 2;
        rect = Rect.fromLTWH(
          baselineX - placement.descent,
          lineY + placement.left,
          placement.ascent + placement.descent,
          placement.height,
        );
      } else {
        // ascent 含上外边距；绘制边框盒时须移回 margin 盒内的边框顶。
        rect = Rect.fromLTWH(
          x + placement.left,
          lineY +
              line.baseline -
              line.top -
              placement.ascent +
              placement.spec.marginTop,
          placement.width,
          placement.height,
        );
      }
      // inline-block 盒子同样可能是半透明（payload.style.effectiveOpacity）。
      final opacity = math.min(style.effectiveOpacity, 1.0);
      void paintBox() {
        final layered = opacity < 1;
        if (layered) {
          canvas.saveLayer(
            rect.inflate(8),
            Paint()..color = Color.fromRGBO(255, 255, 255, opacity),
          );
        }
        _paintOuterShadow(canvas, rect, style);
        _paintBackground(
          canvas,
          rect,
          style,
          startsBlock: true,
          endsBlock: true,
          backgroundColorOverride: inkMode && style.backgroundColor.a > 0
              ? _monochromeBackground(style.backgroundColor)
              : null,
          imageColorFilter: inkMode ? _inkImageFilter : null,
        );
        _paintInnerShadow(canvas, rect, style);
        _paintBorders(
          canvas,
          rect,
          style,
          fragment: (starts: true, ends: true),
        );
        final payload = placement.spec.payload;
        if (payload is PageBlock) {
          _paintInlineBoxContent(canvas, payload, rect);
        } else if (payload is String && payload.isNotEmpty) {
          final painter = TextPainter(
            text: TextSpan(text: payload, style: _paintTextStyleFor(style)),
            textDirection: style.isRtl ? TextDirection.rtl : TextDirection.ltr,
            maxLines: 1,
            ellipsis: '…',
          )..layout(maxWidth: rect.width);
          painter.paint(
            canvas,
            Offset(
              rect.left + (rect.width - painter.width) / 2,
              rect.top + (rect.height - painter.height) / 2,
            ),
          );
          painter.dispose();
        }
        if (layered) {
          canvas.restore();
        }
      }

      final clip = style.clipPath;
      if (clip == null) {
        paintBox();
      } else {
        _withClipShape(
          canvas,
          clip,
          _clipReferenceBox(clip, rect, style),
          paintBox,
        );
      }
    }
  }

  /// 行内盒内容（payload = [PageBlock]）：内容盒内逐行画文字与嵌套盒。
  ///
  /// `placement.width/height` 是边框盒尺寸，内容盒要再扣掉 payload 样式的
  /// padding 与边框；行 x = 内容盒左缘 + `line.offsetX`，行 y 自内容盒顶按
  /// `line.height` 累加，行内样式走 runs（颜色/字号/注音等）。
  void _paintInlineBoxContent(Canvas canvas, PageBlock box, Rect borderBox) {
    final style = box.style;
    if (style == null) {
      return;
    }
    final borders = style.borders;
    final padding = style.padding;
    final contentLeft =
        borderBox.left +
        padding.left +
        (borders.left.isVisible ? borders.left.width : 0);
    final contentTop =
        borderBox.top +
        padding.top +
        (borders.top.isVisible ? borders.top.width : 0);
    final contentRight =
        borderBox.right -
        padding.right -
        (borders.right.isVisible ? borders.right.width : 0);
    final contentWidth = math.max(1.0, contentRight - contentLeft);
    final contentBottom =
        borderBox.bottom -
        padding.bottom -
        (borders.bottom.isVisible ? borders.bottom.width : 0);
    final contentBox = Rect.fromLTWH(
      contentLeft,
      contentTop,
      contentWidth,
      math.max(0.0, contentBottom - contentTop),
    );
    // 内容溢出裁剪（T3 契约）：固定高的 inline-block 声明高 < 内容高时
    // `clipsContent` 为真（作者没写 overflow 也裁）；显式 overflow 非 visible
    // 同样裁。裁剪区就是内容盒（= 声明内容高）。
    final clipsContent =
        box.clipsContent || style.overflow != CssOverflow.visible;
    if (clipsContent) {
      canvas.save();
      canvas.clipRect(contentBox);
    }
    final layout = box.layout;
    if (layout.isVertical) {
      // 竖排行内盒内容：同样按列逐字符绘制（内容盒原点传入）。
      _paintVerticalColumns(
        canvas,
        layout,
        style,
        textColorOverride: _textColorFor(style),
        contentLeft: contentLeft,
        contentTop: contentTop,
        startLine: 0,
        endLine: layout.lineCount,
      );
      if (clipsContent) {
        canvas.restore();
      }
      return;
    }
    final textStyleBase = _paintTextStyleFor(style);
    final emphasis = HorizontalTextEmphasis(layout, style, _textColorFor);
    final hasEmphasis = emphasis.hasMarks;
    try {
      for (var lineIndex = 0; lineIndex < layout.lineCount; lineIndex++) {
        final line = layout.lines[lineIndex];
        final text = layout.text.substring(line.start, line.end);
        final runs = _lineRuns(layout, line);
        if (line.inlineBoxes.isNotEmpty) {
          _paintInlineBoxPlacements(
            canvas,
            style,
            line,
            runs,
            contentLeft,
            contentTop + line.top,
          );
        }
        if (text.isNotEmpty) {
          final painter = TextPainter(
            text: runs.isEmpty
                ? TextSpan(text: text, style: textStyleBase)
                : buildLineSpan(
                    layout: layout,
                    line: line,
                    baseStyle: textStyleBase,
                    styleOf: _paintTextStyleFor,
                  ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: contentWidth);
          final origin = Offset(
            contentLeft + line.offsetX,
            contentTop +
                line.top +
                textLineBaselineOffset(layout, line, painter),
          );
          _paintLineText(
            canvas,
            painter,
            text,
            runs,
            textStyleBase,
            origin.dx,
            origin.dy,
            line: line,
            textAlign: style.textAlign,
            isRtl: layout.isRtl,
          );
          if (hasEmphasis) {
            emphasis.paint(canvas, painter, line, origin);
          }
          painter.dispose();
        }
      }
    } finally {
      emphasis.dispose();
    }
    if (clipsContent) {
      canvas.restore();
    }
  }

  /// 行内盒的样式：payload 是 [ComputedStyle] 就用它，否则取插入点所在 run。
  ComputedStyle? _inlineBoxStyleOf(
    InlineBoxPlacement placement,
    List<_LineRun> runs,
  ) {
    final payload = placement.spec.payload;
    if (payload is ComputedStyle) {
      return payload;
    }
    if (payload is PageBlock) {
      return payload.style;
    }
    for (final run in runs) {
      if (placement.offset >= run.start && placement.offset < run.end) {
        return run.style;
      }
    }
    return null;
  }

  /// 普通行内 run 的背景、边框与内边距在文字下方绘制。
  /// 独立行内盒由 placements 绘制，run 在插入点拆段并跟随文字位移。
  ///
  /// 水平 padding/border 已在排版时占宽；按移动后的字形框外扩绘制，
  /// 跨行只在原元素首尾保留侧边。行高不包含行内上下 padding/border。
  void _paintInlineBoxes(
    Canvas canvas,
    TextPainter painter,
    List<_LineRun> runs,
    double x,
    double y, {
    required LineBox line,
    required CssTextAlign textAlign,
    required bool isRtl,
  }) {
    final marginPlan = _InlineMarginPlan(
      runs: runs,
      line: line,
      textAlign: textAlign,
      isRtl: isRtl,
    );
    for (final run in runs) {
      if (run.syntheticFontFallback) {
        continue;
      }
      final style = run.style;
      final hasBackground = style.backgroundColor.a > 0;
      final hasBorder = style.borders.hasBorder;
      if ((!hasBackground && !hasBorder && style.boxShadow == null) ||
          run.end <= run.start) {
        continue;
      }
      final hasHorizontalMargin =
          style.margin.left != 0 || style.margin.right != 0;
      final boxes = _lineRangeRects(
        painter,
        line,
        TextSelection(baseOffset: run.start, extentOffset: run.end),
        heightStyle: hasBorder || hasHorizontalMargin
            ? ui.BoxHeightStyle.tight
            : ui.BoxHeightStyle.includeLineSpacingMiddle,
      ).toList();
      final marginShift = marginPlan.shiftAtOffset(run.start);
      final leadingEdge =
          isRtl ||
          line.vertical ||
          line.inlineBoxes.any(
            (box) =>
                box.offset == run.sourceStart &&
                box.spec.payload == InlineSpacingEdge.leading,
          );
      final trailingEdge =
          isRtl ||
          line.vertical ||
          line.inlineBoxes.any(
            (box) =>
                box.offset == run.sourceEnd &&
                box.spec.payload == InlineSpacingEdge.trailing,
          );
      for (final (index, box) in boxes.indexed) {
        final leading = leadingEdge && index == 0;
        final trailing = trailingEdge && index == boxes.length - 1;
        final paddingBox = Rect.fromLTRB(
          x + box.left + marginShift - (leading ? style.padding.left : 0),
          y + box.top - style.padding.top,
          x + box.right + marginShift + (trailing ? style.padding.right : 0),
          y + box.bottom + style.padding.bottom,
        );
        final borders = style.borders;
        final rect = Rect.fromLTRB(
          paddingBox.left -
              (leading && borders.left.isVisible ? borders.left.width : 0),
          paddingBox.top - (borders.top.isVisible ? borders.top.width : 0),
          paddingBox.right +
              (trailing && borders.right.isVisible ? borders.right.width : 0),
          paddingBox.bottom +
              (borders.bottom.isVisible ? borders.bottom.width : 0),
        );
        _paintOuterShadow(canvas, rect, style);
        if (hasBackground) {
          final radii = style.borders.radiiFor(rect.size);
          final backgroundColor = inkMode
              ? _monochromeBackground(style.backgroundColor)
              : style.backgroundColor;
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              rect,
              topLeft: radii.topLeft,
              topRight: radii.topRight,
              bottomRight: radii.bottomRight,
              bottomLeft: radii.bottomLeft,
            ),
            Paint()..color = backgroundColor,
          );
        }
        _paintInnerShadow(canvas, rect, style);
        if (hasBorder) {
          // 续行不重复画左右边；将缺省侧边移出片段后裁掉，顶部与底部连续。
          final borderRect = Rect.fromLTRB(
            rect.left -
                (!leading && borders.left.isVisible ? borders.left.width : 0),
            rect.top,
            rect.right +
                (!trailing && borders.right.isVisible
                    ? borders.right.width
                    : 0),
            rect.bottom,
          );
          canvas.save();
          canvas.clipRect(rect);
          _paintBorders(
            canvas,
            borderRect,
            style,
            fragment: (starts: true, ends: true),
            // 新圆角环仅用于完整 run；跨行或跨盒片段沿用原有直边路径。
            allowRoundedSolid:
                run.sourceStart >= line.start &&
                run.sourceEnd <= line.end &&
                boxes.length == 1,
          );
          canvas.restore();
        }
      }
    }
  }

  /// `mix-blend-mode` → 画布混合模式；`normal` 返回 null（普通覆盖）。
  static BlendMode? _blendModeOf(CssMixBlendMode mode) => switch (mode) {
    CssMixBlendMode.normal => null,
    CssMixBlendMode.multiply => BlendMode.multiply,
    CssMixBlendMode.screen => BlendMode.screen,
    CssMixBlendMode.overlay => BlendMode.overlay,
    CssMixBlendMode.darken => BlendMode.darken,
    CssMixBlendMode.lighten => BlendMode.lighten,
  };

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
    Color? backgroundColorOverride,
    ColorFilter? imageColorFilter,
  }) {
    // 百分比圆角按盒子尺寸解算（`border-radius: 50%` 的圆形头像）。
    final radii = style.borders.radiiFor(box.size);
    final rounded = RRect.fromRectAndCorners(
      box,
      topLeft: startsBlock ? radii.topLeft : Radius.zero,
      topRight: startsBlock ? radii.topRight : Radius.zero,
      bottomRight: endsBlock ? radii.bottomRight : Radius.zero,
      bottomLeft: endsBlock ? radii.bottomLeft : Radius.zero,
    );
    final roundedCorners =
        rounded.tlRadiusX > 0 ||
        rounded.trRadiusX > 0 ||
        rounded.brRadiusX > 0 ||
        rounded.blRadiusX > 0;
    final layers = style.backgroundLayers;
    final backgroundColor = backgroundColorOverride ?? style.backgroundColor;
    if (backgroundColor.a != 0) {
      // 背景色按 background-clip 裁剪区域绘制（P3：origin/clip 语义）。
      // `mix-blend-mode`（CSS Compositing §5）用画布混合模式与已绘制的
      // 背景内容做混合（multiply/screen/overlay/darken/lighten）。
      final blend = _blendModeOf(style.mixBlendMode);
      canvas.save();
      canvas.clipRect(
        _backgroundClipRect(
          box,
          style,
          layers.isEmpty ? style.backgroundClip : layers.last.clip,
        ),
      );
      canvas.drawRRect(
        rounded,
        Paint()
          ..color = backgroundColor
          ..blendMode = blend ?? BlendMode.srcOver,
      );
      canvas.restore();
    }
    // CSS 多背景：列表首项最靠上，绘制时必须逆序；每层独立解算
    // origin/clip/size/position，缺项由 backgroundLayers 按列表循环补齐。
    for (final layer in layers.reversed) {
      final origin = _backgroundOriginRect(box, style, layer.origin);
      final clip = _backgroundClipRect(box, style, layer.clip);
      canvas.save();
      canvas.clipRect(clip);
      if (roundedCorners) canvas.clipRRect(rounded);
      _paintBackgroundLayer(
        canvas,
        layer,
        origin,
        paintingBounds: layer.repeat.hasSpacing ? clip : null,
        colorFilter: imageColorFilter,
      );
      canvas.restore();
    }
  }

  void _paintBackgroundLayer(
    Canvas canvas,
    CssBackgroundLayer layer,
    Rect bounds, {
    Rect? paintingBounds,
    ColorFilter? colorFilter,
  }) {
    final gradient = layer.gradient;
    if (gradient != null) {
      _paintGradientBackground(
        canvas,
        gradient,
        bounds,
        layer,
        paintingBounds: paintingBounds,
      );
      return;
    }
    final image = _resolveBackgroundImage(layer.image);
    if (image == null) return;
    paintBackgroundImage(
      canvas,
      image,
      bounds,
      repeat: layer.repeat,
      size: layer.size,
      position: layer.position,
      colorFilter: colorFilter,
      paintingBounds: paintingBounds,
    );
  }

  /// 渐变没有固有尺寸或比例；瓦片几何与背景图片使用同一个计算入口。
  void _paintGradientBackground(
    Canvas canvas,
    CssGradient gradient,
    Rect bounds,
    CssBackgroundLayer layer, {
    Rect? paintingBounds,
  }) {
    for (final tile in backgroundTileRects(
      bounds,
      layer,
      paintingBounds: paintingBounds,
    )) {
      final shader = _gradientShader(gradient, tile);
      if (shader != null) {
        canvas.drawRect(tile, Paint()..shader = shader);
      }
    }
  }

  /// 生成渐变 shader；色标不足 2 个时返回 null（按 background-color 降级）。
  ///
  /// 线性渐变（CSS 角度：0deg 向上、顺时针）按规范口径：渐变线过盒子中心，
  /// 长度 = |w·sinθ| + |h·cosθ|。径向渐变默认 farthest-corner：
  /// - circle：半径 = 中心到最远角的距离；
  /// - ellipse：rx = dx·√2、ry = dy·√2（dx/dy 是中心到最远边的距离），
  ///   与 Chromium 实测一致。
  ///
  /// 色标位置交给 [CssGradientStop.fractionOf]：百分比直接给比例、像素/em 按
  /// [extent]（线性 = 渐变线长，径向 = 半径）换算，未声明位置的按 CSS 规则在
  /// 相邻已定位色标间均分。`repeating-*` 用一个周期的归一化色标 + TileMode
  /// 重复平铺。
  Shader? _gradientShader(CssGradient gradient, Rect area) {
    switch (gradient) {
      case CssConicGradient():
        return _conicGradientShader(gradient, area);
      case CssLinearGradient():
        final radians = gradient.angle * math.pi / 180;
        final direction = Offset(math.sin(radians), -math.cos(radians));
        final length =
            area.width * direction.dx.abs() + area.height * direction.dy.abs();
        if (length <= 0) {
          return null;
        }
        final resolved = _resolveGradientStops(
          gradient.stops,
          extent: length,
          repeating: gradient.repeating,
        );
        if (resolved == null) {
          return null;
        }
        final half = direction * (length / 2);
        final begin = area.center - half;
        // 重复渐变：shader 覆盖「一个周期」，两端由 TileMode 继续平铺，
        // 否则周期会被拉长成整条渐变线。
        final cycle = gradient.repeating
            ? math.max(1e-6, resolved.periodFraction * length)
            : length;
        return ui.Gradient.linear(
          begin,
          gradient.repeating ? begin + direction * cycle : area.center + half,
          [for (final stop in resolved.stops) stop.color],
          [for (final stop in resolved.stops) stop.position],
          gradient.repeating ? TileMode.repeated : TileMode.clamp,
        );
      case CssRadialGradient():
        final cx = gradient.centerX.resolve(area.width) ?? area.width / 2;
        final cy = gradient.centerY.resolve(area.height) ?? area.height / 2;
        final center = Offset(area.left + cx, area.top + cy);
        final dx = math.max(cx, area.width - cx);
        final dy = math.max(cy, area.height - cy);
        if (dx <= 0 || dy <= 0) {
          return null;
        }
        final radius = gradient.shape == CssRadialShape.circle
            ? math.sqrt(dx * dx + dy * dy)
            : dx * math.sqrt2;
        // 像素色标按「半径」换算（椭圆的竖直方向半径不同，取水平半径近似）。
        final resolved = _resolveGradientStops(
          gradient.stops,
          extent: radius,
          repeating: gradient.repeating,
        );
        if (resolved == null) {
          return null;
        }
        final colors = [for (final stop in resolved.stops) stop.color];
        final stops = [for (final stop in resolved.stops) stop.position];
        final tileMode = gradient.repeating
            ? TileMode.repeated
            : TileMode.clamp;
        // 重复径向渐变同理：shader 半径取一个周期，向外由 TileMode 平铺。
        final shaderRadius = gradient.repeating
            ? math.max(1e-6, resolved.periodFraction * radius)
            : radius;
        if (gradient.shape == CssRadialShape.circle) {
          return ui.Gradient.radial(
            center,
            shaderRadius,
            colors,
            stops,
            tileMode,
          );
        }
        // 椭圆：radial() 只支持圆，用「渐变空间 y 压缩」把圆压成椭圆：
        // 关于中心缩放 y（倍率 ry/rx），x 不变。
        final ry = dy * math.sqrt2;
        final scaleY = ry / radius;
        final matrix = Float64List.fromList(<double>[
          1, 0, 0, 0, //
          0, scaleY, 0, 0, //
          0, 0, 1, 0, //
          0, center.dy * (1 - scaleY), 0, 1, //
        ]);
        return ui.Gradient.radial(
          center,
          shaderRadius,
          colors,
          stops,
          tileMode,
          matrix,
        );
    }
  }

  Shader? _conicGradientShader(CssConicGradient gradient, Rect area) {
    if (area.isEmpty || gradient.stops.length < 2) return null;
    if (gradient.stops.any(
      (stop) => stop.position != null || stop.positionPx != null,
    )) {
      return null;
    }
    final center = area.center;
    // Skia sweep 从三点方向开始。围绕中心旋转 -90°，而非截取角度区间，
    // 使十二点接缝两侧仍正确回绕到末色/首色。
    final rotation = Float64List.fromList([
      0, -1, 0, 0, //
      1, 0, 0, 0, //
      0, 0, 1, 0, //
      center.dx - center.dy, center.dx + center.dy, 0, 1, //
    ]);
    return ui.Gradient.sweep(
      center,
      [for (final stop in gradient.stops) stop.color],
      [
        for (var index = 0; index < gradient.stops.length; index++)
          index / (gradient.stops.length - 1),
      ],
      TileMode.clamp,
      0,
      2 * math.pi,
      rotation,
    );
  }

  /// 解析色标位置（0–1）：支持百分比与像素（按 [extent] 换算）。
  ///
  /// 普通渐变：首/尾未声明时分别钉在 0 / 1；位置单调递增（后不小于前），
  /// 未声明位置在相邻已定位色标间均分。
  ///
  /// 重复渐变：以最后一个色标为一个周期，把整段位置归一化到 0..1
  /// （TileMode.repeated 只平铺 shader 的 [0,1] 域）；首标不在 0 时先把周期
  /// 平移到从 0 起算。归一化后末标恒为 1，跨周期回绕由平铺完成。
  ({List<({Color color, double position})> stops, double periodFraction})?
  _resolveGradientStops(
    List<CssGradientStop> stops, {
    required double extent,
    required bool repeating,
  }) {
    if (stops.length < 2) {
      return null;
    }
    final count = stops.length;
    final positions = <double?>[
      for (final stop in stops) stop.fractionOf(extent),
    ];
    positions[0] ??= 0;
    if (!repeating) {
      positions[count - 1] ??= 1;
    } else if (positions[count - 1] == null) {
      positions[count - 1] = 1;
    }
    var previous = 0.0;
    for (var i = 0; i < count; i++) {
      final value = positions[i];
      if (value == null) {
        continue;
      }
      final clamped = value < previous ? previous : value;
      positions[i] = clamped;
      previous = clamped;
    }
    // 未定位的连续段：在左右已定位点之间线性均分。
    var cursor = 0;
    while (cursor < count) {
      if (positions[cursor] != null) {
        cursor++;
        continue;
      }
      final start = cursor - 1;
      var end = cursor;
      while (end < count && positions[end] == null) {
        end++;
      }
      final from = positions[start]!;
      final to = positions[end]!;
      final step = (to - from) / (end - start);
      for (var i = cursor; i < end; i++) {
        positions[i] = from + step * (i - start);
      }
      cursor = end;
    }
    final first = positions.first!;
    final period = positions.last! - first;
    if (!repeating) {
      return (
        stops: [
          for (var i = 0; i < count; i++)
            (color: stops[i].color, position: positions[i]!),
        ],
        periodFraction: 1,
      );
    }
    if (period <= 0) {
      return null;
    }
    return (
      stops: [
        for (var i = 0; i < count; i++)
          (color: stops[i].color, position: (positions[i]! - first) / period),
      ],
      periodFraction: period,
    );
  }

  /// 背景裁剪区域：border-box / padding-box / content-box。
  ///
  /// `background-clip: text` 需要按文字轮廓裁剪，当前按 padding-box 降级。
  Rect _backgroundClipRect(
    Rect box,
    ComputedStyle style,
    CssBackgroundClip clip,
  ) {
    switch (clip) {
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
  Rect _backgroundOriginRect(
    Rect box,
    ComputedStyle style,
    CssBackgroundOrigin origin,
  ) {
    switch (origin) {
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
  ui.Image? _resolveBackgroundImage(String? url) {
    final lookup = imageLookup;
    if (url == null || lookup == null) {
      return null;
    }
    return lookup(url);
  }

  /// 画 `border-image` 九宫格（CSS Backgrounds §6.2）。
  ///
  /// 四角拉伸到边框角、四边按 `repeat/round/stretch` 沿边填充、`fill` 时
  /// 补中间；边框宽度取自 `border-width`（`border-image-width` 长属性不解析）。
  /// 图片缺失或无边框宽度时什么都不画（保持 `border` 的透明占位）。
  void _paintBorderImage(Canvas canvas, Rect box, ComputedStyle style) {
    final spec = style.borderImage;
    final lookup = imageLookup;
    if (spec == null || lookup == null) {
      return;
    }
    final borders = style.borders;
    final left = borders.left.width;
    final top = borders.top.width;
    final right = borders.right.width;
    final bottom = borders.bottom.width;
    if (left + right <= 0 || top + bottom <= 0) {
      return;
    }
    final image = lookup(spec.url);
    if (image == null) {
      return;
    }
    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();
    final sliceLeft = spec.slicePercent
        ? spec.sliceLeft * imageWidth
        : spec.sliceLeft;
    final sliceRight = spec.slicePercent
        ? spec.sliceRight * imageWidth
        : spec.sliceRight;
    final sliceTop = spec.slicePercent
        ? spec.sliceTop * imageHeight
        : spec.sliceTop;
    final sliceBottom = spec.slicePercent
        ? spec.sliceBottom * imageHeight
        : spec.sliceBottom;
    final paint = Paint()..filterQuality = FilterQuality.high;

    void drawPart(Rect src, Rect dst) {
      if (dst.width <= 0 ||
          dst.height <= 0 ||
          src.width <= 0 ||
          src.height <= 0) {
        return;
      }
      canvas.drawImageRect(image, src, dst, paint);
    }

    // 四角：源九宫格四角 → 目标边框四角（拉伸）。
    drawPart(
      Rect.fromLTWH(0, 0, sliceLeft, sliceTop),
      Rect.fromLTWH(box.left, box.top, left, top),
    );
    drawPart(
      Rect.fromLTWH(imageWidth - sliceRight, 0, sliceRight, sliceTop),
      Rect.fromLTWH(box.right - right, box.top, right, top),
    );
    drawPart(
      Rect.fromLTWH(0, imageHeight - sliceBottom, sliceLeft, sliceBottom),
      Rect.fromLTWH(box.left, box.bottom - bottom, left, bottom),
    );
    drawPart(
      Rect.fromLTWH(
        imageWidth - sliceRight,
        imageHeight - sliceBottom,
        sliceRight,
        sliceBottom,
      ),
      Rect.fromLTWH(box.right - right, box.bottom - bottom, right, bottom),
    );

    // 四边：源边条 → 目标边条（repeat/round 平铺，stretch 拉伸）。
    final topSrc = Rect.fromLTWH(
      sliceLeft,
      0,
      imageWidth - sliceLeft - sliceRight,
      sliceTop,
    );
    final bottomSrc = Rect.fromLTWH(
      sliceLeft,
      imageHeight - sliceBottom,
      imageWidth - sliceLeft - sliceRight,
      sliceBottom,
    );
    final leftSrc = Rect.fromLTWH(
      0,
      sliceTop,
      sliceLeft,
      imageHeight - sliceTop - sliceBottom,
    );
    final rightSrc = Rect.fromLTWH(
      imageWidth - sliceRight,
      sliceTop,
      sliceRight,
      imageHeight - sliceTop - sliceBottom,
    );
    _paintBorderImageEdge(
      canvas,
      image,
      topSrc,
      Rect.fromLTWH(box.left + left, box.top, box.width - left - right, top),
      spec.repeat,
      horizontal: true,
      paint: paint,
    );
    _paintBorderImageEdge(
      canvas,
      image,
      bottomSrc,
      Rect.fromLTWH(
        box.left + left,
        box.bottom - bottom,
        box.width - left - right,
        bottom,
      ),
      spec.repeat,
      horizontal: true,
      paint: paint,
    );
    _paintBorderImageEdge(
      canvas,
      image,
      leftSrc,
      Rect.fromLTWH(box.left, box.top + top, left, box.height - top - bottom),
      spec.repeat,
      horizontal: false,
      paint: paint,
    );
    _paintBorderImageEdge(
      canvas,
      image,
      rightSrc,
      Rect.fromLTWH(
        box.right - right,
        box.top + top,
        right,
        box.height - top - bottom,
      ),
      spec.repeat,
      horizontal: false,
      paint: paint,
    );

    // fill：中间区域（源九宫格中心 → 内容盒），按边条相同的 repeat 规则平铺。
    if (spec.fill) {
      _paintBorderImageFill(
        canvas,
        image,
        Rect.fromLTWH(
          sliceLeft,
          sliceTop,
          imageWidth - sliceLeft - sliceRight,
          imageHeight - sliceTop - sliceBottom,
        ),
        Rect.fromLTWH(
          box.left + left,
          box.top + top,
          box.width - left - right,
          box.height - top - bottom,
        ),
        spec.repeat,
        naturalWidth: left > 0 && sliceLeft > 0
            ? (imageWidth - sliceLeft - sliceRight) * left / sliceLeft
            : imageWidth - sliceLeft - sliceRight,
        naturalHeight: top > 0 && sliceTop > 0
            ? (imageHeight - sliceTop - sliceBottom) * top / sliceTop
            : imageHeight - sliceTop - sliceBottom,
        paint: paint,
      );
    }
  }

  /// 填充中间九宫格；`fill` 同样受 `border-image-repeat` 控制。
  void _paintBorderImageFill(
    Canvas canvas,
    ui.Image image,
    Rect src,
    Rect dst,
    CssBorderImageRepeat repeat, {
    required double naturalWidth,
    required double naturalHeight,
    required Paint paint,
  }) {
    if (dst.width <= 0 ||
        dst.height <= 0 ||
        src.width <= 0 ||
        src.height <= 0) {
      return;
    }
    if (repeat == CssBorderImageRepeat.stretch) {
      canvas.drawImageRect(image, src, dst, paint);
      return;
    }
    final countX = _borderImageTileCount(repeat, dst.width, naturalWidth);
    final countY = _borderImageTileCount(repeat, dst.height, naturalHeight);
    final pieceWidth = repeat == CssBorderImageRepeat.round
        ? dst.width / countX
        : naturalWidth;
    final pieceHeight = repeat == CssBorderImageRepeat.round
        ? dst.height / countY
        : naturalHeight;
    canvas.save();
    canvas.clipRect(dst);
    for (var y = 0; y < countY; y++) {
      for (var x = 0; x < countX; x++) {
        canvas.drawImageRect(
          image,
          src,
          Rect.fromLTWH(
            dst.left + pieceWidth * x,
            dst.top + pieceHeight * y,
            pieceWidth,
            pieceHeight,
          ),
          paint,
        );
      }
    }
    canvas.restore();
  }

  int _borderImageTileCount(
    CssBorderImageRepeat repeat,
    double target,
    double natural,
  ) {
    if (natural <= 0 || target <= 0) {
      return 1;
    }
    final ratio = target / natural;
    return repeat == CssBorderImageRepeat.round
        ? math.max(1, ratio.round())
        : math.max(1, ratio.ceil());
  }

  /// 边条填充：`stretch` 一次拉满；`repeat/round/space` 沿边平铺。
  void _paintBorderImageEdge(
    Canvas canvas,
    ui.Image image,
    Rect src,
    Rect dst,
    CssBorderImageRepeat repeat, {
    required bool horizontal,
    required Paint paint,
  }) {
    if (dst.width <= 0 || dst.height <= 0) {
      return;
    }
    if (repeat == CssBorderImageRepeat.stretch) {
      canvas.drawImageRect(image, src, dst, paint);
      return;
    }
    // 边条先按边框厚度等比缩放，再以缩放后的尺寸平铺；直接用源图像素
    // 会让 25% 切割、16px 边框之类的组合密集成两倍以上。
    final natural = horizontal
        ? src.width * dst.height / src.height
        : src.height * dst.width / src.width;
    final target = horizontal ? dst.width : dst.height;
    if (natural <= 0) {
      return;
    }
    final count = _borderImageTileCount(repeat, target, natural);
    final piece = target / count;
    canvas.save();
    canvas.clipRect(dst);
    for (var i = 0; i < count; i++) {
      final start = horizontal ? dst.left + piece * i : dst.top + piece * i;
      final part = horizontal
          ? Rect.fromLTWH(start, dst.top, piece, dst.height)
          : Rect.fromLTWH(dst.left, start, dst.width, piece);
      canvas.drawImageRect(image, src, part, paint);
    }
    canvas.restore();
  }

  /// 画四边边框：贴合块边界，不改变行布局（§65 边框不侵占行布局）。
  void _paintBorders(
    Canvas canvas,
    Rect box,
    ComputedStyle style, {
    required ({bool starts, bool ends}) fragment,
    bool allowRoundedSolid = true,
  }) {
    final startsBlock = fragment.starts;
    final endsBlock = fragment.ends;
    final borders = style.borders;
    if (!borders.hasBorder) {
      return;
    }
    if (_paintJoinedThreeDBorders(
      canvas,
      box,
      borders,
      startsBlock,
      endsBlock,
    )) {
      return;
    }
    if (_paintJoinedDoubleBorders(
      canvas,
      box,
      borders,
      startsBlock,
      endsBlock,
    )) {
      return;
    }
    // 四边一致且实线：整块（首尾都在本页）用整框描边，圆角生效
    //（与阅微整框描边路径一致）。
    if (borders.isUniform && borders.top.style == CssBorderStyle.solid) {
      if (startsBlock && endsBlock) {
        final half = borders.top.width / 2;
        final radii = borders.radiiFor(box.size);
        Radius inset(Radius radius) => Radius.elliptical(
          math.max(0, radius.x - half),
          math.max(0, radius.y - half),
        );
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            box.deflate(half),
            topLeft: inset(radii.topLeft),
            topRight: inset(radii.topRight),
            bottomRight: inset(radii.bottomRight),
            bottomLeft: inset(radii.bottomLeft),
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
        outward: const Offset(-1, 0),
      );
      _paintSide(
        canvas,
        borders.right,
        Offset(box.right - borders.right.width / 2, box.top),
        Offset(box.right - borders.right.width / 2, box.bottom),
        outward: const Offset(1, 0),
      );
      if (startsBlock) {
        final inset = borders.top.width / 2;
        _paintSide(
          canvas,
          borders.top,
          Offset(box.left, box.top + inset),
          Offset(box.right, box.top + inset),
          outward: const Offset(0, -1),
        );
      }
      if (endsBlock) {
        final inset = borders.bottom.width / 2;
        _paintSide(
          canvas,
          borders.bottom,
          Offset(box.left, box.bottom - inset),
          Offset(box.right, box.bottom - inset),
          outward: const Offset(0, 1),
        );
      }
      return;
    }
    if (allowRoundedSolid &&
        _paintRoundedSolidBorders(
          canvas,
          box,
          borders,
          startsBlock,
          endsBlock,
        )) {
      return;
    }
    if (_paintJoinedSolidBorders(
      canvas,
      box,
      borders,
      startsBlock,
      endsBlock,
    )) {
      return;
    }
    // 非实线边框沿边描画；实线交接由上面的斜角多边形处理。
    if (startsBlock) {
      final inset = borders.top.width / 2;
      _paintSide(
        canvas,
        borders.top,
        Offset(box.left, box.top + inset),
        Offset(box.right, box.top + inset),
        outward: const Offset(0, -1),
      );
    }
    if (endsBlock) {
      final inset = borders.bottom.width / 2;
      _paintSide(
        canvas,
        borders.bottom,
        Offset(box.left, box.bottom - inset),
        Offset(box.right, box.bottom - inset),
        outward: const Offset(0, 1),
      );
    }
    _paintSide(
      canvas,
      borders.left,
      Offset(box.left + borders.left.width / 2, box.top),
      Offset(box.left + borders.left.width / 2, box.bottom),
      outward: const Offset(-1, 0),
    );
    _paintSide(
      canvas,
      borders.right,
      Offset(box.right - borders.right.width / 2, box.top),
      Offset(box.right - borders.right.width / 2, box.bottom),
      outward: const Offset(1, 0),
    );
  }

  /// 双线边框画成两个同心圆角环。逐边画线会在四角形成交叉或缺口，
  /// 也无法正确应用作者声明的 border-radius。
  bool _paintJoinedDoubleBorders(
    Canvas canvas,
    Rect box,
    CssBorders borders,
    bool starts,
    bool ends,
  ) {
    if (!starts ||
        !ends ||
        !borders.isUniform ||
        borders.top.style != CssBorderStyle.double) {
      return false;
    }
    final side = borders.top;
    final stripe = side.width / 3;
    final radii = borders.radiiFor(box.size);
    Radius insetRadius(Radius radius, double inset) => Radius.elliptical(
      math.max(0, radius.x - inset),
      math.max(0, radius.y - inset),
    );

    void paintRing(double inset) {
      final ring = box.deflate(inset);
      if (ring.width <= 0 || ring.height <= 0) {
        return;
      }
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          ring,
          topLeft: insetRadius(radii.topLeft, inset),
          topRight: insetRadius(radii.topRight, inset),
          bottomRight: insetRadius(radii.bottomRight, inset),
          bottomLeft: insetRadius(radii.bottomLeft, inset),
        ),
        Paint()
          ..color = side.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stripe,
      );
    }

    paintRing(stripe / 2);
    paintRing(side.width - stripe / 2);
    return true;
  }

  /// 3D 边框按 Chromium 的同心斜接几何绘制。外半和内半分别成环，
  /// 避免四条独立直线在角部留下深色接缝；块跨页时退回逐边绘制。
  bool _paintJoinedThreeDBorders(
    Canvas canvas,
    Rect box,
    CssBorders borders,
    bool starts,
    bool ends,
  ) {
    final sides = [borders.top, borders.right, borders.bottom, borders.left];
    if (!starts ||
        !ends ||
        !sides.any((side) => side.isVisible) ||
        sides.any(
          (side) =>
              side.isVisible &&
              side.style != CssBorderStyle.groove &&
              side.style != CssBorderStyle.ridge &&
              side.style != CssBorderStyle.inset &&
              side.style != CssBorderStyle.outset,
        )) {
      return false;
    }
    final mid = Rect.fromLTRB(
      box.left + borders.left.width / 2,
      box.top + borders.top.width / 2,
      box.right - borders.right.width / 2,
      box.bottom - borders.bottom.width / 2,
    );
    final inner = Rect.fromLTRB(
      box.left + borders.left.width,
      box.top + borders.top.width,
      box.right - borders.right.width,
      box.bottom - borders.bottom.width,
    );

    _paintThreeDRing(canvas, box, mid, sides, outerHalf: true);
    _paintThreeDRing(canvas, mid, inner, sides, outerHalf: false);
    return true;
  }

  void _paintThreeDRing(
    Canvas canvas,
    Rect outer,
    Rect inner,
    List<CssBorderSide> sides, {
    required bool outerHalf,
  }) {
    final outerCorners = [
      outer.topLeft,
      outer.topRight,
      outer.bottomRight,
      outer.bottomLeft,
    ];
    final innerCorners = [
      inner.topLeft,
      inner.topRight,
      inner.bottomRight,
      inner.bottomLeft,
    ];
    for (var index = 0; index < 4; index++) {
      final side = sides[index];
      if (!side.isVisible) {
        continue;
      }
      final next = (index + 1) % 4;
      final path = Path()
        ..moveTo(outerCorners[index].dx, outerCorners[index].dy)
        ..lineTo(outerCorners[next].dx, outerCorners[next].dy)
        ..lineTo(innerCorners[next].dx, innerCorners[next].dy)
        ..lineTo(innerCorners[index].dx, innerCorners[index].dy)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = _threeDColor(side, index, outerHalf: outerHalf)
          ..isAntiAlias = false,
      );
    }
  }

  /// 同色实线以外内圆角环相减，零宽邻边也保留完整的转角曲线。
  bool _paintRoundedSolidBorders(
    Canvas canvas,
    Rect box,
    CssBorders borders,
    bool starts,
    bool ends,
  ) {
    if (!starts || !ends || !borders.hasRadius) return false;
    final sides = [
      borders.top,
      borders.right,
      borders.bottom,
      borders.left,
    ].where((side) => side.isVisible).toList();
    if (sides.any(
      (side) =>
          side.style != CssBorderStyle.solid || side.color != sides.first.color,
    )) {
      return false;
    }
    canvas.drawPath(
      _roundedBorderRing(box, borders),
      Paint()..color = sides.first.color,
    );
    return true;
  }

  Path _roundedBorderRing(Rect box, CssBorders borders) {
    double width(CssBorderSide side) => side.isVisible ? side.width : 0;
    final insets = EdgeInsets.fromLTRB(
      width(borders.left),
      width(borders.top),
      width(borders.right),
      width(borders.bottom),
    );
    final outer = _shadowRRect(borders, box, 0).scaleRadii();
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(outer);
    if (box.width > insets.horizontal && box.height > insets.vertical) {
      path.addRRect(_insetBorderRRect(outer, insets));
    }
    return path;
  }

  RRect _insetBorderRRect(RRect outer, EdgeInsets insets) {
    Radius inset(Radius radius, double x, double y) =>
        Radius.elliptical(math.max(0, radius.x - x), math.max(0, radius.y - y));
    return RRect.fromRectAndCorners(
      Rect.fromLTRB(
        outer.left + insets.left,
        outer.top + insets.top,
        outer.right - insets.right,
        outer.bottom - insets.bottom,
      ),
      topLeft: inset(outer.tlRadius, insets.left, insets.top),
      topRight: inset(outer.trRadius, insets.right, insets.top),
      bottomRight: inset(outer.brRadius, insets.right, insets.bottom),
      bottomLeft: inset(outer.blRadius, insets.left, insets.bottom),
    );
  }

  /// 不同宽度或颜色的实线边框在外角与内角之间斜接，避免矩形互相覆盖。
  bool _paintJoinedSolidBorders(
    Canvas canvas,
    Rect box,
    CssBorders borders,
    bool starts,
    bool ends,
  ) {
    final sides = [borders.top, borders.right, borders.bottom, borders.left];
    if (sides.any(
      (side) =>
          side.isVisible &&
          side.color.a > 0 &&
          side.style != CssBorderStyle.solid,
    )) {
      return false;
    }
    final inner = Rect.fromLTRB(
      box.left + (borders.left.isVisible ? borders.left.width : 0),
      box.top + (starts && borders.top.isVisible ? borders.top.width : 0),
      box.right - (borders.right.isVisible ? borders.right.width : 0),
      box.bottom -
          (ends && borders.bottom.isVisible ? borders.bottom.width : 0),
    );
    final corners = [
      box.topLeft,
      box.topRight,
      box.bottomRight,
      box.bottomLeft,
    ];
    final inside = [
      inner.topLeft,
      inner.topRight,
      inner.bottomRight,
      inner.bottomLeft,
    ];
    for (var index = 0; index < 4; index++) {
      if (!sides[index].isVisible ||
          (index == 0 && !starts) ||
          (index == 2 && !ends)) {
        continue;
      }
      final next = (index + 1) % 4;
      final path = Path()
        ..moveTo(corners[index].dx, corners[index].dy)
        ..lineTo(corners[next].dx, corners[next].dy)
        ..lineTo(inside[next].dx, inside[next].dy)
        ..lineTo(inside[index].dx, inside[index].dy)
        ..close();
      canvas.drawPath(path, Paint()..color = sides[index].color);
    }
    return true;
  }

  /// 画一条边：实线/虚线/点线/双线。
  void _paintSide(
    Canvas canvas,
    CssBorderSide side,
    Offset start,
    Offset end, {
    Offset? outward,
  }) {
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
        // Chromium 实测（dpr=4，1～8px）：3～8px 线宽 dash = 2×宽、gap = 宽；
        // 1～2px 细线改用 3×宽 / 2×宽（细线保持可辨识的段长）。
        if (side.width < 3) {
          _paintDashes(
            canvas,
            start,
            end,
            paint,
            side.width * 3,
            side.width * 2,
          );
        } else {
          _paintDashes(canvas, start, end, paint, side.width * 2, side.width);
        }
      case CssBorderStyle.dotted:
        // Chromium 实测：方点 = 线宽、gap = 线宽（butt 端头，圆头会外溢半宽）。
        _paintDashes(canvas, start, end, paint, side.width, side.width);
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
      case CssBorderStyle.groove:
      case CssBorderStyle.ridge:
      case CssBorderStyle.inset:
      case CssBorderStyle.outset:
        // 跨页切片缺少另一边时退回实线。
        if (outward == null || side.width < 2) {
          canvas.drawLine(start, end, paint);
          break;
        }
        final half = side.width / 2;
        final sideIndex = outward.dy < 0
            ? 0
            : outward.dx > 0
            ? 1
            : outward.dy > 0
            ? 2
            : 3;
        final outerColor = _threeDColor(side, sideIndex, outerHalf: true);
        final innerColor = _threeDColor(side, sideIndex, outerHalf: false);
        final outerPaint = Paint()
          ..color = outerColor
          ..strokeWidth = half
          ..strokeCap = StrokeCap.butt;
        final innerPaint = Paint()
          ..color = innerColor
          ..strokeWidth = half
          ..strokeCap = StrokeCap.butt;
        final shift = outward * (half / 2);
        canvas.drawLine(start + shift, end + shift, outerPaint);
        canvas.drawLine(start - shift, end - shift, innerPaint);
      case CssBorderStyle.none:
        break;
    }
  }

  /// Chromium `Color::Dark()/Light()` 及 inset/outset 取色规则。
  static Color _threeDColor(
    CssBorderSide side,
    int sideIndex, {
    required bool outerHalf,
  }) {
    final insetLike = side.style == CssBorderStyle.inset;
    final outsetLike = side.style == CssBorderStyle.outset;
    final topOrLeft = sideIndex == 0 || sideIndex == 3;
    if (insetLike || outsetLike) {
      final darken = (side.style == CssBorderStyle.inset) == topOrLeft;
      return _insetOutsetColor(side.color, darken: darken);
    }
    final dark = side.style == CssBorderStyle.groove
        ? topOrLeft == outerHalf
        : topOrLeft != outerHalf;
    return dark ? _darken(side.color) : _lighten(side.color);
  }

  /// Chromium `CalculateInsetOutsetColor()`：极暗色改用提亮来增加对比度，
  /// 极亮色保持原色，其余沿用 Dark/Light 的 33% 色阶。
  static Color _insetOutsetColor(Color color, {required bool darken}) {
    final luminance = _relativeLuminance(color);
    if (luminance <= 0.014443844) {
      final lightened = _lighten(color);
      return darken ? lightened : _lighten(lightened);
    }
    if (darken) {
      return _darken(color);
    }
    return luminance > 0.83077 ? color : _lighten(color);
  }

  static double _relativeLuminance(Color color) {
    double linearize(double value) => value <= 0.04045
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * linearize(color.r) +
        0.7152 * linearize(color.g) +
        0.0722 * linearize(color.b);
  }

  static Color _darken(Color color) {
    final maxValue = math.max(color.r, math.max(color.g, color.b));
    if (maxValue == 1 && color.a == 1) {
      return const Color(0xFFABABAB);
    }
    final factor = maxValue == 0
        ? 0.0
        : math.max(0.0, maxValue - 0.33) / maxValue;
    return _scaleRgb(color, factor);
  }

  static Color _lighten(Color color) {
    if (color.r == 0 && color.g == 0 && color.b == 0 && color.a == 1) {
      return const Color(0xFF545454);
    }
    final maxValue = math.max(color.r, math.max(color.g, color.b));
    if (maxValue == 0) {
      return _scaleRgb(const Color(0xFF545454), 1, alpha: color.a);
    }
    final factor = math.min(1.0, maxValue + 0.33) / maxValue;
    return _scaleRgb(color, factor);
  }

  static Color _scaleRgb(Color color, double factor, {double? alpha}) =>
      Color.from(
        alpha: alpha ?? color.a,
        red: (color.r * factor).clamp(0.0, 1.0),
        green: (color.g * factor).clamp(0.0, 1.0),
        blue: (color.b * factor).clamp(0.0, 1.0),
      );

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

  /// 沿圆角路径画虚线/点线；直边仍由 [_paintDashes] 保持 Chromium 的逐边相位。
  void _paintPathDashes(
    Canvas canvas,
    ui.Path path,
    Paint paint,
    double dash,
    double gap,
  ) {
    if (dash <= 0) {
      return;
    }
    for (final metric in path.computeMetrics()) {
      var position = 0.0;
      while (position < metric.length) {
        final end = math.min(position + dash, metric.length);
        canvas.drawPath(metric.extractPath(position, end), paint);
        position = end + gap;
      }
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
    Color? textColorOverride,
    TextLayoutResult? paintingLayout,
  }) {
    TextPainter build() => TextPainter(
      text: _lineSpan(
        paintingLayout ?? layout,
        line,
        baseStyle,
        punctCompression: punctCompression,
        textAutospace: textAutospace,
        textColorOverride: textColorOverride,
      ),
      // 方向必须与布局层一致：RTL 段落测量按 rtl，绘制也要 rtl，
      // 否则字形视觉顺序会反过来（61-logical-properties）。
      textDirection: _textDirectionOf(layout),
    )..layout();
    final cache = paragraphCache;
    if (cache == null) {
      return build();
    }
    final key =
        'spacing=$textSpacingRevision|'
        '${page.spineIndex}:${page.pageIndex}:$sliceIndex:$lineIndex:'
        '${baseStyle.fontSize}:${baseStyle.height}:'
        '${baseStyle.letterSpacing}:${baseStyle.wordSpacing}:'
        '${baseStyle.color?.toARGB32()}:'
        '${textColorOverride?.toARGB32()}:'
        '${line.justifyExtra}:'
        '${identityHashCode(layout)}:${baseStyle.hashCode}:'
        '${line.start}:${line.end}:${line.spacing?.fingerprint}'
        '${_textOverlayPaintKey(paintingLayout, line)}';
    return cache.obtain(key, build: build);
  }

  String _textOverlayPaintKey(TextLayoutResult? layout, LineBox line) {
    if (layout == null) return '';
    return '|overlay=${[for (final run in layout.runs)
      if (run.start < line.end && run.end > line.start) '${run.start}:${run.end}:${run.style.color.toARGB32()}'].join(';')}';
  }

  /// 竖排文本：按列逐字符绘制（W22，CSS Writing Modes）。
  ///
  /// - 每行 = 一列：`columnX` 是列左缘（相对块内容左缘），`width` 是列宽
  ///   （= 行高），列内字符自上而下；
  /// - 纵向 advance 与正立/旋转由布局的
  ///   [TextLayoutEngine.verticalGlyphMetrics] 给出（列长 = 逐字 advance 和，
  ///   绘制端不再自己测量）；
  /// - 正立（CJK/假名，或 `text-orientation: upright`）：字形居中于列宽；
  /// - 旋转（拉丁/数字，`mixed`；或 `sideways` 全部）：顺时针 90°，让字面朝
  ///   右（vertical-rl 阅读方向），旋转后横向宽度铺满列宽。
  ///
  /// 注音不在这里画（由独立注音趟绘制，可越出块盒）。
  void _paintVerticalColumns(
    Canvas canvas,
    TextLayoutResult layout,
    ComputedStyle style, {
    required Color? textColorOverride,
    required double contentLeft,
    required double contentTop,
    required int startLine,
    required int endLine,
  }) {
    final metrics = _verticalMetricsFor(layout, style);
    if (metrics.isEmpty) {
      return;
    }
    final baseStyle = _withoutDecoration(TextLayoutEngine.textStyleFor(style));
    final effectiveBase = textColorOverride == null
        ? baseStyle
        : baseStyle.copyWith(color: textColorOverride);
    final runs = layout.runs;
    for (var lineIndex = startLine; lineIndex < endLine; lineIndex++) {
      final column = layout.lines[lineIndex];
      if (!column.vertical) {
        continue;
      }
      final columnLeft = contentLeft + (column.columnX ?? column.offsetX);
      final columnWidth = column.width;
      var y = contentTop;
      for (final metric in metrics) {
        if (metric.start < column.start) {
          continue;
        }
        if (metric.start >= column.end) {
          break;
        }
        final text = layout.text.substring(metric.start, metric.end);
        if (text.isEmpty) {
          continue;
        }
        final runStyle = _runStyleAtOffset(runs, metric.start);
        final glyphStyle = runStyle ?? style;
        final textStyle = runStyle == null
            ? effectiveBase
            : _verticalStyleOf(runStyle, _textColorFor(runStyle));
        // 装饰线（竖排沿列方向画纵线；位置按 Chromium 实测：下划线 0.13 列宽、
        // 删除线列中线、上划线另一侧），逐字画段自然连成整条。
        _paintVerticalDecoration(
          canvas,
          glyphStyle,
          textColorOverride,
          columnLeft: columnLeft,
          columnWidth: columnWidth,
          top: y,
          advance: metric.advance,
        );
        _paintVerticalGlyph(
          canvas,
          text,
          textStyle,
          upright: metric.upright,
          columnLeft: columnLeft,
          columnWidth: columnWidth,
          y: y,
          advance: metric.advance,
          textDirection: _textDirectionOf(layout),
          combine: metric.combine,
        );
        // 着重号（竖排画在列的右侧，Chromium 实测 x ≈ 列右缘）。
        _paintVerticalEmphasis(
          canvas,
          glyphStyle,
          textColorOverride,
          columnLeft: columnLeft,
          columnWidth: columnWidth,
          centerY: y + metric.advance / 2,
        );
        y += metric.advance;
      }
      // 列末省略号/连字符（布局只计宽不画字）：旋转 90° 后接在列尾。
      final tailWidth = column.ellipsized
          ? column.ellipsisWidth
          : (column.hyphenated ? column.hyphenWidth : 0.0);
      if (tailWidth > 0) {
        _paintVerticalGlyph(
          canvas,
          column.ellipsized ? '…' : '-',
          effectiveBase,
          upright: false,
          columnLeft: columnLeft,
          columnWidth: columnWidth,
          y: y,
          advance: tailWidth,
          textDirection: _textDirectionOf(layout),
        );
        y += tailWidth;
      }
    }

    // 注音由独立注音趟绘制（可越出块盒，见 paint 主循环）。
  }

  List<VerticalGlyphMetric> _verticalMetricsFor(
    TextLayoutResult layout,
    ComputedStyle style,
  ) {
    final metrics = TextLayoutEngine.verticalGlyphMetrics(layout.text, style);
    if (!layout.runs.any(
      (run) => run.style.layoutFingerprint != style.layoutFingerprint,
    )) {
      return metrics;
    }
    return [
      for (final metric in metrics)
        _verticalMetricForRun(layout, style, metric),
    ];
  }

  VerticalGlyphMetric _verticalMetricForRun(
    TextLayoutResult layout,
    ComputedStyle style,
    VerticalGlyphMetric metric,
  ) {
    final runStyle = _runStyleAtOffset(layout.runs, metric.start) ?? style;
    if (runStyle.layoutFingerprint == style.layoutFingerprint) return metric;
    final text = layout.text.substring(metric.start, metric.end);
    final measured = TextLayoutEngine.verticalGlyphMetrics(text, runStyle);
    final advance = metric.combine
        ? runStyle.fontSize
        : measured.fold(0.0, (sum, item) => sum + item.advance);
    return VerticalGlyphMetric(
      start: metric.start,
      end: metric.end,
      advance: math.max(0, advance + runStyle.letterSpacing),
      upright: metric.upright,
      combine: metric.combine,
    );
  }

  /// 竖排画一个字形（正立居中 / 顺时针旋转 90°）。
  void _paintVerticalGlyph(
    Canvas canvas,
    String text,
    TextStyle textStyle, {
    required bool upright,
    required double columnLeft,
    required double columnWidth,
    required double y,
    required double advance,
    required TextDirection textDirection,
    bool combine = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: textDirection,
    )..layout();
    if (upright) {
      // 縦中横：多位数字横排塞进列宽（CSS Writing Modes §9.1），超出时按列宽
      // 等比缩小并保持居中。
      final scale = combine && painter.width > columnWidth
          ? columnWidth / painter.width
          : 1.0;
      final center = Offset(columnLeft + columnWidth / 2, y + advance / 2);
      canvas.save();
      if (scale != 1.0) {
        canvas.translate(center.dx, center.dy);
        canvas.scale(scale);
        canvas.translate(-center.dx, -center.dy);
      }
      // 正立：横向居中于列宽，纵向让字形盒中心落在本次 advance 的中点。
      painter.paint(
        canvas,
        Offset(
          columnLeft + (columnWidth - painter.width) / 2,
          y - (painter.height - advance) / 2,
        ),
      );
      canvas.restore();
    } else {
      // 旋转 90°（顺时针）：旋转后横向占位 = 原行高、纵向占位 = 原字宽。
      canvas.save();
      canvas.translate(columnLeft + columnWidth / 2, y + advance / 2);
      canvas.rotate(math.pi / 2);
      canvas.translate(-painter.width / 2, -painter.height / 2);
      painter.paint(canvas, Offset.zero);
      canvas.restore();
    }
    painter.dispose();
  }

  /// 竖排装饰线：沿列方向的纵向线段（Chromium 实测口径）。
  ///
  /// - 下划线：x = 列左缘 + 0.13 × 列宽（字形盒左侧内侧）；
  /// - 删除线：x = 列中线；
  /// - 上划线：镜像到右侧对称位置；
  /// - 线宽 = max(1, floor(字号 / 10))，颜色取 `text-decoration-color`。
  void _paintVerticalDecoration(
    Canvas canvas,
    ComputedStyle style,
    Color? textColorOverride, {
    required double columnLeft,
    required double columnWidth,
    required double top,
    required double advance,
  }) {
    final decoration = style.textDecoration;
    if (decoration == CssTextDecoration.none || advance <= 0) {
      return;
    }
    final color = style.textDecorationColor ?? textColorOverride ?? style.color;
    final thickness = math
        .max(1.0, (style.fontSize / 10).floorToDouble())
        .toDouble();
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness;
    void line(double x) {
      canvas.drawLine(Offset(x, top), Offset(x, top + advance), paint);
    }

    if (decoration.hasUnderline) {
      line(columnLeft + columnWidth * 0.13);
    }
    if (decoration.hasLineThrough) {
      line(columnLeft + columnWidth / 2);
    }
    if (decoration.hasOverline) {
      line(columnLeft + columnWidth * 0.87);
    }
  }

  /// 竖排着重号：画在列右侧（Chromium 实测 x ≈ 列右缘），y 取字符中心。
  void _paintVerticalEmphasis(
    Canvas canvas,
    ComputedStyle style,
    Color? textColorOverride, {
    required double columnLeft,
    required double columnWidth,
    required double centerY,
  }) {
    final emphasis = style.textEmphasisStyle;
    if (emphasis == CssTextEmphasisStyle.none) {
      return;
    }
    final radius = _emphasisRadius(style.fontSize, emphasis);
    final paint = Paint()
      ..color = style.textEmphasisColor ?? textColorOverride ?? style.color
      ..strokeCap = StrokeCap.round;
    // over → 列右缘；under → 列左缘（竖排的 over 侧就是右）。
    final centerX = style.textEmphasisPosition.isVerticalLeft
        ? columnLeft + radius + 1
        : columnLeft + columnWidth - radius - 1;
    _paintEmphasisMark(
      canvas,
      emphasis,
      Offset(centerX, centerY),
      style.fontSize,
      paint,
    );
  }

  /// 竖排注音：注音文本放在列右侧（Chromium 实测注音中心 ≈ 列右缘），
  /// 沿被注音字符的纵向范围居中、逐字正立堆叠（字号 50%）。
  void _paintVerticalRubies(
    Canvas canvas,
    TextLayoutResult layout,
    ComputedStyle style,
    List<RubyAnnotation> rubies, {
    required double contentLeft,
    required double contentTop,
    required int startLine,
    required int endLine,
    required List<VerticalGlyphMetric> metrics,
  }) {
    for (final ruby in rubies) {
      final computed = ruby.style ?? style;
      final rubyStyle = _rubyTextStyle(
        ruby,
        TextLayoutEngine.textStyleFor(style),
      );
      final rubySize = rubyStyle.fontSize ?? style.fontSize * .5;
      for (var lineIndex = startLine; lineIndex < endLine; lineIndex++) {
        final column = layout.lines[lineIndex];
        if (!column.vertical) {
          continue;
        }
        if (ruby.start < column.start || ruby.start >= column.end) {
          continue;
        }
        final columnLeft = contentLeft + (column.columnX ?? column.offsetX);
        // 被注音字符的纵向范围。
        var y = contentTop;
        var top = double.nan;
        var bottom = double.nan;
        for (final metric in metrics) {
          if (metric.start < column.start) {
            continue;
          }
          if (metric.start >= column.end) {
            break;
          }
          if (metric.start >= ruby.start && metric.end <= ruby.end) {
            if (top.isNaN) {
              top = y;
            }
            bottom = y + metric.advance;
          }
          y += metric.advance;
        }

        if (top.isNaN || bottom.isNaN || bottom <= top) {
          continue;
        }
        // 注音逐字正立堆叠，整体在字符范围居中。
        final advanceTotal = ruby.text.runes.length * rubySize;
        var rubyY = top + (bottom - top - advanceTotal) / 2;
        // 注音用一个宽度 = 注音字号的虚拟列贴在列的一侧（CSS Ruby 1 §5）：
        // `over` 在列右（vertical-rl 的「上」，圆心落在列右缘、可越出到列间）、
        // `under` 在列左（圆心落在列左缘）。
        final rubyColumnLeft = computed.rubyPosition == CssRubyPosition.under
            ? columnLeft - rubySize / 2
            : columnLeft + column.width - rubySize / 2;

        for (final rune in ruby.text.runes) {
          _paintVerticalGlyph(
            canvas,
            String.fromCharCode(rune),
            rubyStyle,
            upright: true,
            columnLeft: rubyColumnLeft,
            columnWidth: rubySize,
            y: rubyY,
            advance: rubySize,
            textDirection: _textDirectionOf(layout),
          );
          rubyY += rubySize;
        }
        break;
      }
    }
  }

  /// 竖排字形样式：装饰线在竖排下由绘制层手画（沿列方向），
  /// 必须剥掉引擎的装饰，否则每个字会各画一条横线。
  TextStyle _withoutDecoration(TextStyle style) =>
      style.decoration == null || style.decoration == TextDecoration.none
      ? style
      : style.copyWith(decoration: TextDecoration.none);

  /// 取某个字符偏移处的 run 样式（竖排逐字符绘制用）。
  ComputedStyle? _runStyleAtOffset(List<StyledRun> runs, int offset) {
    for (final run in runs) {
      if (offset >= run.start && offset < run.end) {
        return run.style;
      }
    }
    return null;
  }

  /// 竖排单字符样式（含主题色覆盖）。
  TextStyle _verticalStyleOf(ComputedStyle style, Color? textColorOverride) {
    final textStyle = _withoutDecoration(TextLayoutEngine.textStyleFor(style));
    return textColorOverride == null
        ? textStyle
        : textStyle.copyWith(color: textColorOverride);
  }

  /// 按测量时的行内盒占宽分段平移，保持原文偏移稳定。
  /// 与背景、装饰线及命中共用 lineTextFragments 的原文分段和盒宽位移。
  /// 保留局部函数集中处理样式及基线偏移，避免重复移动坐标。
  void _paintTextAroundInlineBoxes(
    Canvas canvas,
    TextPainter painter,
    LineBox line,
    List<_LineRun> runs,
    double x,
    double y,
    _InlineMarginPlan marginPlan,
  ) {
    final span = painter.text! as TextSpan;
    var cursor = 0;
    var extra = 0.0;
    void paintUntil(int end) {
      if (end <= cursor) return;
      final boundaries = {
        cursor,
        end,
        for (final run in runs) ...[
          run.start.clamp(cursor, end),
          run.end.clamp(cursor, end),
        ],
      }.toList()..sort();
      for (var index = 0; index < boundaries.length - 1; index++) {
        final start = boundaries[index];
        final stop = boundaries[index + 1];
        final text = sliceTextSpan(span, start, stop);
        // 图间空白没有墨迹，占宽由完整行布局保留；零字号行尾无需查询 caret。
        if (text.toPlainText().trim().isEmpty) continue;
        final segment = TextPainter(
          text: text,
          textDirection: painter.textDirection,
        )..layout();
        final offset = painter.getOffsetForCaret(
          TextPosition(offset: start),
          Rect.zero,
        );
        final baseline =
            painter.computeDistanceToActualBaseline(TextBaseline.alphabetic) -
            segment.computeDistanceToActualBaseline(TextBaseline.alphabetic);
        final shift =
            runs
                .where((run) => start >= run.start && start < run.end)
                .map((run) => run.baselineShift)
                .firstOrNull ??
            0;
        segment.paint(
          canvas,
          Offset(
            x + offset.dx + extra + marginPlan.shiftAtOffset(start),
            y + baseline + shift,
          ),
        );
        segment.dispose();
      }
      cursor = end;
    }

    for (final fragment in lineTextFragments(line)) {
      cursor = fragment.start;
      extra = fragment.advance;
      paintUntil(fragment.end);
    }
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
    double y, {
    LineBox? line,
    required CssTextAlign textAlign,
    required bool isRtl,
  }) {
    if (lineText.isEmpty) {
      return;
    }
    if (line != null && line.inlineBoxes.isNotEmpty) {
      _paintTextAroundInlineBoxes(
        canvas,
        painter,
        line,
        runs,
        x,
        y,
        _InlineMarginPlan(
          runs: runs,
          line: line,
          textAlign: textAlign,
          isRtl: isRtl,
        ),
      );
      return;
    }
    if (line != null &&
        runs.any(
          (run) =>
              !run.syntheticFontFallback &&
              (run.style.margin.left != 0 || run.style.margin.right != 0),
        )) {
      final marginPlan = _InlineMarginPlan(
        runs: runs,
        line: line,
        textAlign: textAlign,
        isRtl: isRtl,
      );
      for (final segment in _lineSegments(lineText.length, runs)) {
        final boxes = painter.getBoxesForSelection(
          TextSelection(baseOffset: segment.start, extentOffset: segment.end),
        );
        if (boxes.isEmpty) {
          continue;
        }
        final segmentPainter = TextPainter(
          text: sliceTextSpan(
            painter.text! as TextSpan,
            segment.start,
            segment.end,
          ),
          textDirection: painter.textDirection,
        )..layout();
        final baseline =
            painter.computeDistanceToActualBaseline(TextBaseline.alphabetic) -
            segmentPainter.computeDistanceToActualBaseline(
              TextBaseline.alphabetic,
            );
        segmentPainter.paint(
          canvas,
          Offset(
            x + boxes.first.left + marginPlan.shiftAtOffset(segment.start),
            y + baseline + segment.baselineShift,
          ),
        );
        segmentPainter.dispose();
      }
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
        text: sliceTextSpan(
          painter.text! as TextSpan,
          segment.start,
          segment.end,
        ),
        textDirection: painter.textDirection,
      )..layout();
      final baseline =
          painter.computeDistanceToActualBaseline(TextBaseline.alphabetic) -
          segmentPainter.computeDistanceToActualBaseline(
            TextBaseline.alphabetic,
          );
      segmentPainter.paint(
        canvas,
        Offset(x + boxes.first.left, y + baseline + segment.baselineShift),
      );
      segmentPainter.dispose();
    }
  }

  /// 重画 text-decoration 的线，位置与线型对齐浏览器。
  ///
  /// 引擎（Skia）按字体自带的 underline/strikeout 度量画线，与 Chromium
  /// 实测有固定偏差（思源宋体 17px：line-through 低约 2px、overline 低约
  /// 1px）；wavy 的振幅远小于浏览器、dotted 过细。这里按 Chromium 口径重算：
  /// - line-through 顶边 = 基线 − (ascent − descent) / 2
  /// - overline 顶边 = 基线 − (ascent + 线宽)
  /// - 线宽 = max(1, floor(字号 / 10))（思源宋体无下划线度量时 Chromium
  ///   同样按 1/10 em 兜底；10～30px 实测逐档一致）
  /// - 点线：方点边长 = max(1, round(0.1em))，间隔同边长；虚线：dash = 3×点、
  ///   gap = 2×点（17px 实测 6/4；24px 实测一致）
  /// - 波浪：笔画 = 0.1em、峰谷高 = 2×笔画、周期 = 5×笔画；下划线波形带顶
  ///   = 实线顶边 + 半个笔画（17px 4x 截图实测）
  ///
  /// ascent/descent 用「去掉 line-height 覆盖」的探针排版取字体本身度量：
  /// LineMetrics 的 ascent/descent 会按 height 等比缩放，直接拿来算会把
  /// 行距算进装饰线位置。
  ///
  /// 装饰线随 `text-decoration` 传播到行内子元素，因此基础样式的线覆盖整行
  /// （行尾空白不画），行内元素自己的线覆盖各自区间；上下标区间按 run 的
  /// 基线偏移平移。双线未重画（保留引擎）。
  void _paintLineDecoration(
    Canvas canvas,
    TextPainter painter,
    TextLayoutResult layout,
    LineBox line,
    ComputedStyle style,
    double x,
    double y,
    Map<TextStyle, ({double ascent, double descent})> metricsCache,
  ) {
    final lineLength = line.end - line.start;
    if (lineLength <= 0) {
      return;
    }
    final runs = _lineRuns(layout, line);
    final baseHasDecoration = _isManualDecoration(
      style.textDecoration,
      style.textDecorationStyle,
    );
    final bands = <_DecorationBand>[];
    if (baseHasDecoration) {
      // 行尾空白不画装饰线（浏览器同样不画）。
      final end = _trimmedLineEnd(layout.text, line.start, line.end);
      if (end > 0) {
        final metrics = _fontMetricsOf(style, metricsCache);
        bands.add(
          _DecorationBand(
            start: 0,
            end: end,
            decoration: style.textDecoration,
            lineStyle: style.textDecorationStyle,
            color: style.textDecorationColor ?? style.color,
            fontSize: style.fontSize,
            baselineShift: 0,
            ascent: metrics.ascent,
            descent: metrics.descent,
          ),
        );
      }
    }
    for (final run in runs) {
      if (!_isManualDecoration(
        run.style.textDecoration,
        run.style.textDecorationStyle,
      )) {
        continue;
      }
      final color = run.style.textDecorationColor ?? run.style.color;
      // 与基础样式同款同色时不重复绘制。
      if (baseHasDecoration &&
          run.style.textDecoration == style.textDecoration &&
          run.style.textDecorationStyle == style.textDecorationStyle &&
          color == (style.textDecorationColor ?? style.color)) {
        continue;
      }
      final metrics = _fontMetricsOf(run.style, metricsCache);
      bands.add(
        _DecorationBand(
          start: run.start,
          end: run.end,
          decoration: run.style.textDecoration,
          lineStyle: run.style.textDecorationStyle,
          color: color,
          fontSize: run.style.fontSize,
          baselineShift: run.baselineShift,
          ascent: metrics.ascent,
          descent: metrics.descent,
        ),
      );
    }
    if (bands.isEmpty) {
      return;
    }
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    for (final band in bands) {
      if (band.end <= band.start) {
        continue;
      }
      final boxes = _lineRangeRects(
        painter,
        line,
        TextSelection(baseOffset: band.start, extentOffset: band.end),
        joinBoxes: true,
      );
      final thickness = math.max(1.0, (band.fontSize / 10).floorToDouble());
      final baselineY = y + baseline + band.baselineShift;
      for (final decoration in band.decoration.lineKinds) {
        // 实线顶边：line-through / overline 在基线上方，下划线在下方。
        final solidTop = switch (decoration) {
          CssTextDecoration.overline =>
            baselineY - (band.ascent + thickness).roundToDouble(),
          // 下划线：基线下方 max(1, round(字号/16))（Chromium 17px 实测 +1）。
          CssTextDecoration.underline =>
            baselineY + math.max(1.0, (band.fontSize / 16).roundToDouble()),
          CssTextDecoration.lineThrough =>
            baselineY - ((band.ascent - band.descent) / 2).roundToDouble(),
          _ => baselineY,
        };
        for (final box in boxes) {
          if (box.width <= 0) continue;
          _paintDecorationBand(
            canvas,
            band,
            decoration: decoration,
            left: x + box.left,
            right: x + box.right,
            // 对齐设备像素（Chromium 同样把装饰线吸附到整数像素），细线更清晰。
            solidTop: solidTop.roundToDouble(),
            thickness: thickness,
          );
        }
      }
    }
  }

  /// 背景与装饰线沿用正文的盒宽位移，并在盒插入点拆开绘制区间。
  Iterable<Rect> _lineRangeRects(
    TextPainter painter,
    LineBox line,
    TextSelection selection, {
    ui.BoxHeightStyle heightStyle = ui.BoxHeightStyle.tight,
    bool joinBoxes = false,
  }) sync* {
    for (final fragment in lineTextFragments(
      line,
      start: selection.start,
      end: selection.end,
    )) {
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: fragment.start, extentOffset: fragment.end),
        boxHeightStyle: heightStyle,
      );
      if (joinBoxes && boxes.isNotEmpty) {
        // 装饰线在同一文字片段内连续，保留原有跨样式 run 的绘制口径。
        yield Rect.fromLTRB(
          boxes.first.left,
          boxes.first.top,
          boxes.last.right,
          boxes.last.bottom,
        ).shift(Offset(fragment.advance, 0));
      } else {
        for (final box in boxes) {
          yield box.toRect().shift(Offset(fragment.advance, 0));
        }
      }
    }
  }

  /// 按线型画一段装饰线：实线 / 点线 / 虚线 / 波浪。
  void _paintDecorationBand(
    Canvas canvas,
    _DecorationBand band, {
    required CssTextDecoration decoration,
    required double left,
    required double right,
    required double solidTop,
    required double thickness,
  }) {
    final paint = Paint()..color = band.color;
    switch (band.lineStyle) {
      case CssTextDecorationStyle.solid:
        canvas.drawRect(
          Rect.fromLTWH(left, solidTop, right - left, thickness),
          paint,
        );
      case CssTextDecorationStyle.dotted:
        // 方点：边长 ≈ 0.1em，间隔同边长。
        final dot = math.max(1.0, (band.fontSize * 0.1).roundToDouble());
        for (var x = left; x < right; x += dot * 2) {
          final end = math.min(x + dot, right);
          canvas.drawRect(Rect.fromLTWH(x, solidTop, end - x, dot), paint);
        }
      case CssTextDecorationStyle.dashed:
        // 虚线：dash = 3×点、gap = 2×点（等价 6/4 @17px）。
        final dot = math.max(1.0, (band.fontSize * 0.1).roundToDouble());
        final dash = dot * 3;
        for (var x = left; x < right; x += dot * 5) {
          final end = math.min(x + dash, right);
          canvas.drawRect(
            Rect.fromLTWH(x, solidTop, end - x, thickness),
            paint,
          );
        }
      case CssTextDecorationStyle.wavy:
        final stroke = math.max(1.0, band.fontSize * 0.1);
        final amplitude = stroke; // 峰谷高 = 2×笔画
        final period = stroke * 5;
        final bandTop = decoration == CssTextDecoration.underline
            ? solidTop + stroke / 2
            : solidTop - (2 * amplitude + stroke - thickness) / 2;
        final center = bandTop + amplitude + stroke / 2;
        final wavePaint = Paint()
          ..color = band.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        final path = Path();
        final steps = math.max(2, ((right - left) * 2).ceil());
        for (var i = 0; i <= steps; i++) {
          final px = left + (right - left) * i / steps;
          final py =
              center + amplitude * math.sin(2 * math.pi * (px - left) / period);
          if (i == 0) {
            path.moveTo(px, py);
          } else {
            path.lineTo(px, py);
          }
        }
        canvas.drawPath(path, wavePaint);
      case CssTextDecorationStyle.double:
        canvas.drawRect(
          Rect.fromLTWH(left, solidTop, right - left, thickness),
          paint,
        );
    }
  }

  /// 取字体本身的 ascent/descent（不受 line-height 影响），按样式缓存。
  ///
  /// `TextStyle.copyWith(height: null)` 清不掉 height（null 视为「不修改」），
  /// 这里按原样式的字体字段新建一个不带 height 的探针样式。
  ///
  /// 探针文本「国Hg」同时覆盖 CJK 与拉丁，取到的是这一行参与排版的字体
  /// 度量；若书籍字体缺其中一种而落到回退字体，装饰线位置会有 ≤1px 偏差
  /// （Chromium 按被装饰文本自己的字体算，回退场景同样存在口径差异）。
  ({double ascent, double descent}) _fontMetricsOf(
    ComputedStyle style,
    Map<TextStyle, ({double ascent, double descent})> cache,
  ) {
    final textStyle = TextLayoutEngine.textStyleFor(style);
    final key = TextStyle(
      fontSize: textStyle.fontSize,
      fontFamily: textStyle.fontFamily,
      fontFamilyFallback: textStyle.fontFamilyFallback,
      fontWeight: textStyle.fontWeight,
      fontStyle: textStyle.fontStyle,
      letterSpacing: textStyle.letterSpacing,
      wordSpacing: textStyle.wordSpacing,
      locale: textStyle.locale,
      leadingDistribution: textStyle.leadingDistribution,
    );
    final cached = cache[key];
    if (cached != null) {
      return cached;
    }
    final probe = TextPainter(
      text: TextSpan(text: '国Hg', style: key),
      textDirection: TextDirection.ltr,
    )..layout();
    final metrics = probe.computeLineMetrics();
    final result = metrics.isEmpty
        ? (ascent: style.fontSize * 1.15, descent: style.fontSize * 0.29)
        : (ascent: metrics.first.ascent, descent: metrics.first.descent);
    probe.dispose();
    cache[key] = result;
    return result;
  }

  /// 该装饰是否需要绘制层重画（与 `_withoutManualDecoration` 同口径）：
  /// line-through / overline 全线型，以及下划线的点线/虚线/波浪。
  bool _isManualDecoration(
    CssTextDecoration decoration,
    CssTextDecorationStyle lineStyle,
  ) {
    if (decoration == CssTextDecoration.none ||
        lineStyle == CssTextDecorationStyle.double) {
      return false;
    }
    if (decoration == CssTextDecoration.underline &&
        lineStyle == CssTextDecorationStyle.solid) {
      return false;
    }
    return true;
  }

  /// 行内文本去掉行尾空白后的长度（相对行首）；全为空白时返回 0。
  int _trimmedLineEnd(String text, int start, int end) {
    var cursor = end;
    while (cursor > start) {
      final unit = text.codeUnitAt(cursor - 1);
      if (unit != 0x20 && unit != 0x09 && unit != 0xA0) {
        break;
      }
      cursor--;
    }
    return cursor - start;
  }

  /// 画尚未转为替换盒的行内图片（P9-06），沿用 U+FFFC 字形框定位。
  ///
  /// 占位符字形已由 [buildLineSpan] 置透明，这里按行盒高度（1em）等比
  /// 缩放并底对齐；宽度超过版心时按版心收窄。
  void _paintInlineImages(
    Canvas canvas,
    TextPainter painter,
    _SliceGeometry geometry,
    LineBox line,
    String lineText,
    double x,
    double lineY,
  ) {
    final specs = geometry.slice.block.inlineImages;
    final lookup = imageLookup;
    if (specs.isEmpty || lookup == null || !lineText.contains('\uFFFC')) {
      return;
    }
    final em = geometry.style.fontSize;
    final available = geometry.pageWidth - geometry.leftInset;
    for (var i = 0; i < lineText.length; i++) {
      if (lineText.codeUnitAt(i) != 0xFFFC) {
        continue;
      }
      final global = line.start + i;
      if (line.inlineBoxes.any(
        (box) => box.offset == global && box.spec.replacesPlaceholder,
      )) {
        continue;
      }
      InlineImageSpec? spec;
      for (final candidate in specs) {
        if (candidate.offset == global) {
          spec = candidate;
          break;
        }
      }
      if (spec == null) {
        continue;
      }
      final image = lookup(spec.url);
      if (image == null) {
        continue;
      }
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1),
      );
      if (boxes.isEmpty) {
        continue;
      }
      final aspect =
          spec.aspectRatio ??
          (image.height == 0 ? 1.0 : image.width / image.height);
      final declaredWidth = spec.width;
      final declaredHeight = spec.height;
      final double rawWidth;
      final double rawHeight;
      if (declaredWidth != null && declaredHeight != null) {
        rawWidth = declaredWidth;
        rawHeight = declaredHeight;
      } else if (declaredWidth != null) {
        rawWidth = declaredWidth;
        rawHeight = aspect == 0 ? rawWidth : rawWidth / aspect;
      } else if (declaredHeight != null) {
        rawHeight = declaredHeight;
        rawWidth = rawHeight * aspect;
      } else {
        rawHeight = em;
        rawWidth = em * aspect;
      }
      final scale = rawWidth > available && rawWidth > 0
          ? available / rawWidth
          : 1.0;
      final width = rawWidth * scale;
      final height = rawHeight * scale;
      final left = x + boxes.first.left;
      final boxBottom = lineY + boxes.first.bottom;
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(left, boxBottom - height, width, height),
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
  }

  static bool _isOpenEmphasis(CssTextEmphasisStyle style) =>
      style == CssTextEmphasisStyle.openDot ||
      style == CssTextEmphasisStyle.openCircle ||
      style == CssTextEmphasisStyle.openSesame;

  static bool _isCircleEmphasis(CssTextEmphasisStyle style) =>
      style == CssTextEmphasisStyle.circle ||
      style == CssTextEmphasisStyle.openCircle;

  static bool _isSesameEmphasis(CssTextEmphasisStyle style) =>
      style == CssTextEmphasisStyle.sesame ||
      style == CssTextEmphasisStyle.openSesame;

  static double _emphasisRadius(
    double fontSize,
    CssTextEmphasisStyle emphasis,
  ) => math.max(1.0, fontSize * (_isCircleEmphasis(emphasis) ? 0.16 : 0.08));

  /// 竖排沿用既有合成字形；横排由 HorizontalTextEmphasis 绘制字体字形。
  void _paintEmphasisMark(
    Canvas canvas,
    CssTextEmphasisStyle emphasis,
    Offset center,
    double fontSize,
    Paint paint,
  ) {
    final open = _isOpenEmphasis(emphasis);
    if (open) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, fontSize * 0.05);
    } else {
      paint.style = PaintingStyle.fill;
    }
    if (_isSesameEmphasis(emphasis)) {
      final halfWidth = math.max(1.2, fontSize * 0.08);
      final halfHeight = math.max(2.0, fontSize * 0.13);
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = math.max(1.0, fontSize * 0.07);
      canvas.drawLine(
        center.translate(-halfWidth, -halfHeight),
        center.translate(halfWidth, halfHeight),
        paint,
      );
      return;
    }
    canvas.drawCircle(center, _emphasisRadius(fontSize, emphasis), paint);
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
            run.syntheticFontFallback,
            run.start,
            run.end,
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
  ///
  /// `line-through` / `overline` 的实线从 span 树上摘掉（见
  /// [_stripManualDecoration]）：引擎的装饰线位置按字体度量绘制，比浏览器
  /// 低 1～2px（17px 字号实测），改由 [_paintLineDecoration] 按浏览器几何
  /// 重画；下划线与点线/虚线/波浪/双线仍留在引擎侧。
  InlineSpan _lineSpan(
    TextLayoutResult layout,
    LineBox line,
    TextStyle baseStyle, {
    bool punctCompression = false,
    bool textAutospace = false,
    Color? textColorOverride,
  }) => _stripManualDecoration(
    buildLineSpan(
      layout: layout,
      line: line,
      baseStyle: baseStyle,
      textColor: textColorOverride,
      styleOf: _paintTextStyleFor,
      punctCompression: punctCompression,
      textAutospace: textAutospace,
    ),
  );

  /// 递归摘掉 span 树上的 line-through / overline 实线。
  InlineSpan _stripManualDecoration(InlineSpan span) {
    if (span is! TextSpan) {
      return span;
    }
    final children = span.children;
    final style = span.style;
    return TextSpan(
      text: span.text,
      style: style == null ? null : _withoutManualDecoration(style),
      children: children == null
          ? null
          : [for (final child in children) _stripManualDecoration(child)],
      recognizer: span.recognizer,
      semanticsLabel: span.semanticsLabel,
      locale: span.locale,
      spellOut: span.spellOut,
    );
  }

  /// 去掉需要绘制层重画的装饰线（其余留给引擎）。
  ///
  /// 重画范围：line-through / overline 的全部实线线型，以及下划线的
  /// 点线/虚线/波浪（引擎的 wavy 振幅远小于浏览器、dotted 过细）。
  /// 下划线实线与浏览器已一致，双线未做几何重画，仍由引擎绘制。
  TextStyle _withoutManualDecoration(TextStyle style) {
    final decoration = style.decoration;
    if (decoration == null || decoration == TextDecoration.none) {
      return style;
    }
    final lineStyle = style.decorationStyle ?? TextDecorationStyle.solid;
    if (lineStyle == TextDecorationStyle.double) {
      return style;
    }
    final manualKind =
        decoration.contains(TextDecoration.lineThrough) ||
        decoration.contains(TextDecoration.overline);
    if (!manualKind && lineStyle == TextDecorationStyle.solid) {
      return style;
    }
    return style.copyWith(decoration: TextDecoration.none);
  }
}

/// 一页绘制共享的只读上下文，递归容器沿用原切片索引供文字缓存使用。
class _PagePaintContext {
  const _PagePaintContext(this.canvas, this.page, this.pageRect, this.indexOf);
  final Canvas canvas;
  final PageContent page;
  final Rect pageRect;
  final Map<_SliceGeometry, int> indexOf;
}

class _PaintGroup {
  _PaintGroup(this.order, this.container, this.geometries);
  final int order;
  final PageContainer? container;
  final List<_SliceGeometry> geometries;
  ComputedStyle get style => container?.style ?? geometries.first.style;

  bool get canSplitFlowPaint {
    final css = style;
    if (css.position != CssPosition.static ||
        css.cssFloat != CssFloat.none ||
        css.zIndex != 0 ||
        css.opacity < 1 ||
        css.transforms.isNotEmpty ||
        css.filters.isNotEmpty ||
        css.backdropFilters.isNotEmpty ||
        css.clipPath != null ||
        css.mixBlendMode != CssMixBlendMode.normal ||
        css.display == CssDisplay.flex ||
        css.display == CssDisplay.inlineBlock) {
      return false;
    }
    if (container != null) return true;
    final block = geometries.single.slice.block;
    return !block.absolute &&
        block.floatSide == null &&
        block.effectiveOpacity >= 1 &&
        block.table == null &&
        block.gallery == null &&
        !block.isReplaced;
  }
}

enum _FlowPaintPhase { all, negative, background, foreground }

/// 普通行内 run 的水平 margin 在绘制期的位移。
///
/// flat 排版没有把行内 margin 计入 LineBox 宽度。这里按对齐方式补回外边距
/// 的居中/右对齐偏移，再让每个 run 从累计外边距处开始；文字、背景和边框
/// 共用同一组位移，避免背景分块后文字仍停在旧位置。
class _InlineMarginPlan {
  _InlineMarginPlan({
    required this.runs,
    required this.line,
    required this.textAlign,
    required this.isRtl,
  }) {
    for (final run in runs) {
      // 合成 run 继承正文块样式，不是行内元素；块级 margin 已由页面几何消费。
      if (run.syntheticFontFallback) continue;
      if (_hasLeadingMargin(run)) {
        _total += run.style.margin.left;
      }
      if (_hasTrailingMargin(run)) {
        _total += run.style.margin.right;
      }
    }
    _baseShift = switch (textAlign) {
      CssTextAlign.center => -_total / 2,
      CssTextAlign.right => -_total,
      CssTextAlign.end => isRtl ? 0 : -_total,
      CssTextAlign.start => isRtl ? -_total : 0,
      CssTextAlign.left || CssTextAlign.justify => 0,
    };
  }

  final List<_LineRun> runs;
  final LineBox line;
  final CssTextAlign textAlign;
  final bool isRtl;
  var _total = 0.0;
  late final double _baseShift;

  /// 单个 run 跨行时，只在原元素的起点/终点应用左/右外边距。
  bool _hasLeadingMargin(_LineRun run) => run.sourceStart >= line.start;
  bool _hasTrailingMargin(_LineRun run) => run.sourceEnd <= line.end;

  /// [offset] 为行内局部字符偏移。
  double shiftAtOffset(int offset) {
    var shift = _baseShift;
    for (final run in runs) {
      if (run.syntheticFontFallback) continue;
      if (run.end <= offset) {
        if (_hasLeadingMargin(run)) {
          shift += run.style.margin.left;
        }
        if (_hasTrailingMargin(run)) {
          shift += run.style.margin.right;
        }
        continue;
      }
      if (run.start <= offset) {
        if (_hasLeadingMargin(run)) {
          shift += run.style.margin.left;
        }
      }
      break;
    }
    return shift;
  }
}

/// 行内一段样式区间（行内局部坐标，带基线偏移）。
class _LineRun {
  const _LineRun(
    this.start,
    this.end,
    this.style,
    this.baselineShift,
    this.syntheticFontFallback,
    this.sourceStart,
    this.sourceEnd,
  );

  final int start;
  final int end;
  final ComputedStyle style;
  final double baselineShift;
  final bool syntheticFontFallback;
  final int sourceStart;
  final int sourceEnd;
}

/// 行内绘制段：样式为 null 时用基础样式。
class _LineSegment {
  const _LineSegment(this.start, this.end, this.style, this.baselineShift);

  final int start;
  final int end;
  final ComputedStyle? style;
  final double baselineShift;
}

/// 无序列表项目符号的形状（Chromium 用几何图形而非字体字形）。
enum _MarkerShape { disc, circle, square }

/// 一段装饰线（行内局部字符区间 + 线的样式 + 字体度量）。
class _DecorationBand {
  const _DecorationBand({
    required this.start,
    required this.end,
    required this.decoration,
    required this.lineStyle,
    required this.color,
    required this.fontSize,
    required this.baselineShift,
    required this.ascent,
    required this.descent,
  });

  final int start;
  final int end;
  final CssTextDecoration decoration;
  final CssTextDecorationStyle lineStyle;
  final Color color;
  final double fontSize;
  final double baselineShift;
  final double ascent;
  final double descent;
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
    required this.rightInset,
    required this.upExtent,
    required this.downExtent,
    required this.pageWidth,
    required this.pageHeight,
    this.pageInsets = EdgeInsets.zero,
    this.chapterLeading = false,
    this.textColorOverride,
    this.paintBox,
  });

  final Rect? paintBox;
  final PageBlockSlice slice;
  final double y;
  final ComputedStyle style;
  final TextStyle textStyle;

  /// 主题文字色覆盖（null = 保留书籍颜色，见 PagePainter._textColorFor）。
  final Color? textColorOverride;

  /// 标点挤压开关（P7-19，源自 style.textSpacingTrim）。
  bool get punctCompression =>
      style.textSpacingTrim == CssTextSpacingTrim.trimAdjacent;

  /// 中西文自动间距开关（P7-20，源自 style.textAutospace）。
  bool get textAutospace => style.textAutospace == CssTextAutospace.normal;

  final bool startsBlock;
  final bool endsBlock;
  final bool hidden;
  final double leading;
  final double leftInset;

  /// 行内容右内缩（P8-05：margin.right + padding.right 参与右侧收窄）。
  final double rightInset;
  final double upExtent;
  final double downExtent;
  final double pageWidth;

  /// 正文区高（页面高 − 上下内缩），出血块向下扩时用到。
  final double pageHeight;

  /// 正文区相对整页的内缩（阅读器页边距 + 页眉页脚槽）。
  final EdgeInsets pageInsets;

  /// 章首页的首个普通流块；只有此处的出血图片可以自动贴页顶。
  final bool chapterLeading;

  /// 背景/边框盒子（含首尾内缩）。
  Rect get box => paintBox ?? Rect.fromLTWH(0, y, pageWidth, slice.height);

  /// 背景/边框盒子（margin 修正）：flat 管线 box.left 恒 0，块级
  /// margin.left 折算进左缘，使背景与边框跟文本 x（已含 margin）对齐；
  /// 右缘同步扣除 margin.right，与收窄后的排版宽度同界。
  /// 容器拼合盒（P9-25）：带边框容器里的子块，把背景与左右边框延伸到
  /// 自己的上下段距，多个子块叠起来就拼回一整片面板。
  Rect get containerPaintBox {
    final base = borderBox;
    if (paintBox != null || !slice.block.containerSides) {
      return base;
    }
    // 容器拼合：向上下延伸到相邻子块的段距，拼回整片面板（P9-25）。
    return Rect.fromLTRB(
      base.left,
      y - slice.leadingExtent,
      base.right,
      y + slice.height + slice.trailingExtent,
    );
  }

  /// 边框盒（页面坐标）。
  ///
  /// 切片 [PageBlockSlice.height] 的首尾额外高度里含**段前/段后间距**
  /// （`leadingExtent = spaceBefore + topInset`），背景/边框/阴影只能用去掉
  /// margin 后的边框盒，否则会画进相邻块之间的空白带——Chromium 那里是页面
  /// 底色（10-background、26-background-gradient 的视觉差全部落在这条带上）。
  Rect get borderBox {
    if (paintBox != null) return paintBox!;
    final block = slice.block;
    final ownTop = block.containers.isEmpty
        ? block.topInset
        : style.padding.top +
              (style.borders.top.isVisible ? style.borders.top.width : 0);
    final ownBottom = block.containers.isEmpty
        ? block.bottomInset
        : style.padding.bottom +
              (style.borders.bottom.isVisible ? style.borders.bottom.width : 0);
    final top = slice.leadingExtent != 0 ? y + slice.leadingExtent - ownTop : y;
    final bottom = slice.trailingExtent != 0
        ? y + slice.height - slice.trailingExtent + ownBottom
        : y + slice.height;
    // 横向按解算后的内容宽（`width` 声明 / auto）× box-sizing 定右边：
    // 声明了 width 的块背景与 overflow 裁剪都要收在声明宽内（Chromium 的
    // used width 口径）；auto 时与「页宽 − margin」等价。
    // 竖排块（W22）：未声明宽时内容盒收缩到列带宽（列数×列宽）；声明宽时
    // 浏览器仍保留声明宽，列带在 vertical-rl 下从内容盒右缘起排。若这里
    // 只看列带宽，`width: 54px` 的单列省略号会被裁到 24px，文字整列消失。
    final model = _boxModel;
    // 出血：盒子扩到整页边（内容坐标里页边是 −insets / +pageWidth+insets）。
    // 覆盖切片的 leftInset 已由分页层解算为盒左缘（绝对定位/浮动/多列），
    // 普通流的 leftInset 仍只是 border + padding，不能拿来当盒左缘。
    final boxLeft = slice.overlay
        ? slice.leftInset + style.margin.left
        : style.margin.left;
    final contentWidth = _contentBoxWidth(model);
    if (block.isReplaced) {
      return _replacedBorderBox(
        Rect.fromLTRB(
          boxLeft,
          top,
          boxLeft + contentWidth + model.horizontalInset,
          bottom,
        ),
      );
    }
    final left = block.bleedLeft ? -pageInsets.left : boxLeft;
    final right = block.bleedRight
        ? pageWidth + pageInsets.right
        : left + contentWidth + model.horizontalInset;
    return Rect.fromLTRB(
      left,
      block.bleedTop ? -pageInsets.top : top,
      right,
      block.bleedBottom ? pageHeight + pageInsets.bottom : bottom,
    );
  }

  /// 替换图片保留测量盒和正文流位置；章首头图可贴页顶，
  /// 覆盖切片沿用显式出血定位，不把图像定位区域撑成整页。
  Rect _replacedBorderBox(Rect box) {
    final block = slice.block;
    final left = box.left - (block.bleedLeft ? pageInsets.left : 0);
    final top = block.bleedTop && (chapterLeading || slice.overlay)
        ? -pageInsets.top
        : block.bleedBottom
        ? pageHeight + pageInsets.bottom - box.height
        : box.top;
    return Rect.fromLTWH(left, top, box.width, box.height);
  }

  double _contentBoxWidth(BoxModel model) {
    final block = slice.block;
    // 浮动和普通横排内在宽度已在测量时解算，绘制直接使用最终内容宽。
    final intrinsicText =
        style.intrinsicWidth != null &&
        !isVerticalBlock &&
        !block.isReplaced &&
        block.table == null &&
        block.gallery == null;
    if (block.floatSide != null || intrinsicText) {
      return block.layout.maxWidth.isFinite
          ? block.layout.maxWidth
          : block.layout.width;
    }
    if (isVerticalBlock && model.contentWidth == null) {
      return block.layout.width;
    }
    return model.resolveContentWidth(pageWidth);
  }

  /// 本切片是否竖排（`writing-mode: vertical-*`）。
  ///
  /// 以列标记为准：章节源重建 `TextLayoutResult` 时可能不携带 writingMode，
  /// 但列仍然是 `LineBox.vertical`，两种来源都认。
  bool get isVerticalBlock {
    final layout = slice.block.layout;
    return layout.isVertical || layout.lines.any((line) => line.vertical);
  }

  /// 本切片的盒模型（百分比以页宽为基准，与排版层同口径）。
  BoxModel get _boxModel =>
      BoxModel.fromStyle(style, containingWidth: pageWidth);

  /// `overflow != visible` 时内容 ink 必须裁到 padding-box（W13）。
  bool get clipsOverflow => style.overflow != CssOverflow.visible;

  /// padding-box（页面坐标）：边框盒去掉四边边框（不可见边框按 0 计）。
  Rect get paddingBox {
    final borders = style.borders;
    final box = borderBox;
    return Rect.fromLTRB(
      box.left + (borders.left.isVisible ? borders.left.width : 0),
      box.top + (borders.top.isVisible ? borders.top.width : 0),
      box.right - (borders.right.isVisible ? borders.right.width : 0),
      box.bottom - (borders.bottom.isVisible ? borders.bottom.width : 0),
    );
  }

  Rect _decorationClip(Rect clip) {
    // 负外边距可把首尾边框移到切片流占位之外；只扩展真实块首尾，
    // 续页仍沿分页切口裁剪，完整边框最多画到整页边界。
    final box = borderBox;
    return Rect.fromLTRB(
      clip.left,
      startsBlock
          ? math.min(clip.top, math.max(-pageInsets.top, box.top))
          : clip.top,
      clip.right,
      endsBlock
          ? math.max(
              clip.bottom,
              math.min(pageHeight + pageInsets.bottom, box.bottom),
            )
          : clip.bottom,
    );
  }

  /// 按切片裁剪；上下标越界时放宽上下边。
  void clip(Canvas canvas, {bool decoration = false}) {
    final bounds = slice.clipRect(y, pageWidth);
    final clip = decoration ? _decorationClip(bounds) : bounds;
    // 容器内子块（P9-25）的背景/边框会延伸到上下段距，裁剪同步放宽。
    final containerTop = slice.block.containerSides ? slice.leadingExtent : 0.0;
    final containerBottom = slice.block.containerSides
        ? slice.trailingExtent
        : 0.0;
    // 出血方向同步放宽到页边，否则扩出去的背景/边框会被切片矩形裁掉。
    final block = slice.block;
    // 声明盒高小于内容高且 overflow: visible 时，文字按 CSS 语义画到盒外；
    // 切片仍需保持声明高，避免把后续块提前上移。
    final contentBottom = block.hasContentOverflow && !block.clipsContent
        ? y + slice.leadingExtent + block.layout.height
        : clip.bottom;
    canvas.clipRect(
      Rect.fromLTRB(
        block.bleedLeft ? -pageInsets.left : clip.left,
        block.bleedTop ? -pageInsets.top : clip.top - upExtent - containerTop,
        block.bleedRight ? pageWidth + pageInsets.right : clip.right,
        block.bleedBottom
            ? pageHeight + pageInsets.bottom
            : contentBottom + downExtent + containerBottom,
      ),
    );
  }
}

/// 单位变换矩阵（ImageShader 平铺用，P4-22）。
Float64List _identityMatrix4() => Float64List.fromList(<double>[
  1, 0, 0, 0, //
  0, 1, 0, 0, //
  0, 0, 1, 0, //
  0, 0, 0, 1, //
]);
