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

const _pageSize = Size(240, 100);
const _serif = 'DecoSerif3';

Future<void> _loadFont() async {
  final bytes = await File('../../test_fonts/SourceHanSerifSC-Regular.otf')
      .readAsBytes();
  await (FontLoader(
    _serif,
  )..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)))).load();
}

Future<ByteData> _renderPages(
  String text,
  ComputedStyle style, {
  required int pageIndex,
}) async {
  final layout = TextLayoutEngine.layout(
    text: text,
    style: style,
    maxWidth: 200,
  );
  final pages = Paginator(pageHeight: 100)
      .measureChapter(
        blocks: [
          PageBlock.styled(layout: layout, style: style, containingWidth: 200),
        ],
      )
      .pages;
  expect(pages.length, greaterThan(pageIndex), reason: '块应跨页');
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(
      const Rect.fromLTWH(0, 0, 240, 100),
      Paint()..color = const Color(0xFFFFFFFF),
    );
  const PagePainter().paint(canvas, pages[pageIndex], pageSize: _pageSize);
  final image = await recorder.endRecording().toImage(240, 100);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

bool _isInk(ByteData bytes, int x, int y) =>
    bytes.getUint32((y * 240 + x) * 4) != 0xFFFFFFFF;

bool _columnContinuous(ByteData bytes, int x, int yTop, int yBottom) {
  for (var y = yTop; y <= yBottom; y++) {
    if (!_isInk(bytes, x, y)) {
      return false;
    }
  }
  return true;
}

bool _hasLongHorizontalRun(ByteData bytes, int y, {int minRun = 50}) {
  var run = 0;
  for (var x = 0; x < 240; x++) {
    if (_isInk(bytes, x, y)) {
      run += 1;
      if (run >= minRun) {
        return true;
      }
    } else {
      run = 0;
    }
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFont);

  const text = '第一行内容\n第二行内容\n第三行内容\n第四行内容\n第五行内容\n第六行内容';

  test('跨页块边框：切片边界不画水平边，左右边框全长续绘', () async {
    final style = ComputedStyle(<String, String>{
      'font-size': '20px',
      'line-height': '1.6',
      'font-family': _serif,
      'color': '#000000',
      'border': '3px solid #000000',
    });
    final page0 = await _renderPages(text, style, pageIndex: 0);
    final page1 = await _renderPages(text, style, pageIndex: 1);

    expect(_columnContinuous(page0, 1, 5, 95), isTrue,
        reason: '首页左边框连续');
    expect(_columnContinuous(page1, 1, 5, 95), isTrue,
        reason: '次页左边框续绘');

    for (var y = 0; y < 6; y++) {
      expect(_hasLongHorizontalRun(page1, y), isFalse,
          reason: '切片边界 y=$y 不应有水平边框线');
    }
  });

  test('跨页块背景：切片各自铺背景色，不越界', () async {
    final style = ComputedStyle(<String, String>{
      'font-size': '20px',
      'line-height': '1.6',
      'font-family': _serif,
      'color': '#000000',
      'background-color': '#EEEEEE',
    });
    final page1 = await _renderPages(text, style, pageIndex: 1);
    final center = page1.getUint32((50 * 240 + 120) * 4);
    // rawRgba 实测通道序：R 在高字节（见 P2-37 通道辅助注释）。
    final r = (center >> 24) & 0xFF;
    final g = (center >> 16) & 0xFF;
    expect(r, 0xEE, reason: '背景色铺满切片');
    expect(g, 0xEE);
  });
}
