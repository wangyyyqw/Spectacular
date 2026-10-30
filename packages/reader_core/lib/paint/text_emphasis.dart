import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

import '../css/computed_style.dart';
import '../layout/text_layout.dart';

/// 横排着重号：使用正文半字号的标准字形，同一块内复用排版结果。
class HorizontalTextEmphasis {
  /// [color] 是阅读器覆盖后的着重号颜色。
  factory HorizontalTextEmphasis(ComputedStyle style, Color color) {
    final mark = _painter(style, color);
    final probe = TextPainter(
      text: TextSpan(
        text: '国Hg',
        style: TextLayoutEngine.textStyleFor(style)
            .copyWith(height: kTextHeightNone),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final font = probe.computeLineMetrics().first;
    final metrics = mark.computeLineMetrics().first;
    final size = TextLayoutEngine.textStyleFor(style).fontSize!;
    // 上侧注音区从 em 盒顶开始；下侧从字体下降部之后开始，避免压住下伸笔画。
    final emAscent = font.ascent - (font.ascent + font.descent - size) / 2;
    final offset = style.textEmphasisPosition.isOver
        ? (-emAscent - metrics.descent).floorToDouble()
        : (font.descent + metrics.ascent).ceilToDouble();
    probe.dispose();
    return HorizontalTextEmphasis._(style, mark, offset - metrics.baseline);
  }

  HorizontalTextEmphasis._(this._style, this._mark, this._top);

  final ComputedStyle _style;
  final TextPainter _mark;
  final double _top;

  // CSS Text Decoration 3 §3.1：标点例外包含 NFKD 对应的兼容字符。
  static final _punctuationExceptions = '#%‰‱٪؉؊&⁊@§¶⁋⁓〽＃％＆＠﹟﹠﹪﹫'.runes.toSet();
  static final _unmarked = RegExp(r'^[\p{P}\p{Cc}\p{Cf}\p{Cn}]', unicode: true);
  static final _separator = RegExp(r'^\p{Z}', unicode: true);
  static final _combinedSpace = RegExp(r'^\p{Z}\p{M}+$', unicode: true);

  static bool _receivesMark(String cluster) {
    if (_punctuationExceptions.contains(cluster.runes.first)) return true;
    if (_unmarked.hasMatch(cluster)) return false;
    return !_separator.hasMatch(cluster) || _combinedSpace.hasMatch(cluster);
  }

  static TextPainter _painter(ComputedStyle style, Color color) {
    final base = TextLayoutEngine.textStyleFor(style);
    final glyph = switch (style.textEmphasisStyle) {
      CssTextEmphasisStyle.dot => '\u2022',
      CssTextEmphasisStyle.openDot => '\u25e6',
      CssTextEmphasisStyle.circle => '\u25cf',
      CssTextEmphasisStyle.openCircle => '\u25cb',
      CssTextEmphasisStyle.sesame => '\ufe45',
      CssTextEmphasisStyle.openSesame => '\ufe46',
      CssTextEmphasisStyle.none => '',
    };
    return TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(
          fontFamily: base.fontFamily,
          fontFamilyFallback: base.fontFamilyFallback,
          fontSize: base.fontSize! / 2,
          fontWeight: base.fontWeight,
          fontStyle: base.fontStyle,
          fontFeatures: [...?base.fontFeatures, const FontFeature('ruby')],
          fontVariations: base.fontVariations,
          height: 1,
          leadingDistribution: TextLeadingDistribution.even,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  /// 沿已排版的字素簇绘制，不拆开代理对、组合字符或 emoji 序列。
  void paint(Canvas canvas, TextPainter text, String line, Offset baseline) {
    var start = 0;
    for (final cluster in line.characters) {
      final end = start + cluster.length;
      if (_receivesMark(cluster)) {
        final boxes = text.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
        );
        if (boxes.isNotEmpty) {
          final center =
              (boxes.first.left + boxes.first.right - _style.letterSpacing) / 2;
          _mark.paint(
            canvas,
            Offset(baseline.dx + center - _mark.width / 2, baseline.dy + _top),
          );
        }
      }
      start = end;
    }
  }

  /// 释放块内共用的字形排版资源。
  void dispose() => _mark.dispose();
}
