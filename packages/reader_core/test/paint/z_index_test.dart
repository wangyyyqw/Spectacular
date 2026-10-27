import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

/// `z-index` 叠放（CSS 2.1 §9.9）：定位块按 z-index 升序绘制，值大的在上。
const _width = 200;
const _height = 200;

ComputedStyle _style(Map<String, String> overrides) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1',
      'font-family': 'Ahem',
      'color': '#ffffff',
      ...overrides,
    });

PageBlock _absolute(String color, String zIndex, double left, double top) {
  final style = _style(<String, String>{
    'position': 'absolute',
    'left': '${left}px',
    'top': '${top}px',
    'width': '120px',
    'height': '120px',
    'background-color': color,
    'z-index': zIndex,
  });
  return PageBlock.styled(
    layout: TextLayoutEngine.layout(text: 'aa', style: style, maxWidth: 120),
    style: style,
    containingWidth: 120,
    // 章节源按 `style.position` 决定；布局单测里要显式标绝对定位。
    absolute: true,
  );
}

Future<ByteData> _render(List<PageBlock> blocks) async {
  final page = Paginator(pageHeight: _height.toDouble(), pageWidth: 200)
      .measureChapter(blocks: blocks)
      .pages
      .first;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  PagePainter(background: const Color(0xFFFFFFFF)).paint(
    canvas,
    page,
    pageSize: const Size(200, 200),
  );
  final image = await recorder.endRecording().toImage(_width, _height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

int _r(ByteData b, int x, int y) => b.getUint8((y * _width + x) * 4);
int _g(ByteData b, int x, int y) => b.getUint8((y * _width + x) * 4 + 1);
int _b(ByteData b, int x, int y) => b.getUint8((y * _width + x) * 4 + 2);

bool _red(ByteData b, int x, int y) =>
    _r(b, x, y) > 200 && _g(b, x, y) < 60 && _b(b, x, y) < 60;
bool _blue(ByteData b, int x, int y) =>
    _b(b, x, y) > 200 && _r(b, x, y) < 60 && _g(b, x, y) < 60;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('后绘制 z-index 更大的块（红 z=2 在蓝 z=1 之上）', () async {
    // 红块先、蓝块后（文档序），但红 z 更大 → 重叠处应红。
    final data = await _render([
      _absolute('#ff0000', '2', 0, 0),
      _absolute('#0000ff', '1', 40, 40),
    ]);
    expect(_red(data, 60, 60), isTrue, reason: 'z-index 大的红块应在上层');
  });

  test('调换 z-index 后蓝块在上（证明不是靠文档序）', () async {
    final data = await _render([
      _absolute('#ff0000', '1', 0, 0),
      _absolute('#0000ff', '2', 40, 40),
    ]);
    expect(_blue(data, 60, 60), isTrue, reason: 'z-index 大的蓝块应在上层');
  });

  test('都没有 z-index 时保持文档序（后者在上）', () async {
    final data = await _render([
      _absolute('#ff0000', 'auto', 0, 0),
      _absolute('#0000ff', 'auto', 40, 40),
    ]);
    expect(_blue(data, 60, 60), isTrue);
  });
}
