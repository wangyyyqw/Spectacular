import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/page_renderer.dart';

/// 块背景不得画进纵向 margin 带（10-background / 26-background-gradient 的
/// 视觉差全部落在相邻块之间的空白带上）。
const _pageSize = Size(200, 120);
const _pageColor = Color(0xFF000000);
const _blockColor = Color(0xFFFF0000);
const _font = 'MarginBandSerif';

Future<void> _loadFont() async {
  final bytes = await File(
    '../../test_fonts/SourceHanSerifSC-Regular.otf',
  ).readAsBytes();
  await (FontLoader(
    _font,
  )..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)))).load();
}

ComputedStyle _style(String background) => ComputedStyle(<String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': _font,
  'color': '#ffffff',
  'background-color': background,
  'margin': '8px 0',
});

PageBlock _block(String text, {String background = '#ff0000'}) {
  final style = _style(background);
  return PageBlock.styled(
    layout: TextLayoutEngine.layout(
      text: text,
      style: style,
      maxWidth: _pageSize.width,
    ),
    style: style,
    containingWidth: _pageSize.width,
  );
}

Future<ByteData> _render(List<PageBlock> blocks) async {
  final page = Paginator(
    pageHeight: _pageSize.height,
  ).measureChapter(blocks: blocks).pages.single;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  PagePainter(
    background: _pageColor,
  ).paint(canvas, page, pageSize: _pageSize);
  final image = await recorder.endRecording().toImage(
    _pageSize.width.toInt(),
    _pageSize.height.toInt(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

Color _pixel(ByteData bytes, int x, int y) {
  final offset = (y * _pageSize.width.toInt() + x) * 4;
  return Color.fromARGB(
    bytes.getUint8(offset + 3),
    bytes.getUint8(offset),
    bytes.getUint8(offset + 1),
    bytes.getUint8(offset + 2),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFont);

  test('单块：上下 margin 带不画背景，只有内容带着色', () async {
    final data = await _render([_block('块一')]);
    // margin 8 + 行高 24 → 背景应只覆盖 y=8..32。
    for (final y in <int>[0, 2, 6, 34, 38]) {
      expect(
        _pixel(data, 100, y),
        _pageColor,
        reason: 'y=$y 在 margin 带内，应为页面底色',
      );
    }
    expect(_pixel(data, 100, 10), _blockColor, reason: '内容带应着色');
    expect(_pixel(data, 100, 30), _blockColor, reason: '内容带应着色');
  });

  test('相邻两块：块间空白带（相邻 margin 折叠后 8px）不带色', () async {
    final data = await _render([_block('块一'), _block('块二')]);
    // 分页把相邻的 8+8 margin 折叠成 8：
    // 块一 0..32（8 margin + 24 内容）、空白带 32..40、块二 40..72。
    for (final y in <int>[0, 4, 33, 36, 38]) {
      expect(
        _pixel(data, 100, y),
        _pageColor,
        reason: 'y=$y 在 margin 带内，应为页面底色',
      );
    }
    expect(_pixel(data, 100, 20), _blockColor, reason: '块一内容带应着色');
    expect(_pixel(data, 100, 50), _blockColor, reason: '块二内容带应着色');
    expect(_pixel(data, 100, 74), _pageColor, reason: '末块下 margin 不带色');
  });

  test('相邻两块都是渐变背景时，空白带同样不带色', () async {
    final style = ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': _font,
      'color': '#ffffff',
      'margin': '8px 0',
      'background':
          'linear-gradient(90deg, #ff0000, #ff0000)',
    });
    PageBlock gradientBlock(String text) => PageBlock.styled(
      layout: TextLayoutEngine.layout(
        text: text,
        style: style,
        maxWidth: _pageSize.width,
      ),
      style: style,
      containingWidth: _pageSize.width,
    );
    final data = await _render([gradientBlock('块一'), gradientBlock('块二')]);
    for (final y in <int>[2, 4, 34, 36, 38, 74]) {
      expect(
        _pixel(data, 100, y),
        _pageColor,
        reason: 'y=$y 在 margin 带内，渐变也不应画出块外',
      );
    }
    expect(_pixel(data, 100, 20), _blockColor, reason: '渐变内容带应着色');
    expect(_pixel(data, 100, 50), _blockColor, reason: '第二块渐变内容应着色');
  });
}
