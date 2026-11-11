import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _pageSize = Size(120, 60);

ComputedStyle _darkCardStyle() => ComputedStyle(const <String, String>{
  'font-size': '20px',
  'line-height': '1.5',
  'font-family': 'Ahem',
  // 书籍只声明深色底色，不声明文字色（默认黑字）。
  'background-color': '#0d131f',
});

Future<ByteData> _render() async {
  final style = _darkCardStyle();
  final block = PageBlock.styled(
    layout: TextLayoutEngine.layout(
      text: 'A',
      style: style,
      maxWidth: _pageSize.width,
    ),
    style: style,
    containingWidth: _pageSize.width,
  );
  final page = Paginator(pageHeight: _pageSize.height)
      .measureChapter(blocks: <PageBlock>[block])
      .pages
      .single;
  final recorder = ui.PictureRecorder();
  PagePainter(
    background: const Color(0xFFFFFFFF),
    textColor: const Color(0xFF1A1A1A),
  ).paint(Canvas(recorder), page, pageSize: _pageSize);
  final image = await recorder.endRecording().toImage(
    _pageSize.width.toInt(),
    _pageSize.height.toInt(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('深色卡片里的未声明颜色文字改用浅色（P9-23）', () async {
    final bytes = await _render();
    var lightPixels = 0;
    for (var i = 0; i < bytes.lengthInBytes; i += 4) {
      final r = bytes.getUint8(i);
      final g = bytes.getUint8(i + 1);
      final b = bytes.getUint8(i + 2);
      if (r > 180 && g > 180 && b > 180) {
        lightPixels += 1;
      }
    }
    expect(
      lightPixels,
      greaterThan(0),
      reason: '深色底上的文字应该画成浅色，否则看不见',
    );
  });
}
