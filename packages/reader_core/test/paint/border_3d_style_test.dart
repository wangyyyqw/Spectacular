import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/page_renderer.dart';

/// 3D 边框（CSS Backgrounds §4.4）：groove/ridge/inset/outset 画两半明暗，
/// 真书里有 ridge 边框卡片（32 次）。
ComputedStyle _style(Map<String, String> overrides) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1',
      'font-family': 'Ahem',
      'margin': '0',
      'width': '100px',
      'height': '60px',
      'border-width': '8px',
      'border-color': '#888888',
      ...overrides,
    });

Future<ByteData> _render(Map<String, String> overrides) async {
  final style = _style(overrides);
  final block = PageBlock.styled(
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
  PagePainter(background: const Color(0xFFFFFFFF))
      .paint(canvas, page, pageSize: const Size(200, 200));
  final image = await recorder.endRecording().toImage(200, 200);
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  return data;
}

int _r(ByteData b, int x, int y) => b.getUint8((y * 200 + x) * 4);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('groove 使用 Chromium 色阶且角部连续', () async {
    final data = await _render(const {'border-style': 'groove'});
    // 上边框外半 y=2、内半 y=6（边宽 8，中线 y=4）。
    final outer = _r(data, 50, 2);
    final inner = _r(data, 50, 6);
    expect(outer, inInclusiveRange(51, 53), reason: 'Chromium #888 dark=52');
    expect(
      inner,
      inInclusiveRange(220, 222),
      reason: 'Chromium #888 light=221',
    );
    expect(
      _r(data, 113, 30),
      inInclusiveRange(220, 222),
      reason: 'groove 右边外半受光',
    );
    for (var offset = 0; offset < 8; offset++) {
      expect(
        _r(data, offset, offset),
        isNot(255),
        reason: '外角斜接不应出现白色接缝，offset=$offset',
      );
    }
  });

  test('ridge 上边框：外半比内半亮', () async {
    final data = await _render(const {'border-style': 'ridge'});
    final outer = _r(data, 50, 2);
    final inner = _r(data, 50, 6);
    expect(outer, greaterThan(inner), reason: '外亮内暗才是凸起 $outer/$inner');
    expect(_r(data, 113, 30), inInclusiveRange(51, 53), reason: 'ridge 右边外半背光');
  });

  test('inset 上左全暗、下右全亮', () async {
    final data = await _render(const {'border-style': 'inset'});
    expect(_r(data, 50, 2), inInclusiveRange(51, 53));
    expect(_r(data, 2, 30), inInclusiveRange(51, 53));
    // content-box：100×60 正文外加左右、上下各 8px 边框。
    expect(_r(data, 113, 30), inInclusiveRange(220, 222));
    expect(_r(data, 50, 73), inInclusiveRange(220, 222));
  });

  test('inset/outset 对黑色使用 Chromium 的提亮特判', () async {
    final inset = await _render(const {
      'border-style': 'inset',
      'border-color': '#000000',
    });
    expect(_r(inset, 50, 2), 84, reason: '黑色 inset 上边应为 Light(#000)');

    final outset = await _render(const {
      'border-style': 'outset',
      'border-color': '#000000',
    });
    expect(_r(outset, 50, 2), 168, reason: '黑色 outset 上边应为 Light(Light(#000))');
  });

  test('solid 仍是单色（上边两条采样一致）', () async {
    final data = await _render(const {'border-style': 'solid'});
    expect(_r(data, 50, 2), _r(data, 50, 6));
  });
}
