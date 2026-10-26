import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _pageSize = Size(200, 120);
const _pageColor = Color(0xFF000000);

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
  'color': '#ffffff',
  'background-color': '#ff0000',
  'margin': '20px',
});

PageContent _page({required bool bleed}) {
  final style = _style();
  final block = PageBlock.styled(
    layout: TextLayoutEngine.layout(
      text: '出血',
      style: style,
      maxWidth: _pageSize.width - 40,
    ),
    style: style,
    containingWidth: _pageSize.width,
    bleedLeft: bleed,
    bleedRight: bleed,
  );
  return Paginator(pageHeight: _pageSize.height)
      .measureChapter(blocks: <PageBlock>[block])
      .pages
      .single;
}

Future<ByteData> _render(PageContent page) async {
  final recorder = ui.PictureRecorder();
  PagePainter(background: _pageColor).paint(
    Canvas(recorder),
    page,
    pageSize: _pageSize,
  );
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

  test('duokan-bleed 让背景延伸到页面边缘（P9-22）', () async {
    final data = await _render(_page(bleed: true));
    // 取块内容带（纵向 margin 20px 之后）验证左右出血。
    expect(_pixel(data, 0, 30), const Color(0xFFFF0000), reason: '左缘应出血');
    expect(
      _pixel(data, _pageSize.width.toInt() - 1, 30),
      const Color(0xFFFF0000),
      reason: '右缘应出血',
    );
    // 出血只作用于声明的左右边；纵向 margin 带仍是页面底色。
    expect(_pixel(data, 100, 10), _pageColor, reason: '上 margin 带不画背景');
    expect(_pixel(data, 100, 110), _pageColor, reason: '下 margin 带不画背景');
  });

  test('没有出血时保留页边距', () async {
    final data = await _render(_page(bleed: false));
    expect(_pixel(data, 0, 30), _pageColor, reason: '左缘应为页面底色');
    expect(
      _pixel(data, _pageSize.width.toInt() - 1, 30),
      _pageColor,
      reason: '右缘应为页面底色',
    );
    expect(_pixel(data, 30, 30), const Color(0xFFFF0000), reason: '块内应着色');
  });
}
