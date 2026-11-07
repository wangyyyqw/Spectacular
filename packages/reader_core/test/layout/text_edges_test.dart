import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/text_edges.dart';
import 'package:reader_core/layout/text_layout_cache.dart';
import 'package:reader_core/paint/line_spans.dart';

const _text =
    '中文“标点”，与 Latin ffi AV 123、emoji 😀👍🏽混排，'
    '每行字体的上下沿保留真实原生几何。';

Future<void> _fonts() async {
  for (final (family, stem) in [
    ('edge_song', 'SourceHanSerifCN'),
    ('edge_hei', 'SourceHanSansSC'),
  ]) {
    final loader = FontLoader(family);
    for (final weight in ['Regular', 'Bold']) {
      loader.addFont(
        Future.value(
          ByteData.sublistView(
            File('../../apps/reader_mobile/assets/fonts/$stem-$weight.otf')
                .readAsBytesSync(),
          ),
        ),
      );
    }
    await loader.load();
  }
}

PageTextEdges _nativeEdges(
  TextLayoutResult layout,
  LineBox line,
  ComputedStyle style,
) {
  final painter = TextPainter(
    text: buildLineSpan(
      layout: layout,
      line: line,
      baseStyle: TextLayoutEngine.textStyleFor(style),
      punctCompression:
          style.textSpacingTrim == CssTextSpacingTrim.trimAdjacent,
      textAutospace: style.textAutospace == CssTextAutospace.normal,
    ),
    textDirection: layout.isRtl ? TextDirection.rtl : TextDirection.ltr,
    textHeightBehavior: const TextHeightBehavior(
      applyHeightToFirstAscent: false,
      applyHeightToLastDescent: false,
    ),
  )..layout();
  try {
    final ascent = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    final baseline = line.baseline - line.top;
    return PageTextEdges(
      top: math.max(0, baseline - ascent),
      bottom: math.max(0, line.height - baseline - (painter.height - ascent)),
    );
  } finally {
    painter.dispose();
  }
}

void _expectEdges(TextLayoutResult layout, ComputedStyle style) {
  // 从后向前查询，避免只有顺序分页才能保持字体与缓存正确。
  for (final line in layout.lines.reversed) {
    final expected = _nativeEdges(layout, line, style);
    final actual = textLineEdges(layout, line, style);
    expect(actual.top, closeTo(expected.top, 0.00001));
    expect(actual.bottom, closeTo(expected.bottom, 0.00001));
    expect(textLineEdges(layout, line, style), same(actual));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await _fonts();
    LineBreaker.preserveFractionalLineHeight = true;
  });

  test('混合字体、字号、标点和缩放的行留白等价于独立原生单行', () {
    for (final size in [17.0, 21.0, 22.0]) {
      for (final trim in [
        'trim-all',
        'trim-adjacent',
        'trim-both',
        'space-all',
      ]) {
        final style = ComputedStyle({
          'font-family': 'edge_song',
          'font-size': '${size}px',
          'line-height': '1.7',
          'text-align': 'justify',
          'text-spacing-trim': trim,
          'text-autospace': 'normal',
        });
        final mixed = style.withTypography(
          fontFamily: 'edge_hei',
          fontSize: 28,
        );
        for (final scale in [1.0, 1.25]) {
          final layout = TextLayoutEngine.layout(
            text: _text * 9,
            style: style,
            maxWidth: 244,
            textScaleFactor: scale,
            runs: [StyledRun(start: 5, end: 31, style: mixed)],
          );
          _expectEdges(layout, style);
        }
      }
    }
  });

  test('空行、硬换行、RTL 和上下标继续按原生单行计算', () {
    final style = ComputedStyle({
      'font-family': 'edge_song',
      'font-size': '22px',
      'line-height': '1.6',
      'direction': 'rtl',
    });
    final layout = TextLayoutEngine.layout(
      text: '''אבג العربية

$_text''',
      style: style,
      maxWidth: 300,
      runs: [StyledRun(start: 0, end: 2, style: style, baselineShift: -6)],
    );
    _expectEdges(layout, style);
  });

  test('只替换绘制 run 时复用行留白，不跨字体依赖共享缓存', () {
    final style = ComputedStyle({
      'font-family': 'edge_song',
      'font-size': '22px',
      'line-height': '1.7',
      'text-spacing-trim': 'trim-all',
    });
    final cache = TextLayoutCache();
    final first = cache.layout(
      text: _text * 4,
      style: style,
      maxWidth: 244,
      fontDependency: '宋体字库版本1',
    );
    final edges = textLineEdges(first, first.lines.first, style);
    final red = style.withInlineTypography(color: const Color(0xffff0000));
    final paintOnly = cache.layout(
      text: _text * 4,
      style: red,
      maxWidth: 244,
      fontDependency: '宋体字库版本1',
    );
    expect(textLineEdges(paintOnly, paintOnly.lines.first, red), same(edges));
    final revised = cache.layout(
      text: _text * 4,
      style: style,
      maxWidth: 244,
      fontDependency: '宋体字库版本2',
    );
    expect(revised, isNot(same(first)));
    expect(
      textLineEdges(revised, revised.lines.first, style),
      isNot(same(edges)),
    );
    _expectEdges(revised, style);
  });
}
