import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

/// `border-radius` 百分比（CSS Backgrounds §5.1）：相对盒子自身宽/高解算，
/// 方盒上的 50% 是正圆——书籍里的圆形头像/徽章靠它。

ComputedStyle _style(Map<String, String> overrides) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1',
      'font-family': 'Ahem',
      'margin': '0',
      'padding': '0',
      'width': '100px',
      'height': '100px',
      'background-color': '#ff0000',
      ...overrides,
    });

Future<ByteData> _render(Map<String, String> overrides) async {
  final style = _style(overrides);
  final block = PageBlock.styled(
    // 空文本：避免字形墨迹干扰圆角像素断言。
    layout: TextLayoutEngine.layout(text: '', style: style, maxWidth: 100),
    style: style,
    containingWidth: 100,
  );
  final page = Paginator(pageHeight: 200)
      .measureChapter(blocks: [block])
      .pages
      .first;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  PagePainter(background: const Color(0xFFFFFFFF)).paint(
    canvas,
    page,
    pageSize: const Size(200, 200),
  );
  final image = await recorder.endRecording().toImage(200, 200);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

int _r(ByteData b, int x, int y) => b.getUint8((y * 200 + x) * 4);
int _g(ByteData b, int x, int y) => b.getUint8((y * 200 + x) * 4 + 1);
bool _red(ByteData b, int x, int y) => _r(b, x, y) > 200 && _g(b, x, y) < 60;
bool _blank(ByteData b, int x, int y) =>
    _r(b, x, y) > 245 && _g(b, x, y) > 245;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('border-radius: 50% 的方盒四角透明（正圆）', () async {
    final data = await _render(const {'border-radius': '50%'});
    // 盒子左上角像素位于圆外 → 白底；盒中心仍是红色。
    expect(_blank(data, 1, 1), isTrue, reason: '圆角外应透明');
    expect(_red(data, 50, 50), isTrue, reason: '中心仍是背景色');
    // 上边中点应在圆内（被背景覆盖）。
    expect(_red(data, 50, 1), isTrue);
  });

  test('像素圆角保持原行为（12px）', () async {
    final data = await _render(const {'border-radius': '12px'});
    expect(_blank(data, 1, 1), isTrue, reason: '12px 圆角也裁掉角点');
    expect(_red(data, 50, 50), isTrue);
    expect(_red(data, 50, 2), isTrue, reason: '上边中部不受圆角影响');
  });

  test('无圆角时四角填满', () async {
    final data = await _render(const {});
    expect(_red(data, 1, 1), isTrue);
  });
}
