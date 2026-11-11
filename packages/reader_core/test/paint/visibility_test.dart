import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _width = 200;
const _height = 120;

ComputedStyle _style(Map<String, String> overrides) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      ...overrides,
    });

TextLayoutResult _layout(String text, ComputedStyle style) =>
    TextLayoutEngine.layout(text: text, style: style, maxWidth: 180);

Future<ByteData> _render(String text, ComputedStyle style) async {
  final page = Paginator(pageHeight: _height.toDouble())
      .measureChapter(
        blocks: [PageBlock(layout: _layout(text, style), style: style)],
      )
      .pages
      .single;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const PagePainter().paint(canvas, page, pageSize: const Size(200, 120));
  final image = await recorder.endRecording().toImage(_width, _height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

int _inkCount(ByteData bytes) {
  var count = 0;
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    if (bytes.getUint32(i) != 0xFFFFFFFF) {
      count += 1;
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('visibility:hidden 不绘制文字与装饰，但布局尺寸不变', () async {
    final visibleStyle = _style(const {});
    final hiddenStyle = _style(const {
      'visibility': 'hidden',
      'background-color': '#FF0000',
      'border': '2px solid #000000',
    });

    final visibleLayout = _layout('aa\nbb', visibleStyle);
    final hiddenLayout = _layout(
      'aa\nbb',
      _style(const {'visibility': 'hidden'}),
    );
    expect(hiddenLayout.lineCount, visibleLayout.lineCount);
    expect(hiddenLayout.height, visibleLayout.height);
    for (var i = 0; i < visibleLayout.lineCount; i++) {
      expect(hiddenLayout.lines[i].top, visibleLayout.lines[i].top);
      expect(hiddenLayout.lines[i].height, visibleLayout.lines[i].height);
    }

    final visible = await _render('aa\nbb', visibleStyle);
    final hidden = await _render('aa\nbb', hiddenStyle);
    expect(_inkCount(visible), greaterThan(0));
    expect(_inkCount(hidden), 0, reason: 'hidden 不画文字/背景/边框');

    final visiblePage = Paginator(pageHeight: _height.toDouble())
        .measureChapter(
          blocks: [PageBlock(layout: visibleLayout, style: visibleStyle)],
        );
    final hiddenPage = Paginator(pageHeight: _height.toDouble()).measureChapter(
      blocks: [
        PageBlock(layout: _layout('aa\nbb', hiddenStyle), style: hiddenStyle),
      ],
    );
    expect(
      hiddenPage.pages.single.usedHeight,
      visiblePage.pages.single.usedHeight,
    );
  });

  test('visibility:collapse 按隐藏处理', () async {
    final bytes = await _render('aa', _style(const {'visibility': 'collapse'}));
    expect(_inkCount(bytes), 0);
  });
}
