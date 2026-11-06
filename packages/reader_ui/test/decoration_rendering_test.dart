import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_ui/decorations/decoration.dart';
import 'package:reader_ui/decorations/decoration_geometry.dart';
import 'package:reader_ui/decorations/decoration_painter.dart';

const _start = 'epubcfi(/6/2!/4/2/1:0)';
const _end = 'epubcfi(/6/2!/4/2/1:20)';
const _red = 0xFFFF0000;
const _green = 0xFF00FF00;
const _blue = 0xFF0000FF;
const _yellow = 0xFFFFFF00;

Future<ByteData> _pixels(void Function(Canvas) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(240, 180);
  picture.dispose();
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return pixels!;
}

int _alpha(ByteData pixels, int left, int top) =>
    pixels.getUint8((top * 240 + left) * 4 + 3);

int _color(ByteData pixels, int left, int top) {
  final offset = (top * 240 + left) * 4;
  return pixels.getUint8(offset + 3) << 24 |
      pixels.getUint8(offset) << 16 |
      pixels.getUint8(offset + 1) << 8 |
      pixels.getUint8(offset + 2);
}

PageContent _page({double width = 160, double lineHeight = 3}) {
  final style = ComputedStyle({
    'font-family': 'Ahem',
    'font-size': '16px',
    'line-height': '$lineHeight',
  });
  return Paginator(pageHeight: 180)
      .measureChapter(
        blocks: [
          PageBlock(
            layout: TextLayoutEngine.layout(
              text: 'abcdefghijklmnopqrst',
              style: style,
              maxWidth: width,
            ),
            style: style,
            startCfi: _start,
          ),
        ],
      )
      .pages
      .single;
}

ReaderDecorationRange _range(
  ReaderDecorationStyle style, {
  String start = _start,
  String end = _end,
}) => ReaderDecorationRange(startCfi: start, endCfi: end, style: style);

ReaderDecoration _decoration(String id, DateTime createdAt) => ReaderDecoration(
  id: id,
  startCfi: _start,
  endCfi: _end,
  quote: 'abcdefghijklmnopqrst',
  style: const ReaderDecorationStyle(backgroundColor: _yellow),
  createdAt: createdAt,
  updatedAt: createdAt,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('多行装饰每行独立闭合，不把行间空白连接成外框', () async {
    final page = _page();
    final boxes = ReaderDecorationGeometry.boxesFor(page, [
      _range(
        const ReaderDecorationStyle(
          backgroundColor: _yellow,
          borderRadius: 4,
          borderTop: ReaderDecorationBorderSide(width: 2, color: _red),
          borderBottom: ReaderDecorationBorderSide(width: 2, color: _red),
        ),
      ),
    ]);
    expect(boxes, hasLength(2));
    final first = boxes.first.rects.single;
    final last = boxes.last.rects.single;
    final pixels = await _pixels((canvas) {
      for (final box in boxes) {
        ReaderDecorationPainter.paintBox(canvas, box.rects.single, box.style);
      }
    });
    expect(_color(pixels, 40, first.top.ceil()), _red);
    expect(_color(pixels, 40, last.top.ceil()), _red);
    expect(_color(pixels, 40, first.center.dy.floor()), _yellow);
    expect(_alpha(pixels, 40, ((first.bottom + last.top) / 2).floor()), 0);
  });

  test('背景透明度和圆角裁切均反映到真实像素', () async {
    final pixels = await _pixels(
      (canvas) => ReaderDecorationPainter.paintBox(
        canvas,
        const Rect.fromLTWH(10, 10, 120, 60),
        const ReaderDecorationStyle(
          backgroundColor: _red,
          backgroundOpacity: 0.5,
          borderRadius: 12,
        ),
      ),
    );
    expect(_alpha(pixels, 10, 10), 0);
    expect(_alpha(pixels, 40, 30), inInclusiveRange(127, 128));
    expect(_alpha(pixels, 9, 40), 0);
  });

  test('四边不同宽度和颜色独立绘制，内部保持透明', () async {
    final pixels = await _pixels(
      (canvas) => ReaderDecorationPainter.paintBox(
        canvas,
        const Rect.fromLTWH(10, 10, 120, 60),
        const ReaderDecorationStyle(
          borderTop: ReaderDecorationBorderSide(width: 2, color: _red),
          borderRight: ReaderDecorationBorderSide(width: 4, color: _green),
          borderBottom: ReaderDecorationBorderSide(width: 6, color: _blue),
          borderLeft: ReaderDecorationBorderSide(width: 3, color: _yellow),
        ),
      ),
    );
    expect(_color(pixels, 50, 10), _red);
    expect(_alpha(pixels, 50, 12), 0);
    expect(_color(pixels, 128, 40), _green);
    expect(_alpha(pixels, 125, 40), 0);
    expect(_color(pixels, 50, 65), _blue);
    expect(_alpha(pixels, 50, 63), 0);
    expect(_color(pixels, 11, 40), _yellow);
    expect(_alpha(pixels, 13, 40), 0);
    expect(_alpha(pixels, 50, 40), 0);
  });

  test('实线双线虚线点线生成四种不同边框像素', () async {
    final signatures = <String>{};
    for (final lineStyle in ReaderDecorationBorderStyle.values) {
      const side = ReaderDecorationBorderSide(width: 6, color: _blue);
      final pixels = await _pixels(
        (canvas) => ReaderDecorationPainter.paintBox(
          canvas,
          const Rect.fromLTWH(10, 10, 120, 60),
          ReaderDecorationStyle(
            borderStyle: lineStyle,
            borderTop: side,
            borderRight: side,
            borderBottom: side,
            borderLeft: side,
          ),
        ),
      );
      expect(_alpha(pixels, 50, 40), 0);
      expect(pixels.buffer.asUint8List().any((value) => value != 0), isTrue);
      expect(
        signatures.add(pixels.buffer.asUint8List().join(',')),
        isTrue,
        reason: lineStyle.name,
      );
    }
    expect(signatures, hasLength(4));
  });

  test('背景图片采用cover居中裁切，缺失时保留背景色', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final (left, color) in [(0.0, _red), (10.0, _green), (20.0, _blue)]) {
      canvas.drawRect(
        Rect.fromLTWH(left, 0, 10, 10),
        Paint()..color = Color(color),
      );
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(30, 10);
    picture.dispose();
    addTearDown(image.dispose);
    const style = ReaderDecorationStyle(
      backgroundColor: _yellow,
      backgroundImagePath: '/local/background.png',
      borderRadius: 6,
    );
    final pixels = await _pixels(
      (canvas) => ReaderDecorationPainter.paintBox(
        canvas,
        const Rect.fromLTWH(10, 10, 30, 30),
        style,
        image: image,
      ),
    );
    expect(_color(pixels, 14, 25), _green);
    expect(_color(pixels, 35, 25), _green);
    expect(_alpha(pixels, 10, 10), 0);
    final missing = await _pixels(
      (canvas) => ReaderDecorationPainter.paintBox(
        canvas,
        const Rect.fromLTWH(10, 10, 30, 30),
        style,
      ),
    );
    expect(_color(missing, 25, 25), _yellow);
  });

  test('绘制内边距不改变布局，垂直扩展受行距余量和8dp双重限制', () {
    final page = _page();
    final layout = page.slices.single.block.layout;
    final boxes = ReaderDecorationGeometry.boxesFor(page, [
      _range(
        const ReaderDecorationStyle(
          paddingTop: 12,
          paddingRight: 12,
          paddingBottom: 12,
          paddingLeft: 12,
        ),
      ),
    ]);
    for (final box in boxes) {
      final original = box.range.rects.single;
      final expanded = box.rects.single;
      final line = box.range.line.rect;
      expect(expanded.left, original.left - 12);
      expect(expanded.right, original.right + 12);
      expect(
        original.top - expanded.top,
        math.min(8, math.max(0, original.top - line.top)),
      );
      expect(
        expanded.bottom - original.bottom,
        math.min(8, math.max(0, line.bottom - original.bottom)),
      );
    }
    expect(page.slices.single.block.layout, same(layout));
    expect(layout.lineCount, 2);
  });

  test('重叠装饰逐属性合并，手工后者覆盖前者且点击选最新创建记录', () {
    final page = _page(width: 400);
    final boxes = ReaderDecorationGeometry.boxesFor(page, [
      _range(
        const ReaderDecorationStyle(color: _red, backgroundColor: _yellow),
      ),
      _range(
        const ReaderDecorationStyle(color: _blue, borderRadius: 4),
        start: 'epubcfi(/6/2!/4/2/1:5)',
        end: 'epubcfi(/6/2!/4/2/1:15)',
      ),
      _range(
        const ReaderDecorationStyle(fontWeight: 700),
        start: 'epubcfi(/6/2!/4/2/1:7)',
        end: 'epubcfi(/6/2!/4/2/1:9)',
      ),
    ]);
    expect(boxes, hasLength(5));
    expect(boxes.first.style.color, _red);
    expect(boxes[2].style.color, _blue);
    expect(boxes[2].style.backgroundColor, _yellow);
    expect(boxes[2].style.fontWeight, 700);
    expect(boxes[2].style.borderRadius, 4);
    expect(boxes.last.style.color, _red);
    final older = _decoration('older', DateTime(2026));
    final newer = _decoration('newer', DateTime(2026, 2));
    expect(
      ReaderDecorationGeometry.decorationAt(
        page,
        boxes[2].rects.single.center,
        [newer, older],
      )?.id,
      newer.id,
    );
    expect(
      ReaderDecorationGeometry.decorationAt(page, const Offset(10, 160), [
        newer,
        older,
      ]),
      isNull,
    );
  });

  test('墨水屏背景降级黑线，保留边框形状但不保留彩色', () async {
    final pixels = await _pixels(
      (canvas) => ReaderDecorationPainter.paintBox(
        canvas,
        const Rect.fromLTWH(10, 10, 120, 60),
        const ReaderDecorationStyle(
          backgroundColor: _yellow,
          borderTop: ReaderDecorationBorderSide(width: 2, color: _red),
        ),
        inkMode: true,
      ),
    );
    expect(_color(pixels, 50, 10), 0xFF000000);
    expect(_color(pixels, 50, 69), 0xFF000000);
    expect(_alpha(pixels, 50, 40), 0);
  });
}
