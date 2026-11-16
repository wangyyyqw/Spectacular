import 'dart:math' as math;

import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/box_model.dart';
import 'package:reader_core/layout/float_occupancy.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/intrinsic_widths.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout_cache.dart';
import 'package:reader_core/paint/image_size.dart';
import 'package:reader_core/position/text_cfi_map.dart';

import '../../util/bounded_cache.dart';
import 'chapter_layout_job.dart';
import 'container_blocks.dart';

/// 所有章节文字测量共用冻结字体和时间预算；只缓存已完成的等价结果。
class ChapterTextMeasurer {
  ChapterTextMeasurer(
    this.snapshot,
    this.budget,
    this._layoutCache,
    this._textWidthCache,
  );
  final LayoutSnapshot snapshot;
  final LayoutBudget budget;
  final TextLayoutCache _layoutCache;
  final BoundedCache<String, double> _textWidthCache;
  double get contentWidth => snapshot.width;
  double get contentHeight => snapshot.height;

  static bool isOrdinaryHorizontalBlock(ComputedStyle style) =>
      style.writingMode == CssWritingMode.horizontalTb &&
      style.cssFloat == CssFloat.none &&
      !style.isOutOfFlow &&
      (style.display == CssDisplay.block ||
          style.display == CssDisplay.listItem);

  /// 字段与核心测量接口一致，保留混排、ruby 和原子盒的独立几何输入。
  Future<TextLayoutResult> layout({
    required String text,
    required ComputedStyle style,
    required double maxWidth,
    List<StyledRun> runs = const [],
    List<RubyAnnotation> rubies = const [],
    List<InlineBoxSpec> inlineBoxes = const [],
    bool preserveContentWidth = false,
    ComputedStyle? firstLineStyle,
    List<StyledRun>? firstLineRuns,
  }) async {
    if (inlineBoxes.isEmpty) {
      return _layoutCache.layoutAsync(
        text: text,
        style: style,
        maxWidth: maxWidth,
        runs: runs,
        rubies: rubies,
        hasGlyph: snapshot.fonts.hasGlyph,
        fontDependency: snapshot.fontDependency,
        checkpoint: budget.checkpoint,
        preserveContentWidth: preserveContentWidth,
        firstLineStyle: firstLineStyle,
        firstLineRuns: firstLineRuns,
      );
    }
    return TextLayoutEngine.layoutAsync(
      text: text,
      style: style,
      maxWidth: maxWidth,
      runs: runs,
      rubies: rubies,
      inlineBoxes: inlineBoxes,
      hasGlyph: snapshot.fonts.hasGlyph,
      checkpoint: budget.checkpoint,
      lineBreaker: preserveContentWidth ? LineBreaker(minimumWidthEm: 0) : null,
      firstLineStyle: firstLineStyle,
      firstLineRuns: firstLineRuns,
    );
  }

  /// 文本块的排版宽度 = 块的内容盒宽（CSS 2.1 §10.3.3）。
  ///
  /// flat 管线把块级水平内缩折算进绘制左偏移（PagePainter 取
  /// `slice.leftInset + style.margin.left`），排版宽度必须同步扣掉同一份
  /// 内缩——否则带 margin/padding 的段落整体右移、压出正文区右缘被裁切
  /// （真机：作者 CSS `body`/`p` 各 1% 外边距 → 正文右偏且缺右缘字）。
  /// 解算规则由 [ComputedStyle.contentBoxWidth] 统一承担：
  /// - `width: auto`（含未声明）：内容宽 = 正文区宽 - margin - padding -
  ///   border；
  /// - 声明 `width`：按 `box-sizing` 折算内容宽——`content-box` 下声明值
  ///   就是内容宽，`border-box` 下声明值已含 padding+border，必须再扣掉，
  ///   否则 `.bb{box-sizing:border-box;width:200px;padding:10px;border:3px}`
  ///   会按 200px 排版（内容宽 174px 却排 200px，行宽溢出正文区）；
  /// - 最后按 min/max-width 钳制（min 优先）。
  ///
  /// 依赖：T2 在 ComputedStyle 侧提供的 `contentBoxWidth`（把 box-sizing /
  /// 百分比基准 / min-max 钳制收敛在一处，与 `BoxModel` 同口径）；这里只
  /// 对未声明宽度的正文保留 24px 下限；作者明确指定的窄列保留内容宽。
  double textWidthFor(ComputedStyle style, {bool preserveNarrowWidth = false}) {
    final width = style.contentBoxWidth(contentWidth);
    return preserveNarrowWidth ||
            style.intrinsicWidth != null ||
            (style.width != null && !style.width!.isAuto)
        ? width
        : math.max(24.0, width);
  }

  /// 只为声明内在宽度的横排块测量，普通正文保持原来的单次布局。
  Future<IntrinsicWidths> intrinsicWidths(
    String text,
    ComputedStyle style, {
    List<StyledRun> runs = const [],
    List<RubyAnnotation> rubies = const [],
    List<InlineBoxSpec> inlineBoxes = const [],
  }) async {
    final unbounded = await layout(
      text: text,
      style: style,
      maxWidth: double.infinity,
      runs: runs,
      rubies: rubies,
      inlineBoxes: inlineBoxes,
    );
    var max = 0.0;
    for (final (index, line) in unbounded.lines.indexed) {
      await budget.checkpoint();
      max = math.max(
        max,
        line.advanceWidth + (index == 0 ? style.textIndent : 0),
      );
    }
    var min = await _minIntrinsicWidth(text, style, runs);
    for (final box in inlineBoxes) {
      await budget.checkpoint();
      min = math.max(min, box.outerWidth);
    }
    return IntrinsicWidths(minContent: math.min(min, max), maxContent: max);
  }

  Future<double> _minIntrinsicWidth(
    String text,
    ComputedStyle style,
    List<StyledRun> runs,
  ) async {
    final key = 'min-content|${_textWidthKey(text, style)}';
    final cached = runs.isEmpty ? _textWidthCache[key] : null;
    if (cached != null) return cached;
    final width = await TextLayoutEngine.minContentTextWidthAsync(
      text: text,
      style: style,
      runs: runs,
      hasGlyph: snapshot.fonts.hasGlyph,
      checkpoint: budget.checkpoint,
    );
    budget.check();
    if (runs.isEmpty) _textWidthCache[key] = width;
    return width;
  }

  /// 浮动文本块：`PageBlock.styled` 不透传 floatSide，这里按同一口径
  /// 直接构造（内缩 = 边框 + 内边距；声明高度走 [BoxModel] 解算）。
  PageBlock floatedTextBlock({
    required TextLayoutResult layout,
    required ComputedStyle style,
    required FloatSide side,
    required double spaceBefore,
    required double spaceAfter,
    List<InlineImageSpec> inlineImages = const <InlineImageSpec>[],
    List<PageFootnote> footnotes = const <PageFootnote>[],
    bool textRuleEligible = true,
    List<RubyAnnotation>? rubies,
    String? startCfi,
    TextCfiMap? textCfis,
    int groupId = 0,
    bool containerSides = false,
    double effectiveOpacity = 1,
    double? containingLeft,
    double? containingWidth,
  }) {
    final model = BoxModel.fromStyle(style, containingWidth: contentWidth);
    return PageBlock(
      layout: layout,
      style: style,
      floatSide: side,
      effectiveOpacity: effectiveOpacity,
      spaceBefore: spaceBefore,
      spaceAfter: spaceAfter,
      topInset: model.borders.top + model.padding.top,
      bottomInset: model.borders.bottom + model.padding.bottom,
      leftInset: model.borders.left + model.padding.left,
      inlineImages: inlineImages,
      footnotes: footnotes,
      textRuleEligible: textRuleEligible,
      rubies: rubies,
      declaredContentHeight: model.resolveContentHeight(
        layout.height,
        containingHeight: contentHeight,
      ),
      verticalContentWidth: layout.isVertical
          ? model.resolveContentWidth(contentWidth)
          : null,
      startCfi: startCfi,
      textCfis: textCfis,
      groupId: groupId,
      containerSides: containerSides,
      floatContainingLeft: containingLeft,
      floatContainingWidth: containingWidth,
    );
  }

  /// `initial-letter` 首字块：只保留字符自身的文字样式，清空段落盒的
  /// 背景、边框、内边距和上下外边距，右侧留出 [gap] 给正文绕排。
  Future<PageBlock> dropCapBlock({
    required String text,
    required ComputedStyle style,
    required double bodyLineHeight,
    required double lineCount,
    required double gap,
    required double effectiveOpacity,
    String? startCfi,
    TextCfiMap? textCfis,
  }) async {
    final extent = bodyLineHeight * lineCount;
    final declarations = <String, String>{
      'margin': '0 ${gap.toStringAsFixed(2)}px 0 0',
      'padding': '0',
      'border': '0',
      'background-color': 'transparent',
      'background-image': 'none',
      'line-height': '${extent.toStringAsFixed(2)}px',
      'float': 'left',
    };
    if (!style.explicitProperties.contains('font-size')) {
      declarations['font-size'] = '${(extent * 0.85).toStringAsFixed(2)}px';
    }
    final dropStyle = ComputedStyle(
      declarations,
      parent: style,
      explicitProperties: declarations.keys.toSet(),
      containingWidth: contentWidth,
      rootFontSize: style.fontSize,
    );
    final measured = await layout(
      text: text,
      style: dropStyle,
      maxWidth: contentWidth,
    );
    final glyphWidth = measured.lines.isEmpty
        ? 1.0
        : measured.lines.first.advanceWidth.clamp(1.0, contentWidth);
    return floatedTextBlock(
      layout: pageBlockWithLayoutWidth(
        measured,
        width: glyphWidth,
        maxWidth: glyphWidth,
      ),
      style: dropStyle,
      side: FloatSide.left,
      spaceBefore: 0,
      spaceAfter: 0,
      startCfi: startCfi,
      textCfis: await textCfis?.transformedAsync(
        measured.inputOffsets,
        checkpoint: budget.checkpoint,
      ),
      effectiveOpacity: effectiveOpacity,
    );
  }

  Future<PageBlock?> emptyBoxBlock(
    ComputedStyle style,
    double contentWidth, {
    required double containingHeight,
    PageFloatBox? floatBox,
  }) async {
    if (style.display == CssDisplay.none ||
        style.visibility != CssVisibility.visible) {
      return null;
    }
    final hasBackground =
        style.backgroundColor.a > 0 ||
        style.backgroundLayers.any(
          (layer) => layer.image != null || layer.gradient != null,
        );
    final hasBorder = style.borders.hasBorder;
    final hasClearance = style.clear != CssClear.none;
    final hasSpacing =
        style.margin.top != 0 ||
        style.margin.bottom != 0 ||
        style.padding.vertical > 0;
    final declaredHeight = style.height?.resolve(contentWidth);
    final declaredMinHeight = style.minHeight?.resolve(contentWidth);
    if (!hasBackground &&
        !hasBorder &&
        !hasClearance &&
        !hasSpacing &&
        (declaredHeight == null || declaredHeight <= 0) &&
        (declaredMinHeight == null || declaredMinHeight <= 0)) {
      return null;
    }
    final absoluteBox = style.resolveAbsoluteBox(
      containingWidth: contentWidth,
      containingHeight: containingHeight,
    );
    final model = BoxModel.fromStyle(style, containingWidth: contentWidth);
    final boxWidth =
        absoluteBox?.width ??
        (style.isOutOfFlow
            ? 0.0
            : model.resolveContentWidth(
                contentWidth,
                intrinsicWidths:
                    style.writingMode == CssWritingMode.horizontalTb
                    ? IntrinsicWidths.zero
                    : null,
              ));
    return PageBlock.styled(
      // 空盒没有文字行高，零高行只承载盒装饰和外边距的分页占位。
      layout: TextLayoutResult(
        text: '',
        lines: const [
          LineBox(start: 0, end: 0, top: 0, height: 0, baseline: 0, width: 0),
        ],
        width: boxWidth,
        height: 0,
        maxWidth: boxWidth,
        runs: const [],
      ),
      style: style,
      containingWidth: contentWidth,
      absolute: style.isOutOfFlow,
      absoluteTop: absoluteBox?.top,
      absoluteLeft: absoluteBox?.left,
    ).withSpacing(
      floatSide: switch (style.cssFloat) {
        CssFloat.left => FloatSide.left,
        CssFloat.right => FloatSide.right,
        CssFloat.none => null,
      },
      // 原子空盒只绘自身装饰，父包含块坐标独立参与浮动占位。
      floatContainingLeft: floatBox?.containingLeft,
      floatContainingWidth: floatBox?.containingWidth,
    );
  }

  /// min-content 的近似：中文逐字可断，拉丁词保持完整。
  Future<double> minContentTextWidth({
    required String text,
    required bool breakEverywhere,
    required ComputedStyle style,
  }) async {
    final segments = await _minContentSegments(text, breakEverywhere);
    await _measureMinContentSegments(segments, style);
    var widest = 0.0;
    for (final segment in segments) {
      await budget.checkpoint();
      widest = math.max(
        widest,
        _textWidthCache[_textWidthKey(segment, style)] ?? 0,
      );
    }
    return widest;
  }

  Future<List<String>> _minContentSegments(
    String text,
    bool breakEverywhere,
  ) async {
    final segments = <String>[];
    final buffer = StringBuffer();
    void flush() {
      if (buffer.isEmpty) return;
      segments.add(buffer.toString());
      buffer.clear();
    }

    for (final rune in text.runes) {
      await budget.checkpoint();
      if (rune == 0x09 || rune == 0x0A || rune == 0x0D || rune == 0x20) {
        flush();
        continue;
      }
      if (breakEverywhere || _isCjkBreakRune(rune)) {
        flush();
        segments.add(String.fromCharCode(rune));
        continue;
      }
      buffer.writeCharCode(rune);
    }
    flush();
    return segments;
  }

  Future<void> _measureMinContentSegments(
    List<String> segments,
    ComputedStyle style,
  ) async {
    final missing = <String>{};
    for (final segment in segments) {
      await budget.checkpoint();
      if (!_textWidthCache.containsKey(_textWidthKey(segment, style))) {
        missing.add(segment);
      }
    }
    final pending = missing.toList();
    for (var start = 0; start < pending.length; start += 16) {
      await budget.checkpoint();
      final widths = TextLayoutEngine.measureTextWidths(
        texts: pending.sublist(start, math.min(start + 16, pending.length)),
        style: style,
        hasGlyph: snapshot.fonts.hasGlyph,
      );
      for (final entry in widths.entries) {
        await budget.checkpoint();
        _textWidthCache[_textWidthKey(entry.key, style)] = entry.value;
      }
    }
  }

  String _textWidthKey(String text, ComputedStyle style) =>
      '${snapshot.fontDependency}|${style.layoutFingerprint}\u0000$text';

  /// 行内替换图按原始尺寸收缩，不沿用块图的默认全宽。
  ImageDisplaySize inlineImageSize(
    ComputedStyle style,
    ImageIntrinsicSize? intrinsic,
    double availableWidth,
  ) {
    final model = BoxModel.fromStyle(style, containingWidth: availableWidth);
    var width = model.contentWidth;
    var height = model.contentHeight;
    final ratio = style.aspectRatio;
    if (ratio != null) {
      if (width != null && height == null) height = width / ratio;
      if (height != null && width == null) width = height * ratio;
    }
    if (width == null && height == null && intrinsic == null) {
      height = style.fontSize;
      width = height * (ratio ?? 1);
    }
    final size = ImageDisplaySizing.compute(
      maxWidth: math.max(
        1,
        availableWidth - model.horizontalInset - model.margin.horizontal,
      ),
      intrinsicWidth: intrinsic?.width,
      intrinsicHeight: intrinsic?.height,
      cssWidth: width,
      cssHeight: height,
    );
    return ImageDisplaySize(
      width: model.borderBoxWidth(size.width),
      height: model.borderBoxHeight(size.height),
    );
  }

  /// CJK 与全角字符通常可在相邻字符之间断行。
  static bool _isCjkBreakRune(int rune) =>
      (rune >= 0x2E80 && rune <= 0x303F) ||
      (rune >= 0x3040 && rune <= 0x30FF) ||
      (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0xAC00 && rune <= 0xD7AF) ||
      (rune >= 0xF900 && rune <= 0xFAFF) ||
      (rune >= 0xFF00 && rune <= 0xFFEF) ||
      (rune >= 0x1F000 && rune <= 0x1FAFF);

  Future<double> insideMarkerIndent(String marker, ComputedStyle style) async {
    const gapEm = 0.333;
    const symbolAdvanceEm = 1.067;
    final isSymbol =
        style.listStyleType != CssListStyleType.custom &&
        (marker == '•' || marker == '○' || marker == '▪');
    final advance = isSymbol
        ? style.fontSize * symbolAdvanceEm
        : (await _layoutCache.layoutAsync(
            text: marker,
            style: style,
            maxWidth: contentWidth,
            fontDependency: snapshot.fontDependency,
            checkpoint: budget.checkpoint,
          )).lines.first.width;
    return advance + style.fontSize * gapEm;
  }
}
