import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../css/computed_style.dart';
import '../layout/box_model.dart';
import '../layout/line_breaker.dart';
import '../layout/paginator.dart';
import '../layout/table_layout.dart';
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
    this.pageBackgroundImage,
    this.imageLookup,
    this.listMarkerImageOf,
    this.textColor,
    this.selection,
    this.selectionColor = const Color(0x330066FF),
    this.onPhase,
    this.paragraphCache,
  });

  /// 页面背景色。
  final Color background;

  /// 整页背景纹理（P4-22）：平铺绘制在背景色之上、正文之下。
  ///
  /// 只影响绘制层，不进入排版指纹——换背景图不触发重排（§31.4）。
  final ui.Image? pageBackgroundImage;

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
    // 叠放顺序（CSS 2.1 §9.9）：`z-index` 升序绘制，同层保持文档序。
    // 只影响绘制次序；`geometries` 本身仍按文档序用于命中/选区。
    final paintOrder = _paintOrder(geometries);
    final paintIndexOf = <_SliceGeometry, int>{
      for (var i = 0; i < geometries.length; i++) geometries[i]: i,
    };

    _notifyPhase(PagePaintPhase.background);
    final pageRect = Rect.fromLTWH(0, 0, pageSize.width, pageSize.height);
    canvas.drawRect(pageRect, Paint()..color = background);
    // 背景纹理平铺在背景色之上、正文之下（P4-22，只影响绘制层）。
    final pageBackground = pageBackgroundImage;
    if (pageBackground != null) {
      canvas.drawRect(
        pageRect,
        Paint()
          ..shader = ImageShader(
            pageBackground,
            TileMode.repeated,
            TileMode.repeated,
            _identityMatrix4(),
          ),
      );
    }

    // 书籍整页背景图（P9-04）：平铺在背景色/纹理之上、正文之下。
    _paintBookPageBackground(canvas, page, pageRect);

    _notifyPhase(PagePaintPhase.blockBackground);
    for (final geometry in paintOrder) {
      if (geometry.hidden) {
        continue;
      }
      // 阴影可溢出块外：画在块裁剪之外（自带透明层），先影后景。
      _inBlockSpace(
        canvas,
        geometry,
        clip: false,
        () => _withEffects(canvas, geometry, () {
          _paintBoxShadow(canvas, geometry);
        }),
      );
      _inBlockSpace(
        canvas,
        geometry,
        clip: true,
        () => _withEffects(canvas, geometry, () {
          _paintBackground(
            canvas,
            geometry.containerPaintBox,
            geometry.style,
            startsBlock: geometry.startsBlock,
            endsBlock: geometry.endsBlock,
          );
          // 内阴影画在背景之上、边框/文字之下（Chromium 的顺序）。
          _paintInsetBoxShadow(canvas, geometry);
          // 多列分隔线：背景之上、正文之下（CSS Multicol §4 的绘制顺序）。
          _paintColumnRules(canvas, geometry);
        }),
      );
    }

    _notifyPhase(PagePaintPhase.blockBorder);
    for (final geometry in paintOrder) {
      if (geometry.hidden) {
        continue;
      }
      _inBlockSpace(
        canvas,
        geometry,
        clip: true,
        () => _withEffects(canvas, geometry, () {
          _paintBorders(
            canvas,
            geometry.containerPaintBox,
            geometry.style,
            startsBlock: geometry.startsBlock,
            endsBlock: geometry.endsBlock,
          );
        }),
      );
    }

    _notifyPhase(PagePaintPhase.text);
    // 字体度量缓存（装饰线几何用）：整个文本阶段共用，避免逐行重排探针。
    final fontMetricsCache = <TextStyle, ({double ascent, double descent})>{};
    for (final geometry in paintOrder) {
      final sliceIndex = paintIndexOf[geometry]!;
      if (geometry.hidden) {
        continue;
      }
      // 表格切片（flat 管线接入）：网格线 + 逐格文字，不走行文本路径。
      final tableSpec = geometry.slice.block.table;
      if (tableSpec != null) {
        _inBlockSpace(
          canvas,
          geometry,
          clip: true,
          contentClip: true,
          () => _withEffects(canvas, geometry, () {
            _paintTable(canvas, geometry, tableSpec);
          }),
        );
        continue;
      }
      // 竖排注音画在列右侧，可能越出块的内容盒；此时不按内容盒裁剪，
      // 否则注音会被切掉（Chrome 的注音同样允许横向溢出）。
      final verticalRuby =
          geometry.isVerticalBlock &&
          (geometry.slice.block.rubies?.isNotEmpty ?? false);
      _inBlockSpace(
        canvas,
        geometry,
        clip: !verticalRuby,
        contentClip: !verticalRuby,
        () => _withEffects(canvas, geometry, () {
          final layout = geometry.slice.block.layout;
          if (geometry.isVerticalBlock) {
            // 竖排：每行 = 一列，逐字符自上而下绘制（W22）。
            _paintVerticalColumns(
              canvas,
              layout,
              geometry.style,
              textColorOverride: geometry.textColorOverride,
              contentLeft:
                  geometry.borderBox.left +
                  geometry.style.padding.left +
                  (geometry.style.borders.left.isVisible
                      ? geometry.style.borders.left.width
                      : 0),
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
              final painter = _linePainterFor(
                page,
                sliceIndex,
                lineIndex,
                layout,
                line,
                geometry.textStyle,
                punctCompression: geometry.punctCompression,
                textColorOverride: geometry.textColorOverride,
              );
              final lineRuns = _lineRuns(layout, line);
              // 行内盒（P9-24 / W16）：布局层给了 placements 就按它画
              // （否则回退到按 run 样式的旧口径），都画在文字之前。
              if (line.inlineBoxes.isEmpty) {
                _paintInlineBoxes(canvas, painter, lineRuns, x, lineY);
              } else {
                _paintInlineBoxPlacements(
                  canvas,
                  geometry,
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
                lineY,
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
                lineY,
                fontMetricsCache,
              );
              _paintInlineImages(
                canvas,
                painter,
                geometry,
                line,
                lineText,
                x,
                lineY,
              );
              // 行尾字形（W13）：布局层只截断/计宽不画字——
              // 省略号 `…`（行宽含省略号 advance）与断词连字符 `-` 都由
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
                  glyph: '-',
                  advance: line.hyphenWidth,
                  x: x,
                  y: lineY,
                );
              }
            }
            lineY += line.height;
          }
        }),
      );
    }

    _notifyPhase(PagePaintPhase.decoration);
    for (var sliceIndex = 0; sliceIndex < geometries.length; sliceIndex++) {
      final geometry = geometries[sliceIndex];
      if (geometry.hidden ||
          geometry.style.textEmphasisStyle == CssTextEmphasisStyle.none) {
        continue;
      }
      _inBlockSpace(
        canvas,
        geometry,
        clip: true,
        contentClip: true,
        () {
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
              textColorOverride: geometry.textColorOverride,
            ),
            lineText,
            geometry.style,
            line.offsetX + geometry.leftInset,
            lineY,
          );
        }
        lineY += line.height;
      }
        },
      );
    }

    // 注音趟（P8-08）：ruby 主文本区间上方绘制注音（50% 字号、区间
    // 居中；行内字符定位按 TextPainter 逐字符累进近似）。
    for (final geometry in paintOrder) {
      if (geometry.hidden) {
        continue;
      }
      final rubies = geometry.slice.block.rubies;
      if (rubies == null || rubies.isEmpty) {
        continue;
      }
      // 竖排块的注音画在列右侧（_paintVerticalRubies）：可能越出块的内容盒，
      // 因此单独一趟、不按块盒裁剪，否则注音会被切掉。
      if (geometry.isVerticalBlock) {
        final layout = geometry.slice.block.layout;
        _inBlockSpace(
          canvas,
          geometry,
          clip: false,
          () => _paintVerticalRubies(
            canvas,
            layout,
            geometry.style,
            rubies,
            contentLeft:
                geometry.borderBox.left +
                geometry.style.padding.left +
                (geometry.style.borders.left.isVisible
                    ? geometry.style.borders.left.width
                    : 0),
            contentTop: geometry.y + geometry.leading,
            startLine: geometry.slice.startLine,
            endLine: geometry.slice.endLine,
            metrics: TextLayoutEngine.verticalGlyphMetrics(
              layout.text,
              geometry.style,
            ),
          ),
        );
        continue;
      }
      _inBlockSpace(
        canvas,
        geometry,
        clip: true,
        contentClip: true,
        () => _paintRubies(canvas, geometry, rubies),
      );
    }

    _notifyPhase(PagePaintPhase.selection);
    final selection = this.selection;
    if (selection != null) {
      _paintSelection(canvas, page, geometries, selection);
    }
  }

  void _notifyPhase(PagePaintPhase phase) => onPhase?.call(phase);

  /// 主题文字色是否覆盖某个块（P9-02）。
  ///
  /// 浅色页：书籍显式声明的颜色照书（金标题、灰注释不再被刷黑），
  /// 只有未声明的默认黑字跟随主题色。
  /// 深色页：按技术方案 §7.5-5，把深色（亮度 ≤ 0.179）文字替换为主题色，
  /// 浅色文字保留——否则黑字落在黑底上不可读。
  Color? _textColorFor(ComputedStyle style) {
    final theme = textColor;
    if (theme == null) {
      return null;
    }
    final darkText = style.color.computeLuminance() <= 0.179;
    // 块自带深色背景时（卡片/面板），按块内的有效底色判断：主题色是
    // 浅色页的深字，直接套上去会在深色卡片里隐形。此时未声明颜色的
    // 文字改用浅色（P9-23）。
    final blendedBackground = style.backgroundColor.a > 0
        ? Color.alphaBlend(style.backgroundColor, background)
        : background;
    if (blendedBackground.computeLuminance() < 0.35) {
      // 与 §7.5-5 一致：深色底上的深色字必须提亮，哪怕书籍显式声明过。
      if (!darkText) {
        return null;
      }
      // 深色底 + 深色字：需要一个浅色。主题文字色在浅色主题里本身就是
      // 深色，不能直接复用，此时固定用浅灰；深色主题才用主题色。
      return theme.computeLuminance() < 0.35
          ? const Color(0xFFE6E6E6)
          : theme;
    }
    if (background.computeLuminance() < 0.35) {
      return darkText ? theme : null;
    }
    if (style.hasExplicitTextColor) {
      return null;
    }
    return darkText ? theme : null;
  }

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
    final lookup = imageLookup;
    if (spec == null || lookup == null) {
      return;
    }
    final image = lookup(spec.imageUrl);
    if (image == null) {
      return;
    }
    paintBackgroundImage(
      canvas,
      image,
      pageRect,
      repeat: spec.repeat,
      size: spec.size,
      position: spec.position,
    );
  }

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
      // 浮动覆盖切片（flat 管线接入）：绝对定位，不推进流游标。
      final sliceY = slice.overlay ? slice.absoluteTop! : y;
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
          leftInset: slice.leftInset + style.margin.left,
          rightInset: style.margin.right + style.padding.right,
          upExtent: upExtent,
          downExtent: downExtent,
          pageWidth: pageSize.width,
        ),
      );
      if (!slice.overlay) {
        y += slice.height;
      }
    }
    return geometries;
  }

  /// 绘制顺序：`z-index` 升序，同层保持文档序（稳定排序）。
  static List<_SliceGeometry> _paintOrder(List<_SliceGeometry> geometries) {
    var needsSort = false;
    for (final geometry in geometries) {
      if (geometry.style.zIndex != 0) {
        needsSort = true;
        break;
      }
    }
    if (!needsSort) {
      return geometries;
    }
    final indexed = <(int, _SliceGeometry)>[
      for (var i = 0; i < geometries.length; i++) (i, geometries[i]),
    ]..sort((a, b) {
      final byZ = a.$2.style.zIndex.compareTo(b.$2.style.zIndex);
      return byZ != 0 ? byZ : a.$1.compareTo(b.$1);
    });
    return <_SliceGeometry>[for (final item in indexed) item.$2];
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
    final originY = style.transformOriginY.resolve(box.height) ?? box.height / 2;
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

  static List<double> _affineTranslate(double tx, double ty) =>
      <double>[1, 0, 0, 1, tx, ty];

  static List<double> _affineScale(double sx, double sy) =>
      <double>[sx, 0, 0, sy, 0, 0];

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

  /// 行尾字形（W13）：省略号 `…` 与断词连字符 `-`。
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
  /// 绘制按背景/边框/文本等阶段分别套一次：对书内卡片类元素观感等价，
  /// 与「整元素一次合成」的差别只在相邻半透明边缘的亚像素混合。
  void _withEffects(
    Canvas canvas,
    _SliceGeometry geometry,
    void Function() body,
  ) {
    final filters = geometry.style.filters;
    // 累计不透明度有两个来源：PageBlock（章节源按级联链乘积传入，W3 已接线）
    // 与 ComputedStyle.effectiveOpacity（样式层按父链乘积）。取两者较小值，
    // 既不会重复相乘，也能覆盖「只有一边带了祖先值」的调用路径。
    final opacity = math.min(
      geometry.slice.block.effectiveOpacity,
      geometry.style.effectiveOpacity,
    );
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
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
          );
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

  static List<double> _lerpMatrix(List<double> from, List<double> to, double t) {
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
        box.top +
        (borders.top.isVisible ? borders.top.width : 0) +
        padding.top;
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
  /// 内阴影由 [_paintInsetBoxShadow] 在背景之后绘制。
  /// 跨页切片不重复投影（首尾都在本页才画）。
  void _paintBoxShadow(Canvas canvas, _SliceGeometry geometry) {
    final shadow = geometry.style.boxShadow;
    if (shadow == null ||
        shadow.inset ||
        !geometry.startsBlock ||
        !geometry.endsBlock) {
      return;
    }
    final style = geometry.style;
    final borders = style.borders;
    final box = geometry.containerPaintBox;
    final blur = math.max(0.0, shadow.blur);
    final paint = Paint()..color = shadow.color;
    if (blur > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2);
    }
    canvas.drawRRect(
      _shadowRRect(
        borders,
        box.inflate(shadow.spread).translate(shadow.offsetX, shadow.offsetY),
        shadow.spread,
      ),
      paint,
    );
  }

  /// 内阴影（W2）：裁到 padding-box（Chromium 实测：透明边框下阴影不进入
  /// 边框区域），用「padding-box 外框 − 偏移/收缩后的洞」even-odd 挖洞后
  /// 一起模糊；圆角内阴影按直角洞近似（书内罕见）。
  void _paintInsetBoxShadow(Canvas canvas, _SliceGeometry geometry) {
    final shadow = geometry.style.boxShadow;
    if (shadow == null ||
        !shadow.inset ||
        !geometry.startsBlock ||
        !geometry.endsBlock) {
      return;
    }
    final style = geometry.style;
    final box = geometry.containerPaintBox;
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
    double grow(double radius) => math.max(0, radius + radiusDelta);
    return RRect.fromRectAndCorners(
      rect,
      topLeft: Radius.circular(grow(radii.topLeft)),
      topRight: Radius.circular(grow(radii.topRight)),
      bottomRight: Radius.circular(grow(radii.bottomRight)),
      bottomLeft: Radius.circular(grow(radii.bottomLeft)),
    );
  }

  /// 注音绘制（P8-08，CSS Ruby 1 flat 近似）：定位主文本区间所在行，
  /// 逐字符累进求区间起点 x，注音按 50% 字号居中画在行顶上方。
  void _paintRubies(
    Canvas canvas,
    _SliceGeometry geometry,
    List<RubyAnnotation> rubies,
  ) {
    final layout = geometry.slice.block.layout;
    final rubyStyle = geometry.textStyle.copyWith(
      fontSize: geometry.textStyle.fontSize != null
          ? geometry.textStyle.fontSize! * 0.5
          : null,
    );
    for (final ruby in rubies) {
      // 找覆盖区间起点的行。
      LineBox? hostLine;
      var hostIndex = geometry.slice.startLine;
      var lineY = geometry.y + geometry.leading;
      for (;
        hostIndex < geometry.slice.endLine;
        hostIndex++
      ) {
        final line = layout.lines[hostIndex];
        if (ruby.start >= line.start && ruby.start < line.end) {
          hostLine = line;
          break;
        }
        lineY += line.height;
      }
      if (hostLine == null) {
        continue;
      }
      final lineStart = hostLine.start;
      final prefix = layout.text.substring(lineStart, ruby.start);
      final painter = TextPainter(
        text: TextSpan(text: prefix, style: geometry.textStyle),
        textDirection: _textDirectionOf(layout),
      )..layout();
      final x0 = geometry.leftInset + hostLine.offsetX + painter.width;
      painter.dispose();
      final basePainter = TextPainter(
        text: TextSpan(
          text: layout.text.substring(ruby.start, ruby.end),
          style: geometry.textStyle,
        ),
        textDirection: _textDirectionOf(layout),
      )..layout();
      final baseWidth = basePainter.width;
      basePainter.dispose();
      final rubyPainter = TextPainter(
        text: TextSpan(text: ruby.text, style: rubyStyle),
        textDirection: _textDirectionOf(layout),
      )..layout();
      final rx = x0 + (baseWidth - rubyPainter.width) / 2;
      rubyPainter.paint(canvas, ui.Offset(rx, lineY - rubyPainter.height));
      rubyPainter.dispose();
    }
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
  ) {
    final top = geometry.y + geometry.leading;
    final height = spec.rowYs.last;
    // 表格原点与正文左缘对齐（P9-16）：列坐标是表格内的相对坐标，
    // 左内缩（容器内边距）与 margin 必须叠加，否则表格压到页边距外。
    final left = geometry.leftInset + geometry.style.margin.left;
    final tableStyle = geometry.style;
    if (tableStyle.backgroundColor.a > 0) {
      canvas.drawRect(
        Rect.fromLTWH(left, top, spec.tableWidth, height),
        Paint()..color = tableStyle.backgroundColor,
      );
    }
    for (final cell in spec.cells) {
      final style = cell.style;
      final cellRect = Rect.fromLTWH(
        left + cell.rect.left,
        top + cell.rect.top,
        cell.rect.width,
        cell.rect.height,
      );
      if (style.backgroundColor.a > 0) {
        canvas.drawRect(
          cellRect,
          Paint()..color = style.backgroundColor,
        );
      }
      _paintCellBorders(canvas, cellRect, style.borders);
    }
    for (final cell in spec.cells) {
      if (cell.layout.lineCount == 0) {
        continue;
      }
      final style = cell.style;
      final borders = style.borders;
      final leftInset = style.padding.left + borders.left.width;
      final rightInset = style.padding.right + borders.right.width;
      final topInset = style.padding.top + borders.top.width;
      final bottomInset = style.padding.bottom + borders.bottom.width;
      final innerWidth = math.max(
        8.0,
        cell.rect.width - leftInset - rightInset,
      );
      final innerHeight = math.max(
        0.0,
        cell.rect.height - topInset - bottomInset,
      );
      final textHeight = cell.layout.height;
      // 垂直对齐（P9-16）：书籍大量使用 td { vertical-align: top/middle }。
      final freeSpace = math.max(0.0, innerHeight - textHeight);
      final alignOffset = switch (style.verticalAlign) {
        CssVerticalAlign.middle => freeSpace / 2,
        CssVerticalAlign.bottom => freeSpace,
        _ => 0.0,
      };
      // 单元格文字同样走主题色策略（P9-23）：书籍没显式声明颜色的格
      // （如 RANK 标签）此前用初始黑色，深色底上直接看不见。
      final textStyleBase = TextLayoutEngine.textStyleFor(style);
      final override = _textColorFor(style);
      final textStyle = override == null
          ? textStyleBase
          : textStyleBase.copyWith(color: override);
      var lineY = top + cell.rect.top + topInset + alignOffset;
      for (var i = 0; i < cell.layout.lineCount; i++) {
        final line = cell.layout.lines[i];
        final text = cell.layout.text.substring(line.start, line.end);
        if (text.isNotEmpty) {
          // 单元格里的行内 span（P9-26）：按 run 组装 span，颜色/字号/边框
          // 才和书籍一致（RANK 金框、标签 chip）。
          final cellRuns = _lineRuns(cell.layout, line);
          final painter = TextPainter(
            text: cellRuns.isEmpty
                ? TextSpan(text: text, style: textStyle)
                : buildLineSpan(
                    layout: cell.layout,
                    line: line,
                    baseStyle: textStyle,
                  ),
            textDirection: cell.layout.isRtl
                ? TextDirection.rtl
                : TextDirection.ltr,
          )..layout(maxWidth: innerWidth);
          final contentLeft = left + cell.rect.left + leftInset;
          final contentRight = left + cell.rect.right - rightInset;
          var x = contentLeft;
          if (style.textAlign == CssTextAlign.center) {
            x = contentLeft + (contentRight - contentLeft - painter.width) / 2;
          } else if (style.textAlign == CssTextAlign.right ||
              style.textAlign == CssTextAlign.justify) {
            x = contentRight - painter.width;
          }
          _paintInlineBoxes(
            canvas,
            painter,
            cellRuns,
            x,
            lineY - (painter.height - line.height) / 2,
          );
          painter.paint(canvas, ui.Offset(x, lineY));
          painter.dispose();
        }
        lineY += line.height;
      }
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
      );
    }
    if (borders.bottom.isVisible) {
      final inset = borders.bottom.width / 2;
      _paintSide(
        canvas,
        borders.bottom,
        ui.Offset(rect.left, rect.bottom - inset),
        ui.Offset(rect.right, rect.bottom - inset),
      );
    }
    if (borders.left.isVisible) {
      final inset = borders.left.width / 2;
      _paintSide(
        canvas,
        borders.left,
        ui.Offset(rect.left + inset, rect.top),
        ui.Offset(rect.left + inset, rect.bottom),
      );
    }
    if (borders.right.isVisible) {
      final inset = borders.right.width / 2;
      _paintSide(
        canvas,
        borders.right,
        ui.Offset(rect.right - inset, rect.top),
        ui.Offset(rect.right - inset, rect.bottom),
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
    // 仍走文字绘制。
    final shape = _markerShapeOf(marker);
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
    final rect = Rect.fromLTWH(left, centerY - diameter / 2, diameter, diameter);
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
  /// 时按盒居中单行绘制（其余 payload 结构等章节源约定后接入）。
  void _paintInlineBoxPlacements(
    Canvas canvas,
    _SliceGeometry geometry,
    LineBox line,
    List<_LineRun> runs,
    double x,
    double lineY,
  ) {
    if (line.inlineBoxes.isEmpty) {
      return;
    }
    for (final placement in line.inlineBoxes) {
      final style = _inlineBoxStyleOf(placement, runs) ?? geometry.style;
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
        // 横排：盒顶 = 基线 − 基线以上延伸（行顶由 LineBox.baseline 反映）。
        rect = Rect.fromLTWH(
          x + placement.left,
          lineY + line.baseline - placement.ascent,
          placement.width,
          placement.height,
        );
      }
      // inline-block 盒子同样可能是半透明（payload.style.effectiveOpacity）。
      final opacity = math.min(style.effectiveOpacity, 1.0);
      final layered = opacity < 1;
      if (layered) {
        canvas.saveLayer(
          rect.inflate(8),
          Paint()..color = Color.fromRGBO(255, 255, 255, opacity),
        );
      }
      _paintBackground(
        canvas,
        rect,
        style,
        startsBlock: true,
        endsBlock: true,
      );
      _paintBorders(
        canvas,
        rect,
        style,
        startsBlock: true,
        endsBlock: true,
      );
      final payload = placement.spec.payload;
      if (payload is PageBlock) {
        _paintInlineBoxContent(canvas, payload, rect);
      } else if (payload is String && payload.isNotEmpty) {
        final painter = TextPainter(
          text: TextSpan(
            text: payload,
            style: TextLayoutEngine.textStyleFor(style),
          ),
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
  }

  /// 行内盒内容（payload = [PageBlock]）：内容盒内逐行画文字。
  ///
  /// `placement.width/height` 是边框盒尺寸，内容盒要再扣掉 payload 样式的
  /// padding 与边框；行 x = 内容盒左缘 + `line.offsetX`，行 y 自内容盒顶按
  /// `line.height` 累加，行内样式走 runs（颜色/字号/注音等）。
  void _paintInlineBoxContent(
    Canvas canvas,
    PageBlock box,
    Rect borderBox,
  ) {
    final style = box.style;
    if (style == null) {
      return;
    }
    final borders = style.borders;
    final padding = style.padding;
    final contentLeft =
        borderBox.left + padding.left + (borders.left.isVisible ? borders.left.width : 0);
    final contentTop =
        borderBox.top + padding.top + (borders.top.isVisible ? borders.top.width : 0);
    final contentRight =
        borderBox.right - padding.right - (borders.right.isVisible ? borders.right.width : 0);
    final contentWidth = math.max(1.0, contentRight - contentLeft);
    final contentBottom =
        borderBox.bottom - padding.bottom - (borders.bottom.isVisible ? borders.bottom.width : 0);
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
        textColorOverride: null,
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
    final textStyleBase = TextLayoutEngine.textStyleFor(style);
    var lineY = contentTop;
    for (var lineIndex = 0; lineIndex < layout.lineCount; lineIndex++) {
      final line = layout.lines[lineIndex];
      final text = layout.text.substring(line.start, line.end);
      if (text.isNotEmpty) {
        final runs = _lineRuns(layout, line);
        final painter = TextPainter(
          text: runs.isEmpty
              ? TextSpan(text: text, style: textStyleBase)
              : buildLineSpan(
                  layout: layout,
                  line: line,
                  baseStyle: textStyleBase,
                ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: contentWidth);
        painter.paint(
          canvas,
          Offset(contentLeft + line.offsetX, lineY),
        );
        painter.dispose();
      }
      lineY += line.height;
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

  /// 行内元素盒（P9-24）：`display:inline-block` 的行内 span 的背景、
  /// 边框与内边距在文字下方绘制（RANK 金框、状态标签 chip 等）。
  ///
  /// 排版宽度没有把行内 padding 计入（flat 管线不做行内盒布局），这里
  /// 按字形框外扩 padding 绘制——视觉上还原书籍设计，代价是与相邻文字
  /// 可能轻微重叠。
  void _paintInlineBoxes(
    Canvas canvas,
    TextPainter painter,
    List<_LineRun> runs,
    double x,
    double y,
  ) {
    for (final run in runs) {
      final style = run.style;
      final hasBackground = style.backgroundColor.a > 0;
      final hasBorder = style.borders.hasBorder;
      if ((!hasBackground && !hasBorder) || run.end <= run.start) {
        continue;
      }
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: run.start, extentOffset: run.end),
        boxHeightStyle: ui.BoxHeightStyle.includeLineSpacingMiddle,
      );
      for (final box in boxes) {
        final rect = Rect.fromLTRB(
          x + box.left - style.padding.left,
          y + box.top - style.padding.top,
          x + box.right + style.padding.right,
          y + box.bottom + style.padding.bottom,
        );
        if (hasBackground) {
          final radii = style.borders;
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              rect,
              topLeft: Radius.circular(radii.topLeftRadius),
              topRight: Radius.circular(radii.topRightRadius),
              bottomRight: Radius.circular(radii.bottomRightRadius),
              bottomLeft: Radius.circular(radii.bottomLeftRadius),
            ),
            Paint()..color = style.backgroundColor,
          );
        }
        if (hasBorder) {
          _paintBorders(
            canvas,
            rect,
            style,
            startsBlock: true,
            endsBlock: true,
          );
        }
      }
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
    // 百分比圆角按盒子尺寸解算（`border-radius: 50%` 的圆形头像）。
    final radii = style.borders.radiiFor(box.size);
    final rounded = RRect.fromRectAndCorners(
      box,
      topLeft: Radius.circular(startsBlock ? radii.topLeft : 0),
      topRight: Radius.circular(startsBlock ? radii.topRight : 0),
      bottomRight: Radius.circular(endsBlock ? radii.bottomRight : 0),
      bottomLeft: Radius.circular(endsBlock ? radii.bottomLeft : 0),
    );
    final roundedCorners =
        rounded.tlRadiusX > 0 ||
        rounded.trRadiusX > 0 ||
        rounded.brRadiusX > 0 ||
        rounded.blRadiusX > 0;
    if (style.backgroundColor.a != 0) {
      // 背景色按 background-clip 裁剪区域绘制（P3：origin/clip 语义）。
      canvas.save();
      canvas.clipRect(_backgroundClipRect(box, style));
      canvas.drawRRect(rounded, Paint()..color = style.backgroundColor);
      canvas.restore();
    }
    // 渐变背景（W2）：样式层把 `background-image: <gradient>` 解析成
    // CssLinearGradient / CssRadialGradient。渐变几何按 background-origin
    // 的定位区解算（默认 padding-box，与浏览器一致），裁剪与圆角沿用背景色。
    final gradient = style.backgroundGradient;
    if (gradient != null) {
      final shader = _gradientShader(
        gradient,
        _backgroundOriginRect(box, style),
      );
      if (shader != null) {
        canvas.save();
        canvas.clipRect(_backgroundClipRect(box, style));
        if (roundedCorners) {
          canvas.clipRRect(rounded);
        }
        canvas.drawRect(box, Paint()..shader = shader);
        canvas.restore();
      }
    }
    final image = _resolveBackgroundImage(style);
    if (image == null) {
      return;
    }
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
      case CssLinearGradient():
        final radians = gradient.angle * math.pi / 180;
        final direction = Offset(math.sin(radians), -math.cos(radians));
        final length =
            area.width * direction.dx.abs() +
            area.height * direction.dy.abs();
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
          (
            color: stops[i].color,
            position: (positions[i]! - first) / period,
          ),
      ],
      periodFraction: period,
    );
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
        final radii = borders.radiiFor(box.size);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            box.deflate(half),
            topLeft: Radius.circular(math.max(0, radii.topLeft - half)),
            topRight: Radius.circular(math.max(0, radii.topRight - half)),
            bottomRight: Radius.circular(math.max(0, radii.bottomRight - half)),
            bottomLeft: Radius.circular(math.max(0, radii.bottomLeft - half)),
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
    // 分边绘制：宽度/线型/颜色不同时按边画，圆角只在圆角样本的整框路径里用。
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
        // 3D 边框（CSS Backgrounds §4.4）：外半深/内半浅（groove/inset）或
        // 相反（ridge/outset）。缺朝向信息时退回实线，避免画错明暗。
        if (outward == null || side.width < 2) {
          canvas.drawLine(start, end, paint);
          break;
        }
        final half = side.width / 2;
        final dark = _shade(side.color, 0.62);
        final light = _shade(side.color, 1.35);
        final grooveLike =
            side.style == CssBorderStyle.groove ||
            side.style == CssBorderStyle.inset;
        final outerPaint = Paint()
          ..color = grooveLike ? dark : light
          ..strokeWidth = half
          ..strokeCap = StrokeCap.butt;
        final innerPaint = Paint()
          ..color = grooveLike ? light : dark
          ..strokeWidth = half
          ..strokeCap = StrokeCap.butt;
        final shift = outward * (half / 2);
        canvas.drawLine(start + shift, end + shift, outerPaint);
        canvas.drawLine(start - shift, end - shift, innerPaint);
      case CssBorderStyle.none:
        break;
    }
  }

  /// 明暗调整（3D 边框用）：按比例缩放 RGB 通道。
  static Color _shade(Color color, double factor) => Color.from(
    alpha: color.a,
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
  }) {
    TextPainter build() => TextPainter(
      text: _lineSpan(
        layout,
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
        '${page.spineIndex}:${page.pageIndex}:$sliceIndex:$lineIndex:'
        '${baseStyle.fontSize}:${baseStyle.height}:'
        '${baseStyle.letterSpacing}:${baseStyle.wordSpacing}:'
        '${baseStyle.color?.toARGB32()}:'
        '${textColorOverride?.toARGB32()}:'
        '${line.justifyExtra.toStringAsFixed(3)}';
    return cache.obtain(key, build: build);
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
    final metrics = TextLayoutEngine.verticalGlyphMetrics(layout.text, style);
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
            : _verticalStyleOf(runStyle, textColorOverride);
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
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: textDirection,
    )..layout();
    if (upright) {

      // 正立：横向居中于列宽，纵向让字形盒中心落在本次 advance 的中点。
      painter.paint(
        canvas,
        Offset(
          columnLeft + (columnWidth - painter.width) / 2,
          y - (painter.height - advance) / 2,
        ),
      );
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
    final color =
        style.textDecorationColor ?? textColorOverride ?? style.color;
    final thickness = math
        .max(1.0, (style.fontSize / 10).floorToDouble())
        .toDouble();
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness;
    void line(double x) {
      canvas.drawLine(
        Offset(x, top),
        Offset(x, top + advance),
        paint,
      );
    }

    if (decoration == CssTextDecoration.underline) {
      line(columnLeft + columnWidth * 0.13);
    }
    if (decoration == CssTextDecoration.lineThrough) {
      line(columnLeft + columnWidth / 2);
    }
    if (decoration == CssTextDecoration.overline) {
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
    final radius = math.max(1.0, style.fontSize * 0.08);
    final paint = Paint()
      ..color = style.textEmphasisColor ?? textColorOverride ?? style.color;
    if (emphasis == CssTextEmphasisStyle.open) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, style.fontSize * 0.05);
    }
    // over → 列右缘；under → 列左缘（竖排的 over 侧就是右）。
    final centerX = style.textEmphasisPosition == CssTextEmphasisPosition.under
        ? columnLeft + radius + 1
        : columnLeft + columnWidth - radius - 1;
    canvas.drawCircle(Offset(centerX, centerY), radius, paint);
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
    final rubySize = style.fontSize * 0.5;
    final rubyStyle = TextLayoutEngine.textStyleFor(
      style,
    ).copyWith(fontSize: rubySize);
    for (final ruby in rubies) {
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
        final advanceTotal = ruby.text.length * rubySize;
        var rubyY = top + (bottom - top - advanceTotal) / 2;
        // 注音中心 ≈ 列右缘（Chromium 实测）：用一个宽度 = 注音字号的
        // 虚拟列贴在列右缘内侧来复用居中绘制。
        final rubyColumnLeft = columnLeft + column.width - rubySize / 2;

        for (final rune in ruby.text.runes) {
          _paintVerticalGlyph(
            canvas,
            String.fromCharCode(rune),
            rubyStyle.copyWith(color: style.color),
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
    final textStyle = _withoutDecoration(
      TextLayoutEngine.textStyleFor(style),
    );
    return textColorOverride == null
        ? textStyle
        : textStyle.copyWith(color: textColorOverride);
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
        textDirection: painter.textDirection,
      )..layout();
      segmentPainter.paint(
        canvas,
        Offset(x + boxes.first.left, y + segment.baselineShift),
      );
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
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: band.start, extentOffset: band.end),
      );
      if (boxes.isEmpty) {
        continue;
      }
      final left = x + boxes.first.left;
      final right = x + boxes.last.right;
      if (right <= left) {
        continue;
      }
      final thickness = math.max(1.0, (band.fontSize / 10).floorToDouble());
      final baselineY = y + baseline + band.baselineShift;
      // 实线顶边：line-through / overline 在基线上方，下划线在下方。
      final double solidTop;
      switch (band.decoration) {
        case CssTextDecoration.overline:
          solidTop =
              baselineY - (band.ascent + thickness).roundToDouble();
        case CssTextDecoration.underline:
          // 下划线：基线下方 max(1, round(字号/16))（Chromium 17px 实测 +1）。
          solidTop =
              baselineY + math.max(1.0, (band.fontSize / 16).roundToDouble());
        case CssTextDecoration.lineThrough:
        case CssTextDecoration.none:
          solidTop =
              baselineY -
              ((band.ascent - band.descent) / 2).roundToDouble();
      }
      _paintDecorationBand(
        canvas,
        band,
        left: left,
        right: right,
        // 对齐设备像素（Chromium 同样把装饰线吸附到整数像素），细线更清晰。
        solidTop: solidTop.roundToDouble(),
        thickness: thickness,
      );
    }
  }

  /// 按线型画一段装饰线：实线 / 点线 / 虚线 / 波浪。
  void _paintDecorationBand(
    Canvas canvas,
    _DecorationBand band, {
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
        final bandTop = band.decoration == CssTextDecoration.underline
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
        ? (
            ascent: style.fontSize * 1.15,
            descent: style.fontSize * 0.29,
          )
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

  /// 画行内图片（P9-06）：图片画在 U+FFFC 占位符的字形框上。
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
      final aspect = image.height == 0 ? 1.0 : image.width / image.height;
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
        Rect.fromLTWH(
          0,
          0,
          image.width.toDouble(),
          image.height.toDouble(),
        ),
        Rect.fromLTWH(left, boxBottom - height, width, height),
        Paint()..filterQuality = FilterQuality.medium,
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
    this.textColorOverride,
  });

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
  bool get textAutospace =>
      style.textAutospace == CssTextAutospace.normal;

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

  /// 背景/边框盒子（含首尾内缩）。
  Rect get box => Rect.fromLTWH(0, y, pageWidth, slice.height);

  /// 背景/边框盒子（margin 修正）：flat 管线 box.left 恒 0，块级
  /// margin.left 折算进左缘，使背景与边框跟文本 x（已含 margin）对齐；
  /// 右缘同步扣除 margin.right，与收窄后的排版宽度同界。
  /// 容器拼合盒（P9-25）：带边框容器里的子块，把背景与左右边框延伸到
  /// 自己的上下段距，多个子块叠起来就拼回一整片面板。
  Rect get containerPaintBox {
    final base = borderBox;
    if (!slice.block.containerSides) {
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
    final block = slice.block;
    final top = slice.leadingExtent > 0
        ? y + slice.leadingExtent - block.topInset
        : y;
    final bottom = slice.trailingExtent > 0
        ? y + slice.height - slice.trailingExtent + block.bottomInset
        : y + slice.height;
    // 横向按解算后的内容宽（`width` 声明 / auto）× box-sizing 定右边：
    // 声明了 width 的块背景与 overflow 裁剪都要收在声明宽内（Chromium 的
    // used width 口径）；auto 时与「页宽 − margin」等价。
    // 竖排块（W22）：内容是「列带」，块宽收缩到列数×列宽（Chromium 实测
    // 35 用例 .v 宽 98 = 4 列×24 + 边框），不能用页宽。
    final model = _boxModel;
    final left = block.bleedLeft ? 0.0 : style.margin.left;
    final contentWidth = isVerticalBlock
        ? block.layout.width
        : model.resolveContentWidth(pageWidth);
    final right = block.bleedRight
        ? pageWidth
        : left + contentWidth + model.horizontalInset;
    return Rect.fromLTRB(left, top, right, bottom);
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

  /// 按切片裁剪；上下标越界时放宽上下边。
  void clip(Canvas canvas) {
    final clip = slice.clipRect(y, pageWidth);
    // 容器内子块（P9-25）的背景/边框会延伸到上下段距，裁剪同步放宽。
    final containerTop = slice.block.containerSides ? slice.leadingExtent : 0.0;
    final containerBottom = slice.block.containerSides
        ? slice.trailingExtent
        : 0.0;
    canvas.clipRect(
      Rect.fromLTRB(
        clip.left,
        clip.top - upExtent - containerTop,
        clip.right,
        clip.bottom + downExtent + containerBottom,
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
