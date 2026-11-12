import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';

import 'support/css_chapter_book.dart';

const _css = '''
html, body { margin: 0; font: 20px/1 Ahem; }
body {
  width: 100%; min-height: 100vh; box-sizing: border-box;
  display: flex; flex-direction: column;
  justify-content: flex-start; align-items: center;
  padding-top: 25%; background: blue;
}
.none { display: none; }
.card {
  width: 90%; max-width: 500px; box-sizing: border-box;
  padding: 20px 5px 10px; border: 1px solid red;
  background: #00ff00; color: transparent; text-align: center;
}
.subtitle { font-size: 1em; margin-bottom: 20px; }
.note { font-size: .7em; margin-bottom: 0; }
''';
const _body = '''
<h1 class="none">信息</h1>
<div class="card">
  <div class="subtitle">AAA</div>
  <div class="subtitle">BBB</div>
  <div class="subtitle">CCC</div>
  <div class="subtitle">DDD</div>
  <div class="note">EEE</div>
</div>
''';

Future<ByteData> _paint(PageContent page, Size size) async {
  final recorder = ui.PictureRecorder();
  PagePainter().paint(
    Canvas(recorder),
    page,
    pageSize: size,
    pageInsets: EdgeInsets.zero,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

int _pixel(ByteData data, Size size, int x, int y) =>
    data.getUint32((y * size.width.toInt() + x) * 4);

Future<void> _expectCardPosition(Size size, double cardWidth) async {
  final source = await openCssChapter(
    body: _body,
    css: _css,
    contentWidth: size.width,
    contentHeight: size.height,
  );
  addTearDown(source.close);
  final page = (await source.loadChapter(0)).single;
  final first = page.slices.firstWhere(
    (slice) => slice.block.layout.text == 'AAA',
  );
  final card = first.block.containers.single.container;
  final left = (size.width - cardWidth) / 2;
  final top = size.width * .25;
  expect(card.width, cardWidth, reason: '90% 和 max-width 约束边框盒宽');
  expect(card.left, left, reason: '纵向 Flex 将完整卡片横向居中');
  expect(first.block.style!.margin.left, left + 6);
  final data = await _paint(page, size);
  final center = size.width ~/ 2;
  expect(_pixel(data, size, center, top.toInt() - 1), 0x0000ffff);
  expect(_pixel(data, size, center, top.toInt()), 0xff0000ff);
  expect(_pixel(data, size, center, top.toInt() + 1), 0x00ff00ff);
  expect(_pixel(data, size, left.toInt(), top.toInt() + 10), 0xff0000ff);
  expect(
    _pixel(data, size, (left + cardWidth - 1).toInt(), top.toInt() + 10),
    0xff0000ff,
    reason: '左右边框随内容投影一起移动',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '纵向 Flex 的 90% 宽制作卡片横向居中，并按包含块宽预留 25% 顶部内边距',
    () => _expectCardPosition(const Size(360, 600), 324),
  );
  test(
    '宽页面按 max-width 限制卡片宽，顶部百分比仍取页面宽度',
    () => _expectCardPosition(const Size(720, 1000), 500),
  );
  test('根 Flex 容器已保留时，顶部内边距只占位一次', () async {
    const size = Size(360, 600);
    final source = await openCssChapter(
      body: '<span style="display:block;background:red;color:transparent">AAA</span>',
      css: _css,
      contentWidth: size.width,
      contentHeight: size.height,
    );
    addTearDown(source.close);
    final page = (await source.loadChapter(0)).single;
    final data = await _paint(page, size);
    expect(_pixel(data, size, 180, 89), 0x0000ffff);
    expect(_pixel(data, size, 180, 90), 0xff0000ff);
  });
}
