import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _width = 180;
const _height = 100;

ComputedStyle _style(String clipPath) => ComputedStyle(<String, String>{
  'font-size': '10px',
  'line-height': '1',
  'font-family': 'Ahem',
  'color': 'transparent',
  'width': '120px',
  'height': '60px',
  'background-color': '#FF0000',
  'clip-path': clipPath,
});

Future<ui.Image> _render(ComputedStyle style) async {
  final block = PageBlock.styled(
    layout: TextLayoutEngine.layout(text: ' ', style: style, maxWidth: 120),
    style: style,
    containingWidth: 120,
  );
  final page = Paginator(pageHeight: _height.toDouble())
      .measureChapter(blocks: [block])
      .pages
      .single;
  final recorder = ui.PictureRecorder();
  const PagePainter().paint(
    Canvas(recorder),
    page,
    pageSize: Size(_width.toDouble(), _height.toDouble()),
  );
  return recorder.endRecording().toImage(_width, _height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clip-path 基本形状解析为 Chromium 计算值序列化', () {
    final inset = ComputedStyle(const <String, String>{
      'clip-path': 'inset(10px 5% 20px round 4px / 8px)',
    });
    expect(inset.clipPath!.cssValue, 'inset(10px 5% 20px round 4px / 8px)');

    final circle = ComputedStyle(const <String, String>{
      'clip-path': 'circle(40% at 25% 75%)',
    });
    expect(circle.clipPath!.cssValue, 'circle(40% at 25% 75%)');

    final ellipse = ComputedStyle(const <String, String>{
      'clip-path': 'ellipse(closest-side farthest-side at left top)',
    });
    expect(
      ellipse.clipPath!.cssValue,
      'ellipse(closest-side farthest-side at 0% 0%)',
    );

    final polygon = ComputedStyle(const <String, String>{
      'clip-path': 'polygon(nonzero, 0px 0px, 100% 0%, 50% 100%)',
    });
    expect(polygon.clipPath!.cssValue, 'polygon(0px 0px, 100% 0%, 50% 100%)');
  });

  test('clip-path 不继承，非法 SVG 引用按无效声明处理', () {
    final parent = ComputedStyle(const <String, String>{
      'clip-path': 'circle(40%)',
    });
    final child = ComputedStyle(const <String, String>{
      'font-size': '12px',
    }, parent: parent);
    expect(child.clipPath, isNull);
    expect(
      ComputedStyle(const <String, String>{'clip-path': 'url(#mask)'}).clipPath,
      isNull,
    );
  });

  test('polygon 裁剪掉三角形之外的全部背景', () async {
    final clip = ComputedStyle(const <String, String>{
      'font-size': '10px',
      'line-height': '1',
      'font-family': 'Ahem',
      'color': 'transparent',
      'width': '120px',
      'height': '60px',
      'margin-left': '20px',
      'background-color': '#FF0000',
      'clip-path': 'polygon(0 0, 100% 0, 50% 100%)',
    });
    final image = await _render(clip);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
    Color pixel(int x, int y) {
      final offset = (y * _width + x) * 4;
      return Color.fromARGB(
        bytes.getUint8(offset + 3),
        bytes.getUint8(offset),
        bytes.getUint8(offset + 1),
        bytes.getUint8(offset + 2),
      );
    }

    expect(pixel(80, 8), const Color(0xFFFF0000), reason: '三角形顶部内侧');
    expect(pixel(28, 50), const Color(0xFFFFFFFF), reason: '左下角应在形状外');
  });

  test('inset round 同时裁掉四角', () async {
    final image = await _render(_style('inset(0 round 20px)'));
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
    Color pixel(int x, int y) {
      final offset = (y * _width + x) * 4;
      return Color.fromARGB(
        bytes.getUint8(offset + 3),
        bytes.getUint8(offset),
        bytes.getUint8(offset + 1),
        bytes.getUint8(offset + 2),
      );
    }

    var minX = _width;
    var minY = _height;
    for (var y = 0; y < _height; y++) {
      for (var x = 0; x < _width; x++) {
        if (pixel(x, y) == const Color(0xFFFF0000)) {
          minX = x < minX ? x : minX;
          minY = y < minY ? y : minY;
        }
      }
    }
    expect(pixel(minX + 2, minY + 2), const Color(0xFFFFFFFF), reason: '圆角外');
    expect(pixel(minX + 22, minY + 8), const Color(0xFFFF0000), reason: '圆角内');
  });
}
