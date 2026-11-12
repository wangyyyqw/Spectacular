import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';

import 'support/css_chapter_book.dart';

const _pageSize = Size(360, 600);
const _rootCss =
    'html, body {height:100%;margin:0;padding:0;} '
    'body {display:flex;justify-content:center;align-items:center;}';

Future<ByteData> _paint(
  PageContent page, {
  EdgeInsets insets = EdgeInsets.zero,
}) async {
  final recorder = ui.PictureRecorder();
  PagePainter().paint(
    Canvas(recorder),
    page,
    pageSize: _pageSize,
    pageInsets: insets,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(360, 600);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

int _pixel(ByteData data, int x, int y) => data.getUint32((y * 360 + x) * 4);

Rect _greenBounds(ByteData data) {
  var left = 360, top = 600, right = -1, bottom = -1;
  for (var y = 0; y < 600; y++) {
    for (var x = 0; x < 360; x++) {
      if (_pixel(data, x, y) != 0x008000ff) continue;
      if (x < left) left = x;
      if (y < top) top = y;
      if (x > right) right = x;
      if (y > bottom) bottom = y;
    }
  }
  expect(right, greaterThanOrEqualTo(left), reason: '标题必须有实际墨迹');
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    right + 1.0,
    bottom + 1.0,
  );
}

void _expectSameBackground(ByteData data, int firstX, int secondX, int y) {
  // 渐变栅格化会产生一个色阶的抖动，重复铺底造成的明显色差仍须失败。
  for (var channel = 0; channel < 4; channel++) {
    expect(
      data.getUint8((y * 360 + firstX) * 4 + channel),
      closeTo(data.getUint8((y * 360 + secondX) * 4 + channel), 1),
      reason: '页边距内外同一高度的背景必须连续，不能叠加正文区背景',
    );
  }
}

Future<void> _expectVerticalTitle(String mode) async {
  final source = await openCssChapter(
    body: '<h1 class="heading-1">ABC</h1>',
    css:
        '$_rootCss .heading-1 {font:bold 48px/1 Ahem;color:#008000;'
        'writing-mode:$mode;text-orientation:upright;'
        'text-align:center;margin:0 auto;}',
    contentWidth: 360,
    contentHeight: 600,
  );
  addTearDown(source.close);
  final page = (await source.loadChapter(0)).single;
  final data = await _paint(page);
  final bounds = _greenBounds(data);
  expect(bounds.width, closeTo(48, 1));
  expect(bounds.height, closeTo(144, 1), reason: '三个字不能被横排裁成尾片');
  expect(bounds.center.dx, closeTo(180, 1));
  expect(bounds.center.dy, closeTo(300, 1));
  for (var index = 0; index < 3; index++) {
    expect(
      _pixel(data, 180, 252 + index * 48),
      0x008000ff,
      reason: '第 ${index + 1} 个字完整落在自己的纵向字格',
    );
  }
}

Future<void> _expectRootBackground() async {
  const insets = EdgeInsets.fromLTRB(12, 30, 12, 30);
  final source = await openCssChapter(
    body: '<div class="card"><h1>ABC</h1></div>',
    css:
        '$_rootCss body {background:linear-gradient(red,blue);} '
        '.card {display:flex;justify-content:center;align-items:center;'
        'width:120px;height:100px;background:#00ff00;} '
        'h1 {margin:0;font:16px/1 Ahem;color:transparent;}',
    contentWidth: 336,
    contentHeight: 540,
  );
  addTearDown(source.close);
  final page = (await source.loadChapter(0)).single;
  final data = await _paint(page, insets: insets);
  for (final y in [31, 80, 520, 568]) {
    _expectSameBackground(data, 20, 5, y);
    _expectSameBackground(data, 340, 355, y);
  }
  expect(
    _pixel(data, 180, 300),
    0x00ff00ff,
    reason: '只有页面根的背景交给整页绘制，普通 Flex 背景仍保留',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final mode in ['vertical-lr', 'vertical-rl']) {
    test('全页 Flex 的 $mode 标题完整竖排居中', () => _expectVerticalTitle(mode));
  }
  test('根 Flex 背景只铺整页一次，嵌套 Flex 卡片仍保留自身背景', _expectRootBackground);
}
