import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _font = 'Ahem';
const _size = Size(200, 100);

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': _font,
});

PageBlock _block(String text) => PageBlock(
  layout: TextLayoutEngine.layout(text: text, style: _style(), maxWidth: 180),
  style: _style(),
);

Future<ByteData> _render(void Function(Canvas canvas) paint) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paint(canvas);
  final image = await recorder.endRecording().toImage(
    _size.width.round(),
    _size.height.round(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

Future<ByteData> _renderPage(PageContent page) =>
    _render((canvas) => PagePainter().paint(canvas, page, pageSize: _size));

Future<ByteData> _renderReference(PageContent page) => _render((canvas) {
  canvas.drawRect(
    Rect.fromLTWH(0, 0, _size.width, _size.height),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  var y = page.topPadding;
  for (final slice in page.slices) {
    final style = slice.block.style!;
    final textStyle = TextLayoutEngine.textStyleFor(style);
    if (slice.startLine == 0) {
      y += slice.block.spaceBefore;
    }
    for (var i = slice.startLine; i < slice.endLine; i++) {
      final line = slice.block.layout.lines[i];
      final text = slice.block.layout.text.substring(line.start, line.end);
      final painter = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(0, y));
      y += line.height;
    }
    if (slice.endLine == slice.block.layout.lineCount) {
      y += slice.block.spaceAfter;
    }
  }
});

int _diff(ByteData a, ByteData b) {
  var count = 0;
  for (var i = 0; i < a.lengthInBytes; i += 4) {
    if (a.getUint32(i) != b.getUint32(i)) {
      count += 1;
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('按页绘制与 TextPainter 直接绘制逐像素一致', () async {
    final page = Paginator(pageHeight: 48)
        .measureChapter(blocks: [_block('a\nb')])
        .pages
        .single;
    final actual = await _renderPage(page);
    final expected = await _renderReference(page);
    expect(_diff(actual, expected), 0);
  });

  test('跨页切片按页内连续坐标绘制', () async {
    final result = Paginator(pageHeight: 48)
        .measureChapter(blocks: [_block('a\nb\nc')]);
    final actual = await _renderPage(result.pages[0]);
    final expected = await _renderReference(result.pages[0]);
    expect(_diff(actual, expected), 0);
    expect(result.pages[0].slices.single.endLine, 2);
  });

  test('背景色生效且空页只画背景', () async {
    final page = PageContent(
      spineIndex: 0,
      pageIndex: 0,
      slices: const <PageBlockSlice>[],
      usedHeight: 0,
      pageHeight: 48,
      topPadding: 0,
    );
    final bytes = await _render(
      (canvas) =>
          const PagePainter(background: Color(0xFFFF0000))
              .paint(canvas, page, pageSize: _size),
    );
    expect(bytes.getUint8(0), 255);
    expect(bytes.getUint8(1), 0);
    expect(bytes.getUint8(2), 0);
    expect(bytes.getUint8(3), 255);
  });

  test('段前/段后间距影响绘制位置', () async {
    final page = Paginator(pageHeight: 100)
        .measureChapter(
          blocks: [
            PageBlock(
              layout: TextLayoutEngine.layout(
                text: 'a',
                style: _style(),
                maxWidth: 180,
              ),
              style: _style(),
              spaceBefore: 10,
              spaceAfter: 5,
            ),
          ],
        )
        .pages
        .single;
    final actual = await _renderPage(page);
    final expected = await _renderReference(page);
    expect(_diff(actual, expected), 0);
    var firstNonWhiteRow = -1;
    for (var row = 0; row < _size.height && firstNonWhiteRow < 0; row++) {
      for (var x = 0; x < _size.width; x++) {
        final offset = (row * _size.width.round() + x) * 4;
        if (actual.getUint32(offset) != 0xFFFFFFFF) {
          firstNonWhiteRow = row;
          break;
        }
      }
    }
    expect(firstNonWhiteRow, greaterThanOrEqualTo(10));
  });

  test('白底页面第一个非白像素在文字位置', () async {
    final page = Paginator(pageHeight: 48)
        .measureChapter(blocks: [_block('a')])
        .pages
        .single;
    final bytes = await _renderPage(page);
    var firstNonWhiteRow = -1;
    for (var y = 0; y < _size.height && firstNonWhiteRow < 0; y++) {
      for (var x = 0; x < _size.width; x++) {
        final offset = (y * _size.width.round() + x) * 4;
        if (bytes.getUint32(offset) != 0xFFFFFFFF) {
          firstNonWhiteRow = y;
          break;
        }
      }
    }
    expect(firstNonWhiteRow, greaterThanOrEqualTo(0));
    expect(firstNonWhiteRow, lessThan(24));
  });
}
