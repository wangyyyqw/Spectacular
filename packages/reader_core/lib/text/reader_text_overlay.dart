import 'dart:convert';

import 'package:flutter/painting.dart';

import '../css/computed_style.dart';
import '../layout/line_breaker.dart';
import '../position/cfi.dart';
import '../position/text_cfi_map.dart';

/// 基于原文 CFI 的文字覆盖；字体与点九占位参与测量，颜色仅参与绘制。
class ReaderTextOverlay {
  /// 创建半开原文区间，字号与字距相对命中处的作者字体解算。
  const ReaderTextOverlay({
    required this.startCfi,
    required this.endCfi,
    this.fontFamily,
    this.fontSizeScale = 1,
    this.fontWeight,
    this.italic,
    this.letterSpacingEm = 0,
    this.color,
    this.colorOpacity = 1,
    this.paddingByTextHeight,
    this.paddingLogicalPixels,
  });

  /// 原文起点与终点，不包含终点字符。
  final String startCfi;
  final String endCfi;

  /// 字体族；空值表示继承作者字体。
  final String? fontFamily;

  /// 字号比例，非法数值回退为 1，合法范围为 0.75～2。
  final double fontSizeScale;

  /// 字重与斜体；空值表示继承。
  final int? fontWeight;
  final bool? italic;

  /// 字距，单位为最终字号的 em；0 表示不覆盖作者字距。
  final double letterSpacingEm;

  /// ARGB 文字色及其透明度；空颜色不覆盖作者配色。
  final int? color;
  final double colorOpacity;

  final EdgeInsets? paddingByTextHeight;

  /// 规则 CSS 留白使用逻辑像素；未指定时保留点九按字高计算的行为。
  final EdgeInsets? paddingLogicalPixels;

  /// 是否包含字体或行内占位度量，不包含颜色变化。
  bool get affectsTypography =>
      normalizedFontFamily != null ||
      normalizedFontSizeScale != 1 ||
      fontWeight != null ||
      italic != null ||
      normalizedLetterSpacingEm != 0 ||
      paddingLogicalPixels != null && paddingLogicalPixels != EdgeInsets.zero ||
      paddingByTextHeight != null && paddingByTextHeight != EdgeInsets.zero;

  /// 去除空白后的字体族；空字符串视为继承。
  String? get normalizedFontFamily =>
      fontFamily?.trim().isEmpty ?? true ? null : fontFamily!.trim();

  /// 经范围校验的字号比例。
  double get normalizedFontSizeScale =>
      fontSizeScale.isFinite ? fontSizeScale.clamp(0.75, 2.0) : 1;

  /// 经范围校验的字距。
  double get normalizedLetterSpacingEm =>
      letterSpacingEm.isFinite ? letterSpacingEm.clamp(-0.05, 0.2) : 0;

  /// 只包含度量字段的稳定指纹，供分页缓存区分覆盖版本。
  String get typographyFingerprint => jsonEncode([
    startCfi,
    endCfi,
    normalizedFontFamily,
    normalizedFontSizeScale,
    fontWeight?.clamp(100, 900),
    italic,
    normalizedLetterSpacingEm,
    if (paddingByTextHeight case final padding?) ...[
      padding.left,
      padding.top,
      padding.right,
      padding.bottom,
    ],
    if (paddingLogicalPixels case final padding?) ...[
      'px',
      padding.left,
      padding.top,
      padding.right,
      padding.bottom,
    ],
  ]);

  /// 经透明度校验的绘制色；保持颜色自带的 alpha。
  Color? get paintColor {
    final value = color;
    if (value == null) return null;
    final opacity = colorOpacity.isFinite ? colorOpacity.clamp(0.0, 1.0) : 1.0;
    final result = Color(value);
    return result.withValues(alpha: result.a * opacity);
  }
}

/// 支持原文文字覆盖的章节源；返回值表示字体或行内占位是否改变。
abstract interface class ReaderTextOverlaySource {
  /// 替换当前覆盖列表；颜色变化不得失效分页与段落测量缓存。
  Future<bool> applyTextOverlays(List<ReaderTextOverlay> overlays);
}

/// 将 CFI 覆盖映射到块内 UTF-16 区间，保留原文及作者样式边界。
class ReaderTextOverlayResolver {
  /// 预解析覆盖端点；非法及反向区间忽略，不生成半成品样式。
  ReaderTextOverlayResolver(
    List<ReaderTextOverlay> overlays, {
    this.typography = true,
    this.colors = true,
  }) : _ranges = [
         for (final overlay in overlays)
           if (typography &&
                   (overlay.affectsTypography ||
                       overlay.paddingByTextHeight != null ||
                       overlay.paddingLogicalPixels != null) ||
               colors && overlay.color != null)
             ?_TextOverlayRange.parse(overlay),
       ];

  /// 是否覆盖字体度量。
  final bool typography;

  /// 是否覆盖文字色。
  final bool colors;

  final List<_TextOverlayRange> _ranges;

  /// 有效覆盖的字体度量指纹；颜色及无效区间不会改变它。
  late final String typographyFingerprint = jsonEncode([
    for (final range in _ranges)
      if (range.overlay.affectsTypography ||
          range.overlay.paddingByTextHeight == EdgeInsets.zero &&
              _ranges.any(
                (other) =>
                    other.overlay.paddingByTextHeight != null &&
                    other.overlay.paddingByTextHeight != EdgeInsets.zero &&
                    other.start.compareTo(range.end) < 0 &&
                    other.end.compareTo(range.start) > 0,
              ))
        range.overlay.typographyFingerprint,
  ]);

  /// 按作者 run 与选区边界切分；后出现的覆盖按属性覆盖前者。
  ///
  /// 新合成区间不代表行内元素，禁止重复绘制作者块级背景与边框。
  List<StyledRun> resolve({
    required String? blockCfi,
    TextCfiMap? textCfis,
    required String text,
    required ComputedStyle style,
    required List<StyledRun> runs,
  }) {
    final block = blockCfi == null ? null : EpubCfi.parse(blockCfi);
    if (block == null || text.isEmpty) return runs;
    final ranges = [
      for (final range in _ranges) ?range.inBlock(block, text.length, textCfis),
    ];
    if (ranges.isEmpty) return runs;
    final boundaries = <int>{0, text.length};
    for (final range in ranges) {
      boundaries
        ..add(range.start)
        ..add(range.end);
    }
    for (final run in runs) {
      boundaries
        ..add(run.start.clamp(0, text.length))
        ..add(run.end.clamp(0, text.length));
    }
    final ordered = boundaries.toList()..sort();
    return [
      for (var index = 0; index < ordered.length - 1; index++)
        ?_resolveRun((ordered[index], ordered[index + 1]), style, runs, ranges),
    ];
  }

  StyledRun? _resolveRun(
    (int, int) interval,
    ComputedStyle style,
    List<StyledRun> runs,
    List<_LocalOverlayRange> ranges,
  ) {
    final (start, end) = interval;
    final author = runs
        .where((run) => run.start <= start && run.end >= end)
        .lastOrNull;
    final overlays = [
      for (final range in ranges)
        if (range.start <= start && range.end >= end) range.overlay,
    ];
    if (author == null && overlays.isEmpty) return null;
    final merged = _mergeStyle(author?.style ?? style, overlays);
    final padding = _paddingAt(merged, ranges, interval);
    return StyledRun(
      start: start,
      end: end,
      style: merged,
      baselineShift: author?.baselineShift ?? 0,
      syntheticFontFallback: author?.syntheticFontFallback ?? true,
      inlineLeadingInset:
          (start == author?.start ? _authorInset(author, true) : 0) +
          padding.leading,
      inlineTrailingInset:
          (end == author?.end ? _authorInset(author, false) : 0) +
          padding.trailing,
      inlinePadding: padding.insets,
    );
  }

  double _authorInset(StyledRun? run, bool leading) {
    if (run == null) return 0;
    if (run.syntheticFontFallback) {
      return leading
          ? run.inlineLeadingInset ?? 0
          : run.inlineTrailingInset ?? 0;
    }
    return leading ? run.leadingInset : run.trailingInset;
  }

  ({EdgeInsets insets, double leading, double trailing}) _paddingAt(
    ComputedStyle style,
    List<_LocalOverlayRange> ranges,
    (int, int) interval,
  ) {
    final (start, end) = interval;
    final padded = ranges
        .where(
          (range) =>
              range.start <= start &&
              range.end >= end &&
              (range.overlay.paddingByTextHeight != null ||
                  range.overlay.paddingLogicalPixels != null),
        )
        .lastOrNull;
    final padding =
        !typography ||
            style.isRtl ||
            style.writingMode != CssWritingMode.horizontalTb
        ? EdgeInsets.zero
        : padded?.overlay.paddingLogicalPixels ??
              _paddingFor(style, padded?.overlay.paddingByTextHeight);
    return (
      insets: padding,
      leading: start == padded?.start ? padding.left : 0,
      trailing: end == padded?.end ? padding.right : 0,
    );
  }

  EdgeInsets _paddingFor(ComputedStyle style, EdgeInsets? relative) {
    if (!typography ||
        style.isRtl ||
        style.writingMode != CssWritingMode.horizontalTb) {
      return EdgeInsets.zero;
    }
    if (relative == null || relative == EdgeInsets.zero) return EdgeInsets.zero;
    final painter = TextPainter(
      text: TextSpan(text: '国', style: TextLayoutEngine.textStyleFor(style)),
      textDirection: TextDirection.ltr,
    )..layout();
    final height = painter
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 1),
        )
        .single
        .toRect()
        .height;
    painter.dispose();
    return relative * height;
  }

  ComputedStyle _mergeStyle(
    ComputedStyle base,
    List<ReaderTextOverlay> overlays,
  ) {
    String? family;
    double? scale;
    int? weight;
    bool? italic;
    double? spacing;
    Color? color;
    for (final overlay in overlays) {
      if (typography) {
        family = overlay.normalizedFontFamily ?? family;
        if (overlay.normalizedFontSizeScale != 1) {
          scale = overlay.normalizedFontSizeScale;
        }
        weight = overlay.fontWeight?.clamp(100, 900) ?? weight;
        italic = overlay.italic ?? italic;
        if (overlay.normalizedLetterSpacingEm != 0) {
          spacing = overlay.normalizedLetterSpacingEm;
        }
      }
      if (colors) color = overlay.paintColor ?? color;
    }
    final fontSize = scale == null ? null : base.fontSize * scale;
    return base.withInlineTypography(
      fontFamily: family,
      fontSize: fontSize,
      fontWeight: weight,
      italic: italic,
      letterSpacing: spacing == null
          ? null
          : (fontSize ?? base.fontSize) * spacing,
      color: color,
    );
  }
}

class _TextOverlayRange {
  _TextOverlayRange(this.overlay, this.start, this.end);

  final ReaderTextOverlay overlay;
  final EpubCfi start;
  final EpubCfi end;

  static _TextOverlayRange? parse(ReaderTextOverlay overlay) {
    final start = EpubCfi.parse(overlay.startCfi);
    final end = EpubCfi.parse(overlay.endCfi);
    if (start == null ||
        end == null ||
        start.isRange ||
        end.isRange ||
        start.compareTo(end) >= 0) {
      return null;
    }
    return _TextOverlayRange(overlay, start, end);
  }

  _LocalOverlayRange? inBlock(EpubCfi block, int length, TextCfiMap? textCfis) {
    final mapped = (textCfis ?? TextCfiMap.linear(block, length)).rangeFor(
      start.serialize(),
      end.serialize(),
    );
    return mapped == null
        ? null
        : _LocalOverlayRange(overlay, mapped.$1, mapped.$2);
  }
}

class _LocalOverlayRange {
  _LocalOverlayRange(this.overlay, this.start, this.end);

  final ReaderTextOverlay overlay;
  final int start;
  final int end;
}
