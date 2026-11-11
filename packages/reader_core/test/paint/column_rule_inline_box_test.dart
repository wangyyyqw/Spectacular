import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/line_spans.dart';
import 'package:reader_core/paint/page_renderer.dart';

/// W16：`column-rule` 绘制与行内盒 placements 绘制。
const _width = 300;
const _height = 120;

TextLayoutResult _syntheticLayout({
  String text = '',
  double lineHeight = 60,
  double lineWidth = 260,
  List<InlineBoxPlacement> inlineBoxes = const <InlineBoxPlacement>[],
}) => TextLayoutResult(
  text: text,
  lines: [
    LineBox(
      start: 0,
      end: text.length,
      top: 0,
      height: lineHeight,
      baseline: lineHeight * 0.7,
      width: lineWidth,
      inlineBoxes: inlineBoxes,
    ),
  ],
  width: lineWidth,
  height: lineHeight,
  maxWidth: lineWidth,
  runs: const <StyledRun>[],
);

ComputedStyle _columnStyle(String rule) => ComputedStyle(<String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
  'color': '#000000',
  'column-count': '2',
  'column-gap': '20px',
  'column-rule': rule,
});

Future<ByteData> _render(PageBlock block) async {
  final page = Paginator(pageHeight: _height.toDouble())
      .measureChapter(blocks: [block])
      .pages
      .single;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  PagePainter(background: const Color(0xFFFFFFFF)).paint(
    canvas,
    page,
    pageSize: Size(_width.toDouble(), _height.toDouble()),
  );
  final image = await recorder.endRecording().toImage(_width, _height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

int _r(ByteData b, int x, int y) => b.getUint8((y * _width + x) * 4);
int _g(ByteData b, int x, int y) => b.getUint8((y * _width + x) * 4 + 1);
int _b(ByteData b, int x, int y) => b.getUint8((y * _width + x) * 4 + 2);

bool _isBlank(ByteData b, int x, int y) =>
    _r(b, x, y) > 245 && _g(b, x, y) > 245 && _b(b, x, y) > 245;

bool _isRed(ByteData b, int x, int y) =>
    _r(b, x, y) > 180 && _g(b, x, y) < 80 && _b(b, x, y) < 80;

ByteData _bytes(List<int> values) => Uint8List.fromList(values).buffer.asByteData();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------- column-rule ----------------

  test('column-rule 2px solid：两列之间画竖线（x = 列宽 + gap/2）', () async {
    final style = _columnStyle('2px solid #ff0000');
    final block = PageBlock(
      layout: _syntheticLayout(),
      style: style,
      multicol: const MulticolGeometry(
        count: 2,
        columnWidth: 120,
        gap: 20,
      ),
    );
    final data = await _render(block);
    // 列带：x 0..260；分隔线在 x = 120 + 10 = 130。
    expect(_isRed(data, 130, 30), isTrue, reason: '列间中线应有竖线');
    expect(_isRed(data, 129, 30), isTrue, reason: '2px 线覆盖中线两侧');
    expect(_isBlank(data, 100, 30), isTrue, reason: '列内不应有着色');
    expect(_isBlank(data, 160, 30), isTrue, reason: '第二列内不应有着色');
    expect(_isBlank(data, 130, 100), isTrue, reason: '竖线高度只到列带底');
  });

  test('column-rule: none（无规则）：列间不画线', () async {
    final style = ComputedStyle(<String, String>{
      'font-size': '16px',
      'font-family': 'Ahem',
      'column-count': '2',
      'column-gap': '20px',
    });
    final block = PageBlock(
      layout: _syntheticLayout(),
      style: style,
      multicol: const MulticolGeometry(
        count: 2,
        columnWidth: 120,
        gap: 20,
      ),
    );
    final data = await _render(block);
    for (var y = 0; y < 60; y += 6) {
      expect(
        _isBlank(data, 130, y),
        isTrue,
        reason: 'column-rule: none 时 y=$y 不应有竖线',
      );
    }
  });

  test('column-rule 1px dotted：竖线呈点阵（有间隙），不同于 solid', () async {
    Future<ByteData> render(String rule) => _render(
      PageBlock(
        layout: _syntheticLayout(),
        style: _columnStyle(rule),
        multicol: const MulticolGeometry(
          count: 2,
          columnWidth: 120,
          gap: 20,
        ),
      ),
    );
    final dotted = await render('1px dotted #ff0000');
    final solid = await render('1px solid #ff0000');
    int inkCount(ByteData bytes) {
      var count = 0;
      for (var y = 0; y < 60; y++) {
        if (!_isBlank(bytes, 130, y)) count++;
      }
      return count;
    }

    expect(inkCount(solid), greaterThan(50), reason: 'solid 竖线连续');
    expect(inkCount(dotted), lessThan(40), reason: '点线有明显间隙');
    expect(inkCount(dotted), greaterThan(5), reason: '点线仍应可见');
  });

  // ---------------- 行内盒 placements ----------------

  test('行内盒 placements：按 left/ascent 定位并画背景、边框与 payload 文本', () async {
    final payloadStyle = ComputedStyle(<String, String>{
      'font-size': '16px',
      'font-family': 'Ahem',
      'color': '#000000',
      'background-color': '#ff0000',
      'border': '2px solid #00ff00',
    });
    final placement = InlineBoxPlacement(
      offset: 0,
      left: 20,
      width: 60,
      height: 40,
      ascent: 32,
      descent: 8,
      spec: InlineBoxSpec(
        offset: 0,
        width: 60,
        height: 40,
        payload: payloadStyle,
      ),
    );
    final block = PageBlock(
      layout: _syntheticLayout(text: 'ab', inlineBoxes: [placement]),
      style: ComputedStyle(<String, String>{
        'font-size': '16px',
        'font-family': 'Ahem',
      }),
    );
    final data = await _render(block);
    // 行顶 0、基线 42（60×0.7）→ 盒顶 = 42 − 32 = 10，盒 20..80 × 10..50。
    expect(_isRed(data, 50, 30), isTrue, reason: '盒内应铺 payload 背景色');
    expect(_isRed(data, 24, 30), isTrue, reason: '左侧边框以内仍是背景');
    expect(_isBlank(data, 10, 30), isTrue, reason: '盒外不应着色');
    expect(_isBlank(data, 100, 30), isTrue, reason: '盒右侧之外不应着色');
    // 边框：盒缘 2px 绿线。
    expect(_g(data, 20, 30) > 150 && _r(data, 20, 30) < 100, isTrue,
        reason: '左缘应有绿色边框');
    // payload 字符串未提供时盒内只有背景（本用例 payload 是样式）。
  });

  test('行内盒 payload 为 String：盒内居中绘制文本', () async {
    // 盒放在行文本（Ahem 'ab' 占 0..32）右侧，盒内墨迹只可能来自 payload。
    final placement = InlineBoxPlacement(
      offset: 0,
      left: 100,
      width: 60,
      height: 40,
      ascent: 32,
      descent: 8,
      spec: const InlineBoxSpec(
        offset: 0,
        width: 60,
        height: 40,
        payload: 'ab',
      ),
    );
    final block = PageBlock(
      layout: _syntheticLayout(text: 'ab', inlineBoxes: [placement]),
      style: ComputedStyle(<String, String>{
        'font-size': '16px',
        'font-family': 'Ahem',
        'background-color': '#ffff00',
      }),
    );
    final data = await _render(block);
    // 盒 100..160 × 10..50，底色黄；payload 'ab' 黑色居中。
    expect(_r(data, 150, 45) > 200 && _g(data, 150, 45) > 200, isTrue,
        reason: '盒内应为 payload 背景（黄）');
    var dark = 0;
    for (var y = 10; y < 50; y++) {
      for (var x = 100; x < 160; x++) {
        if (_r(data, x, y) < 80) dark++;
      }
    }
    expect(dark, greaterThan(20), reason: '盒内应有 payload 文本墨迹');
  });

  test('无 placements 时保持旧口径（run 样式行内盒，不重复绘制）', () async {
    final block = PageBlock(
      layout: _syntheticLayout(),
      style: ComputedStyle(<String, String>{
        'font-size': '16px',
        'font-family': 'Ahem',
      }),
    );
    final data = await _render(block);
    expect(_isBlank(data, 50, 30), isTrue, reason: '无 placements 不应凭空画盒');
    // 参考：字节缓冲区最小可用性（避免未使用告警）。
    expect(_bytes(<int>[0, 0, 0, 0]).lengthInBytes, 4);
  });

  // ---------------- font-variant: small-caps ----------------

  test('small-caps：textStyleFor 带 smcp，绘制 span 原样保留', () {
    final style = ComputedStyle(<String, String>{
      'font-size': '16px',
      'font-family': 'Ahem',
      'font-variant': 'small-caps',
    });
    final textStyle = TextLayoutEngine.textStyleFor(style);
    expect(
      textStyle.fontFeatures?.map((feature) => feature.feature),
      contains('smcp'),
      reason: '布局与绘制共用的 TextStyle 必须带 smcp，否则测宽与实际绘制不一致',
    );
    final layout = TextLayoutEngine.layout(
      text: 'Abc',
      style: style,
      maxWidth: 300,
    );
    final span = buildLineSpan(
      layout: layout,
      line: layout.lines.first,
      baseStyle: textStyle,
    );
    bool hasSmallCaps(InlineSpan span) {
      if (span is! TextSpan) {
        return false;
      }
      final features = span.style?.fontFeatures;
      if (features != null &&
          features.any((feature) => feature.feature == 'smcp')) {
        return true;
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        if (hasSmallCaps(child)) {
          return true;
        }
      }
      return false;
    }

    expect(
      hasSmallCaps(span),
      isTrue,
      reason: '绘制 span 必须保留 smcp（逐字符 copyWith 不能丢特性）',
    );
  });

  test('small-caps 渲染冒烟：无 smcp 的字体按原样出墨（不崩）', () async {
    final block = PageBlock(
      layout: TextLayoutEngine.layout(
        text: 'Ab',
        style: ComputedStyle(<String, String>{
          'font-size': '16px',
          'font-family': 'Ahem',
          'font-variant': 'small-caps',
        }),
        maxWidth: 260,
      ),
      style: ComputedStyle(<String, String>{
        'font-size': '16px',
        'font-family': 'Ahem',
        'font-variant': 'small-caps',
      }),
    );
    final data = await _render(block);
    var ink = 0;
    for (var y = 0; y < _height; y++) {
      for (var x = 0; x < _width; x++) {
        if (!_isBlank(data, x, y)) ink++;
      }
    }
    expect(ink, greaterThan(20), reason: 'Ahem 无 smcp 特性时按原样出墨');
  });

  test('行内盒 payload=PageBlock：画盒背景/边框 + 内容盒内文字', () async {
    final boxStyle = ComputedStyle(<String, String>{
      'font-size': '16px',
      'font-family': 'Ahem',
      'color': '#000000',
      'background-color': '#ff0000',
      'border': '2px solid #00ff00',
      'padding': '4px',
    });
    final payload = PageBlock(
      layout: TextLayoutEngine.layout(
        text: 'ab',
        style: boxStyle,
        maxWidth: 52,
      ),
      style: boxStyle,
    );
    final placement = InlineBoxPlacement(
      offset: 0,
      left: 100,
      width: 60,
      height: 40,
      ascent: 32,
      descent: 8,
      spec: InlineBoxSpec(
        offset: 0,
        width: 60,
        height: 40,
        payload: payload,
      ),
    );
    final block = PageBlock(
      layout: _syntheticLayout(text: 'x', inlineBoxes: [placement]),
      style: ComputedStyle(<String, String>{
        'font-size': '16px',
        'font-family': 'Ahem',
      }),
    );
    final data = await _render(block);
    // 盒 100..160 × 10..50；边框 2px、padding 4 ⇒ 内容盒 106..154 × 16..44。
    expect(_isRed(data, 150, 40), isTrue, reason: '盒内应铺 payload 背景色');
    expect(
      _g(data, 101, 30) > 150 && _r(data, 101, 30) < 100,
      isTrue,
      reason: '盒左缘应有 payload 绿色边框',
    );
    var dark = 0;
    for (var y = 16; y < 44; y++) {
      for (var x = 106; x < 154; x++) {
        if (_r(data, x, y) < 80) dark++;
      }
    }
    expect(dark, greaterThan(20), reason: '内容盒内应有 payload 文字墨迹');
  });

  test('固定高的行内盒：payload.clipsContent 时内容按内容盒裁剪', () async {
    final boxStyle = ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.25',
      'font-family': 'Ahem',
      'color': '#000000',
      'background-color': '#ffeecc',
      'overflow': 'hidden',
    });
    // 内容 2 行（40px 高），但声明高 20 → clipsContent 为真。
    final payloadLayout = TextLayoutEngine.layout(
      text: 'abcd',
      style: boxStyle,
      maxWidth: 32,
    );
    expect(payloadLayout.lineCount, 2);
    final payload = PageBlock(
      layout: payloadLayout,
      style: boxStyle,
      declaredContentHeight: 20,
    );
    expect(payload.clipsContent, isTrue, reason: '声明高 20 < 内容高 40');
    final placement = InlineBoxPlacement(
      offset: 0,
      left: 60,
      width: 32,
      height: 20,
      ascent: 16,
      descent: 4,
      spec: InlineBoxSpec(
        offset: 0,
        width: 32,
        height: 20,
        payload: payload,
      ),
    );
    final block = PageBlock(
      layout: _syntheticLayout(text: 'x', inlineBoxes: [placement]),
      style: ComputedStyle(<String, String>{
        'font-size': '16px',
        'font-family': 'Ahem',
      }),
    );
    final data = await _render(block);
    // 行顶 0、基线 42 → 盒顶 42−16 = 26，盒 26..46；内容盒与盒同高（无 padding/border）。
    var inkInside = 0;
    var inkBelow = 0;
    for (var y = 0; y < _height; y++) {
      for (var x = 60; x < 92; x++) {
        if (_isBlank(data, x, y)) continue;
        // 背景（#ffeecc）不算墨迹：只统计深色文字。
        if (_r(data, x, y) < 120) {
          if (y < 46) {
            inkInside++;
          } else {
            inkBelow++;
          }
        }
      }
    }
    expect(inkInside, greaterThan(10), reason: '第一行内容应画出');
    expect(inkBelow, 0, reason: '超出声明高的第二行应被裁掉');
  });
}
