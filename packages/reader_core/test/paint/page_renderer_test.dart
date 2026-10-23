import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _font = 'Ahem';
const _cjkFont = 'P203Justify';
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
      painter.paint(canvas, Offset(line.offsetX, y));
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

/// 找到第一条有墨迹的像素行；没有时返回 -1。
int _firstInkRow(ByteData bytes) {
  final width = _size.width.round();
  for (var y = 0; y < _size.height; y++) {
    for (var x = 0; x < width; x++) {
      if (bytes.getUint32((y * width + x) * 4) != 0xFFFFFFFF) {
        return y;
      }
    }
  }
  return -1;
}

/// 指定行第一个墨迹像素列；没有时返回 -1。
int _firstInkColumn(ByteData bytes, int row) {
  final width = _size.width.round();
  for (var x = 0; x < width; x++) {
    if (bytes.getUint32((row * width + x) * 4) != 0xFFFFFFFF) {
      return x;
    }
  }
  return -1;
}

/// 指定行最后一个墨迹像素列；没有时返回 -1。
int _lastInkColumn(ByteData bytes, int row) {
  final width = _size.width.round();
  for (var x = width - 1; x >= 0; x--) {
    if (bytes.getUint32((row * width + x) * 4) != 0xFFFFFFFF) {
      return x;
    }
  }
  return -1;
}

/// 最后一个有墨迹的像素行；没有时返回 -1。
int _lastInkRow(ByteData bytes) {
  final width = _size.width.round();
  for (var y = _size.height.round() - 1; y >= 0; y--) {
    for (var x = 0; x < width; x++) {
      if (bytes.getUint32((y * width + x) * 4) != 0xFFFFFFFF) {
        return y;
      }
    }
  }
  return -1;
}

/// 把一段文本排成一页并绘制。
Future<ByteData> _renderText(
  String text, {
  List<StyledRun> runs = const <StyledRun>[],
}) {
  final style = ComputedStyle(const <String, String>{
    'font-size': '16px',
    'line-height': '1.5',
    'font-family': _font,
  });
  final layout = TextLayoutEngine.layout(
    text: text,
    style: style,
    maxWidth: 180,
    runs: runs,
  );
  final page = Paginator(pageHeight: 100)
      .measureChapter(
        blocks: [PageBlock(layout: layout, style: style)],
      )
      .pages
      .single;
  return _renderPage(page);
}

/// 用给定对齐方式排一行 3 字（Ahem 16px，行宽 48）并返回绘制结果。
Future<ByteData> _renderAligned(String align) {
  final style = ComputedStyle(<String, String>{
    'font-size': '16px',
    'line-height': '1.5',
    'font-family': _font,
    'text-align': align,
  });
  final layout = TextLayoutEngine.layout(
    text: 'abc',
    style: style,
    maxWidth: 180,
  );
  final page = Paginator(pageHeight: 100)
      .measureChapter(
        blocks: [PageBlock(layout: layout, style: style)],
      )
      .pages
      .single;
  return _renderPage(page);
}

ComputedStyle _cjkStyle(String align) => ComputedStyle(<String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': _cjkFont,
  'text-align': align,
});

/// 9 个全角字、可用宽 100：首行 6 字（96），余量 4。
TextLayoutResult _cjkLayout(String align) => TextLayoutEngine.layout(
  text: '一二三四五六七八九',
  style: _cjkStyle(align),
  maxWidth: 100,
);

Future<ByteData> _renderCjkPage(String align) {
  final style = _cjkStyle(align);
  final page = Paginator(pageHeight: 100)
      .measureChapter(
        blocks: [PageBlock(layout: _cjkLayout(align), style: style)],
      )
      .pages
      .single;
  return _renderPage(page);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final file = File('../../test_fonts/SourceHanSerifSC-Regular.otf');
    if (!file.existsSync()) {
      return;
    }
    final bytes = ByteData.view(file.readAsBytesSync().buffer);
    final loader = FontLoader(_cjkFont)..addFont(Future<ByteData>.value(bytes));
    await loader.load();
  });

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

  test('首行缩进绘制在缩进位置', () async {
    final style = ComputedStyle(const <String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': _font,
      'text-indent': '32px',
    });
    final layout = TextLayoutEngine.layout(
      text: 'abcdefghijklmnop',
      style: style,
      maxWidth: 180,
    );
    final block = PageBlock(layout: layout, style: style);
    final page = Paginator(pageHeight: 100)
        .measureChapter(blocks: [block])
        .pages
        .single;
    expect(layout.lines.first.indent, 32);
    final actual = await _renderPage(page);
    final expected = await _renderReference(page);
    expect(_diff(actual, expected), 0);
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

  test('center 对齐绘制在内容区水平居中', () async {
    final bytes = await _renderAligned('center');
    final row = _firstInkRow(bytes);
    expect(row, greaterThanOrEqualTo(0));
    expect(_firstInkColumn(bytes, row), closeTo((180 - 48) / 2, 2));
  });

  test('right 对齐绘制贴内容区右边', () async {
    final bytes = await _renderAligned('right');
    final row = _firstInkRow(bytes);
    expect(_firstInkColumn(bytes, row), closeTo(180 - 48, 2));
  });

  test('justify 非末行拉伸到右缘、末行保持自然宽', () async {
    final layout = _cjkLayout('justify');
    expect(layout.lineCount, 2);
    expect(layout.lines.first.width, closeTo(96, 0.01));
    expect(layout.lines.first.justifyExtra, closeTo(4, 0.01));
    expect(layout.lines.last.justifyExtra, 0);

    final left = await _renderCjkPage('left');
    final justified = await _renderCjkPage('justify');
    final firstRow = _firstInkRow(justified);
    expect(firstRow, greaterThanOrEqualTo(0));
    // 拉伸后的行右缘比左对齐宽出余量 4px（字框取整允许 ±1px）。
    final grown =
        _lastInkColumn(justified, firstRow) - _lastInkColumn(left, firstRow);
    expect(grown, closeTo(4, 1));
    // 末行不拉伸，与左对齐完全一致。
    expect(
      _lastInkColumn(justified, firstRow + 24),
      _lastInkColumn(left, firstRow + 24),
    );
  });

  test('行内大字号 run 绘制出更高的墨迹', () async {
    final plain = await _renderText('ab');
    final mixed = await _renderText(
      'ab',
      runs: [
        StyledRun(
          start: 1,
          end: 2,
          style: ComputedStyle(const <String, String>{
            'font-size': '32px',
            'line-height': '1.5',
            'font-family': _font,
          }),
        ),
      ],
    );
    expect(_lastInkRow(mixed), greaterThan(_lastInkRow(plain)));
  });
}
