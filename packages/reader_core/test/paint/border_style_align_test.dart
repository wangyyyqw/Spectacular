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

/// 边框线型的浏览器对齐回归。
///
/// 浏览器基准来自 tool/css_parity（Chromium，dpr=4，300px 宽顶边）实测：
/// - dashed：1～2px 线宽为 3×宽 / 2×宽，3～8px 为 2×宽 / 宽
/// - dotted：方点 = 线宽、gap = 线宽（1～8px）
const _pageSize = Size(320, 80);
const _serif = 'BorderAlignSerif';

Future<void> _loadFont() async {
  final bytes = await File(
    '../../test_fonts/SourceHanSerifSC-Regular.otf',
  ).readAsBytes();
  await (FontLoader(
    _serif,
  )..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)))).load();
}

ComputedStyle _style(String borderTop) => ComputedStyle(<String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': _serif,
  'border-top': borderTop,
});

Future<ByteData> _render(String borderTop) async {
  final style = _style(borderTop);
  final layout = TextLayoutEngine.layout(
    text: '边框线型',
    style: style,
    maxWidth: _pageSize.width,
  );
  final page = Paginator(pageHeight: 60).measureChapter(
    blocks: [
      PageBlock.styled(
        layout: layout,
        style: style,
        containingWidth: _pageSize.width,
      ),
    ],
  ).pages.single;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(
      Rect.fromLTWH(0, 0, _pageSize.width, _pageSize.height),
      Paint()..color = const Color(0xFFFFFFFF),
    );
  const PagePainter().paint(canvas, page, pageSize: _pageSize);
  final image = await recorder.endRecording().toImage(
    _pageSize.width.toInt(),
    _pageSize.height.toInt(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

bool _ink(ByteData bytes, int x, int y) =>
    bytes.getUint32((y * _pageSize.width.toInt() + x) * 4) != 0xFFFFFFFF;

/// 边框线所在的行（该行墨迹最多）。
int _borderRow(ByteData bytes) {
  var bestRow = -1;
  var best = 0;
  for (var y = 0; y < _pageSize.height.toInt(); y++) {
    var count = 0;
    for (var x = 0; x < _pageSize.width.toInt(); x++) {
      if (_ink(bytes, x, y)) count++;
    }
    if (count > best) {
      best = count;
      bestRow = y;
    }
  }
  return bestRow;
}

({List<int> runs, List<int> gaps}) _pattern(ByteData bytes) {
  final y = _borderRow(bytes);
  final runs = <int>[];
  final gaps = <int>[];
  var start = -1;
  var previous = -1;
  for (var x = 0; x < _pageSize.width.toInt(); x++) {
    if (!_ink(bytes, x, y)) continue;
    if (start < 0) {
      start = x;
    } else if (x - previous > 1) {
      runs.add(previous - start + 1);
      gaps.add(x - previous - 1);
      start = x;
    }
    previous = x;
  }
  if (start >= 0) {
    runs.add(previous - start + 1);
  }
  return (runs: runs, gaps: gaps);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFont);

  test('1px dashed：段长 3 / 间隔 2（浏览器实测 3/2）', () async {
    final pattern = _pattern(await _render('1px dashed #000000'));
    expect(pattern.runs.length, greaterThan(3));
    expect(pattern.runs.first, 3);
    expect(pattern.gaps.first, 2);
  });

  test('4px dashed：段长 8 / 间隔 4（浏览器实测 8/4）', () async {
    final pattern = _pattern(await _render('4px dashed #000000'));
    expect(pattern.runs.length, greaterThan(3));
    expect(pattern.runs.first, closeTo(8, 1.0));
    expect(pattern.gaps.first, closeTo(4, 1.0));
  });

  test('1px dotted：方点 1 / 间隔 1（浏览器实测 1/1）', () async {
    final pattern = _pattern(await _render('1px dotted #000000'));
    expect(pattern.runs.length, greaterThan(3));
    expect(pattern.runs.first, closeTo(1, 1.0));
    expect(pattern.gaps.first, closeTo(1, 1.0));
  });

  test('4px dotted：方点 4 / 间隔 4（浏览器实测 4/4）', () async {
    final pattern = _pattern(await _render('4px dotted #000000'));
    expect(pattern.runs.length, greaterThan(3));
    expect(pattern.runs.first, closeTo(4, 1.0));
    expect(pattern.gaps.first, closeTo(4, 1.0));
  });

  test('实线边框仍是一整段（线型改动不影响 solid）', () async {
    final pattern = _pattern(await _render('4px solid #000000'));
    expect(pattern.runs, hasLength(1));
  });
}
