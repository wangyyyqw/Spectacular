import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/paint/paragraph_cache.dart';

const _size = Size(300, 320);
const _red = Color(0xFFCC0000);
const _blue = Color(0xFF0066CC);

Future<void> _loadFont() async {
  final bytes = await File(
    '../../apps/reader_mobile/assets/fonts/SourceHanSerifCN-Regular.otf',
  ).readAsBytes();
  await (FontLoader(
    'InlineEmphasisFont',
  )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
}

ComputedStyle _style([Map<String, String> properties = const {}]) =>
    ComputedStyle({
      'font-family': 'InlineEmphasisFont',
      'font-size': '24px',
      'line-height': '1.8',
      'color': '#000000',
      ...properties,
    }, hasExplicitTextColor: properties.containsKey('color'));

List<PageContent> _pages(
  TextLayoutResult layout,
  ComputedStyle style, {
  double height = 320,
}) => Paginator(pageHeight: height, topPadding: 32)
    .measureChapter(
      blocks: [
        PageBlock.styled(layout: layout, style: style, containingWidth: 300),
      ],
    )
    .pages;

Future<ByteData> _render(
  PageContent page, {
  Color? theme,
  ParagraphCache? cache,
}) async {
  final recorder = ui.PictureRecorder();
  PagePainter(
    textColor: theme,
    paragraphCache: cache,
  ).paint(Canvas(recorder), page, pageSize: _size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(300, 320);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return data!;
}

bool _isColor(ByteData pixels, int x, int y, Color color) {
  final offset = (y * 300 + x) * 4;
  return pixels.getUint8(offset + 3) > 200 &&
      (pixels.getUint8(offset) - color.r * 255).abs() < 30 &&
      (pixels.getUint8(offset + 1) - color.g * 255).abs() < 30 &&
      (pixels.getUint8(offset + 2) - color.b * 255).abs() < 30;
}

List<(int, int)> _bands(Iterable<int> positions) {
  final bands = <(int, int)>[];
  for (final position in positions) {
    if (bands.isEmpty || position > bands.last.$2 + 1) {
      bands.add((position, position));
    } else {
      bands[bands.length - 1] = (bands.last.$1, position);
    }
  }
  return bands;
}

List<Rect> _marks(ByteData pixels, Color color) {
  final rows = _bands([
    for (var y = 0; y < 320; y++)
      if ([for (var x = 0; x < 300; x++) _isColor(pixels, x, y, color)]
          .any((pixel) => pixel))
        y,
  ]);
  return [
    for (final (top, bottom) in rows)
      for (final (left, right) in _bands([
        for (var x = 0; x < 300; x++)
          if ([
            for (var y = top; y <= bottom; y++) _isColor(pixels, x, y, color),
          ].any((pixel) => pixel))
            x,
      ]))
        Rect.fromLTRB(left.toDouble(), top.toDouble(), right + 1, bottom + 1),
  ];
}

void main() {
  setUpAll(_loadFont);

  test('块级无标记时，仅行内指定区间绘制着重号', () async {
    final base = _style();
    final layout = TextLayoutEngine.layout(
      text: '前中文后',
      style: base,
      maxWidth: 300,
      runs: [
        StyledRun(
          start: 1,
          end: 3,
          style: _style({'text-emphasis': 'circle #cc0000'}),
        ),
      ],
    );
    final marks = _marks(await _render(_pages(layout, base).single), _red);
    expect(marks, hasLength(2));
    expect(marks[0].center.dx, closeTo(36, 1));
    expect(marks[1].center.dx, closeTo(60, 1));
  });

  test('行内 none 取消继承的着重号，区间外保留且不重复绘制', () async {
    final base = _style({'text-emphasis': 'circle #cc0000'});
    final layout = TextLayoutEngine.layout(
      text: '前中文后',
      style: base,
      maxWidth: 300,
      runs: [StyledRun(start: 1, end: 3, style: _style())],
    );
    final marks = _marks(await _render(_pages(layout, base).single), _red);
    expect(marks, hasLength(2));
    expect(marks[0].center.dx, closeTo(12, 1));
    expect(marks[1].center.dx, closeTo(84, 1));
  });

  test('行内颜色和下方位置覆盖块级上方标记', () async {
    final base = _style({'text-emphasis': 'circle #cc0000'});
    final layout = TextLayoutEngine.layout(
      text: '前中文后',
      style: base,
      maxWidth: 300,
      runs: [
        StyledRun(
          start: 1,
          end: 3,
          style: _style({
            'text-emphasis': 'circle #0066cc',
            'text-emphasis-position': 'under',
          }),
        ),
      ],
    );
    final pixels = await _render(_pages(layout, base).single);
    final red = _marks(pixels, _red);
    final blue = _marks(pixels, _blue);
    expect(red, hasLength(2));
    expect(blue, hasLength(2));
    expect(blue.first.top, greaterThan(red.first.bottom + 24));
  });

  test('标记采用行内字号，不沿用块字号', () async {
    final base = _style();
    final layout = TextLayoutEngine.layout(
      text: '中文',
      style: base,
      maxWidth: 300,
      runs: [
        StyledRun(
          start: 0,
          end: 1,
          style: _style({'text-emphasis': 'circle #cc0000'}),
        ),
        StyledRun(
          start: 1,
          end: 2,
          style: _style({
            'font-size': '36px',
            'text-emphasis': 'circle #0066cc',
          }),
        ),
      ],
    );
    final pixels = await _render(_pages(layout, base).single);
    final red = _marks(pixels, _red).single;
    final blue = _marks(pixels, _blue).single;
    expect(blue.width, greaterThan(red.width * 1.3));
    expect(blue.top, lessThan(red.top));
  });

  test('行内 currentcolor 使用作者正文色而非块主题色', () async {
    final base = _style();
    final layout = TextLayoutEngine.layout(
      text: '中文',
      style: base,
      maxWidth: 300,
      runs: [
        StyledRun(
          start: 0,
          end: 2,
          style: _style({
            'color': '#008000',
            'text-emphasis': 'circle currentcolor',
          }),
        ),
      ],
    );
    final pixels = await _render(_pages(layout, base).single, theme: _blue);
    final green = _marks(pixels, const Color(0xFF008000));
    expect(green.where((mark) => mark.bottom < 32 + 12), hasLength(2));
    expect(_marks(pixels, _blue), isEmpty);
  });

  test('多行块的着重号只推进一次行高', () async {
    final base = _style({'text-emphasis': 'circle #cc0000'});
    final layout = TextLayoutEngine.layout(
      text: '中文中文中文',
      style: base,
      maxWidth: 72,
    );
    expect(layout.lineCount, 2);
    final marks = _marks(await _render(_pages(layout, base).single), _red);
    expect(marks, hasLength(6));
    expect(marks[3].top - marks[0].top, closeTo(layout.lines.first.height, 1));
  });

  test('跨行跨页区间只标记交集，后续页从正确偏移继续', () async {
    const text = '中文中文中文中文中文中文中文';
    final base = _style();
    final layout = TextLayoutEngine.layout(
      text: text,
      style: base,
      maxWidth: 96,
      runs: [
        StyledRun(
          start: 2,
          end: text.length - 1,
          style: _style({'text-emphasis': 'circle #cc0000'}),
        ),
      ],
    );
    final pages = _pages(layout, base, height: 125);
    expect(pages.length, greaterThan(1));
    for (final page in pages) {
      final slice = page.slices.single;
      final start = layout.lines[slice.startLine].start;
      final end = layout.lines[slice.endLine - 1].end;
      final count = math.max(
        0,
        math.min(end, text.length - 1) - math.max(start, 2),
      );
      expect(_marks(await _render(page), _red), hasLength(count));
    }
  });

  test('样式边界落在组合字符内时，字素簇采用起始字符样式且只标记一次', () async {
    final base = _style();
    final layout = TextLayoutEngine.layout(
      text: '中e\u0301文',
      style: base,
      maxWidth: 300,
      runs: [
        StyledRun(
          start: 1,
          end: 2,
          style: _style({'text-emphasis': 'circle #cc0000'}),
        ),
        StyledRun(
          start: 2,
          end: 3,
          style: _style({'text-emphasis': 'circle #0066cc'}),
        ),
      ],
    );
    final pixels = await _render(_pages(layout, base).single);
    expect(_marks(pixels, _red), hasLength(1));
    expect(_marks(pixels, _blue), isEmpty);
  });

  test('行内盒后面的标记跟随正文占宽位移，不落在盒内', () async {
    final base = _style();
    final layout = TextLayoutEngine.layout(
      text: '中文',
      style: base,
      maxWidth: 300,
      runs: [
        StyledRun(
          start: 0,
          end: 2,
          style: _style({'text-emphasis': 'circle #cc0000'}),
        ),
      ],
      inlineBoxes: [InlineBoxSpec(offset: 1, width: 44, height: 18)],
    );
    final marks = _marks(await _render(_pages(layout, base).single), _red);
    expect(marks, hasLength(2));
    expect(marks[1].center.dx - marks[0].center.dx, closeTo(24 + 44, 1));
  });

  test('继承着重号不在行内图片占位符上生成标记', () async {
    final base = _style({'text-emphasis': 'circle #cc0000'});
    final layout = TextLayoutEngine.layout(
      text: '中\uFFFC文',
      style: base,
      maxWidth: 300,
    );
    final marks = _marks(await _render(_pages(layout, base).single), _red);
    expect(marks, hasLength(2));
  });

  test('行内基线位移同步移动标记', () async {
    final base = _style();
    final marked = _style({'text-emphasis': 'circle #cc0000'});
    Future<double> top(double shift) async {
      final layout = TextLayoutEngine.layout(
        text: '中文',
        style: base,
        maxWidth: 300,
        runs: [
          StyledRun(start: 0, end: 2, style: marked, baselineShift: shift),
        ],
      );
      return _marks(await _render(_pages(layout, base).single), _red).first.top;
    }

    expect(await top(-8) - await top(0), closeTo(-8, 1));
  });

  test('紧行高的行内标记不被块裁剪，缓存与非缓存绘制一致', () async {
    final base = _style({'line-height': '1'});
    final layout = TextLayoutEngine.layout(
      text: '中文',
      style: base,
      maxWidth: 300,
      runs: [
        StyledRun(
          start: 0,
          end: 2,
          style: _style({
            'line-height': '1',
            'text-emphasis': 'circle #cc0000',
          }),
        ),
      ],
    );
    final page = _pages(layout, base).single;
    final plain = await _render(page);
    expect(_marks(plain, _red), hasLength(2));
    final cache = ParagraphCache();
    try {
      final cached = await _render(page, cache: cache);
      final repeated = await _render(page, cache: cache);
      expect(cached.buffer.asUint8List(), plain.buffer.asUint8List());
      expect(repeated.buffer.asUint8List(), plain.buffer.asUint8List());
    } finally {
      cache.dispose();
    }
  });
}
