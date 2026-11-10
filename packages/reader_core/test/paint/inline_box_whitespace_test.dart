import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _height = 160;

PageContent _page(String text, double width) {
  final style = ComputedStyle(const {
    'font-family': 'Ahem',
    'font-size': '16px',
    'line-height': '1.5',
  });
  final layout = TextLayoutEngine.layout(
    text: text,
    style: style,
    maxWidth: width,
    inlineBoxes: [
      for (var offset = 0; offset < text.length; offset++)
        if (text.codeUnitAt(offset) == 0xfffc)
          InlineBoxSpec(
            offset: offset,
            width: 28,
            height: 20,
            marginLeft: 3,
            marginRight: 3,
            replacesPlaceholder: true,
            payload: ComputedStyle(const {'background-color': '#ff0000'}),
          ),
    ],
  );
  return Paginator(pageHeight: _height.toDouble())
      .measureChapter(
        blocks: [
          PageBlock.styled(
            layout: layout,
            style: style,
            containingWidth: width,
          ),
        ],
      )
      .pages
      .single;
}

Future<Uint8List> _paint(PageContent page, int width) async {
  final recorder = ui.PictureRecorder();
  PagePainter(background: const Color(0xffffffff)).paint(
    Canvas(recorder),
    page,
    pageSize: Size(width.toDouble(), _height.toDouble()),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, _height);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

int _redPixels(Uint8List bytes) {
  var red = 0;
  for (var offset = 0; offset < bytes.length; offset += 4) {
    if (bytes[offset] > 240 &&
        bytes[offset + 1] < 10 &&
        bytes[offset + 2] < 10) {
      red++;
    }
  }
  return red;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final width in [200, 90]) {
    test('行内图片间纯空白不触发 caret 断言，宽度 $width', () async {
      final page = _page('\uFFFC \uFFFC \uFFFC \uFFFC ', width.toDouble());
      final layout = page.slices.single.block.layout;
      expect(layout.lines.length, width == 200 ? 1 : 2);
      expect(layout.lines.expand((line) => line.inlineBoxes), hasLength(4));
      final pixels = await _paint(page, width);
      expect(_redPixels(pixels), 4 * 28 * 20, reason: '全部四个图片盒都必须绘制');
    });
  }

  test('图片后的空格和正文保持布局位置', () async {
    final page = _page('\uFFFC \uFFFC A', 180);
    final layout = page.slices.single.block.layout;
    final line = layout.lines.single;
    final pixels = await _paint(page, 180);
    expect(_redPixels(pixels), 2 * 28 * 20);
    // Ahem 的 A 是 16px 实心方块；图后两段空格也必须保留占宽。
    final expectedLeft = line.inlineBoxes.last.left + 28 + 3 + 16;
    final blackXs = <int>{};
    for (var y = 0; y < _height; y++) {
      for (var x = 0; x < 180; x++) {
        final offset = (y * 180 + x) * 4;
        if (pixels[offset] < 10 &&
            pixels[offset + 1] < 10 &&
            pixels[offset + 2] < 10) {
          blackXs.add(x);
        }
      }
    }
    expect(blackXs.reduce((a, b) => a < b ? a : b), expectedLeft.round());
    expect(blackXs, hasLength(16));
  });
}
