import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/paint/paragraph_cache.dart';

import 'support/css_chapter_book.dart';

const _pageSize = Size(300, 140);
const _scale = 3;
const _blue = Color(0xff304598);
const _authorRule =
    '.hr1 { margin: 1.5em 1em; height: 1px; border: none; '
    'border-top: 1px dashed #304598; }';

Future<PageContent> _page({
  String body = '<hr class="hr1"/>',
  String css = _authorRule,
  double fontSize = 17,
}) async {
  final source = await openCssChapter(
    body: body,
    css: 'body { margin: 0; font-size: ${fontSize}px; } $css',
    contentWidth: _pageSize.width,
    contentHeight: _pageSize.height,
  );
  return (await source.loadChapter(0)).single;
}

Future<ByteData> _paint(PageContent page, ParagraphCache? cache) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(_scale.toDouble());
  canvas.drawRect(
    Offset.zero & _pageSize,
    Paint()..color = const Color(0xffffffff),
  );
  PagePainter(paragraphCache: cache).paint(canvas, page, pageSize: _pageSize);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (_pageSize.width * _scale).round(),
    (_pageSize.height * _scale).round(),
  );
  picture.dispose();
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return pixels!;
}

List<int> _inkXs(ByteData pixels, Color color) {
  final width = (_pageSize.width * _scale).round();
  final argb = color.toARGB32();
  final rgba = ((argb & 0xffffff) << 8) | (argb >> 24);
  var row = -1;
  var maxInk = 0;
  for (var y = 0; y < _pageSize.height * _scale; y++) {
    var ink = 0;
    for (var x = 0; x < width; x++) {
      if (pixels.getUint32((y * width + x) * 4) == rgba) ink++;
    }
    if (ink > maxInk) {
      maxInk = ink;
      row = y;
    }
  }
  expect(row, greaterThanOrEqualTo(0), reason: '作者指定颜色的分隔线必须实际绘制');
  return [
    for (var x = 0; x < width; x++)
      if (pixels.getUint32((row * width + x) * 4) == rgba) x,
  ];
}

({List<int> runs, List<int> gaps, int left, int right}) _pattern(
  ByteData pixels,
  Color color,
) {
  final xs = _inkXs(pixels, color);
  final runs = <int>[];
  final gaps = <int>[];
  var start = xs.first;
  for (var i = 1; i < xs.length; i++) {
    if (xs[i] == xs[i - 1] + 1) continue;
    runs.add(xs[i - 1] - start + 1);
    gaps.add(xs[i] - xs[i - 1] - 1);
    start = xs[i];
  }
  runs.add(xs.last - start + 1);
  return (runs: runs, gaps: gaps, left: xs.first, right: xs.last + 1);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final size in [17.0, 22.0]) {
    test('${size}px：原书分隔线保留蓝色虚线、尺寸和边距', () async {
      final page = await _page(fontSize: size);
      final block = page.slices.single.block;
      final style = block.style!;
      expect(style.borders.top.style, CssBorderStyle.dashed);
      expect(style.borders.top.color, _blue);
      expect(style.borders.top.width, 1);
      expect(style.borders.bottom.width, 0);
      expect(style.margin.top, size * 1.5);
      expect(style.margin.left, size);
      expect(style.margin.right, size);
      expect(block.height, 1);
      expect(block.layout.maxWidth, _pageSize.width - 2 * size);
      final pixels = await _paint(page, null);
      final pattern = _pattern(pixels, _blue);
      expect(pattern.runs.length, greaterThan(20));
      expect(pattern.runs.first, 3 * _scale);
      expect(pattern.gaps.first, 2 * _scale);
      expect(pattern.left, (size * _scale).round());
      expect(pattern.right, lessThanOrEqualTo((300 - size) * _scale));
      final cache = ParagraphCache();
      addTearDown(cache.dispose);
      for (var pass = 0; pass < 2; pass++) {
        expect(
          (await _paint(page, cache)).buffer.asUint8List(),
          orderedEquals(pixels.buffer.asUint8List()),
        );
      }
    });
  }

  for (final (lineStyle, color) in [
    ('solid', const Color(0xff008000)),
    ('dotted', const Color(0xffcc0000)),
  ]) {
    test('作者 $lineStyle 分隔线不被统一替换成默认实线', () async {
      final page = await _page(
        css:
            'hr { margin: 10px; height: 2px; border: none; '
            'border-bottom: 2px $lineStyle '
            '#${color.toARGB32().toRadixString(16).substring(2)}; }',
      );
      final block = page.slices.single.block;
      expect(block.style!.borders.top.width, 0);
      expect(block.style!.borders.bottom.color, color);
      expect(block.style!.borders.bottom.width, 2);
      final pattern = _pattern(await _paint(page, null), color);
      expect(pattern.runs.length, lineStyle == 'solid' ? 1 : greaterThan(20));
    });
  }

  test('后代、内联与 important 正常参与分隔线层叠', () async {
    final page = await _page(
      body:
          '<div class="panel"><hr style="border-top: 4px solid green"/></div>',
      css:
          '.panel hr { margin: 10px; height: 1px; border: none; '
          'border-top: 2px dotted #cc0000 !important; }',
    );
    final border = page.slices.single.block.style!.borders.top;
    expect(border.style, CssBorderStyle.dotted);
    expect(border.width, 2);
    expect(border.color, const Color(0xffcc0000));
    expect(
      _pattern(await _paint(page, null), border.color).runs.length,
      greaterThan(20),
    );
  });

  test('border:none 不再被补回实线', () async {
    final page = await _page(css: 'hr { border: none; height: 1px; }');
    expect(page.slices.single.block.style!.borders.hasBorder, isFalse);
    expect((await _paint(page, null)).buffer.asUint8List(), everyElement(255));
  });

  test('自动高度分隔线只有边框占高，不引入正文行高', () async {
    final page = await _page(
      css:
          'hr { margin: 10px; height: auto; border: none; '
          'border-top: 1px dashed #304598; }',
    );
    final block = page.slices.single.block;
    expect(block.height, 0);
    expect(block.topInset, 1);
    expect(block.bottomInset, 0);
    expect(
      _pattern(await _paint(page, null), _blue).runs.length,
      greaterThan(20),
    );
  });

  test('display:none 分隔线不绘制也不占位', () async {
    final page = await _page(
      body: '<hr class="hr1"/><p>正文</p>',
      css: '$_authorRule hr { display: none; } p { margin: 0; }',
    );
    expect(page.slices, hasLength(1));
    expect(page.slices.single.block.layout.text, '正文');
    expect(page.slices.single.leadingExtent, 0);
  });

  test('无作者样式时保留既有灰色实线和默认段距', () async {
    final page = await _page(body: '<hr/>', css: '');
    final block = page.slices.single.block;
    final border = block.style!.borders.bottom;
    expect(border.style, CssBorderStyle.solid);
    expect(border.width, 1);
    expect(border.color, const Color(0xffb0b0b0));
    expect(block.height, 1);
    expect(block.spaceBefore, 8.5);
    expect(block.spaceAfter, 8.5);
    expect(_pattern(await _paint(page, null), border.color).runs, hasLength(1));
  });
}
