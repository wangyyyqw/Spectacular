import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/paint/paragraph_cache.dart';

const _size = Size(200, 120);
const _text = 'abc\nTITLE';
final _base = ComputedStyle({
  'font-family': 'Ahem',
  'font-size': '20px',
  'line-height': '1.6',
  'color': '#224466',
});
final _small = ComputedStyle({
  'font-size': '0.7em',
  'color': '#cc3322',
}, parent: _base);

TextPainter _reference() => TextPainter(
  text: TextSpan(
    style: TextLayoutEngine.textStyleFor(_base),
    children: [
      TextSpan(text: 'abc', style: TextLayoutEngine.textStyleFor(_small)),
      const TextSpan(text: '\nTITLE'),
    ],
  ),
  textDirection: TextDirection.ltr,
  strutStyle: StrutStyle.fromTextStyle(TextLayoutEngine.textStyleFor(_base)),
)..layout(maxWidth: _size.width);

PageContent _page() {
  final layout = TextLayoutEngine.layout(
    text: _text,
    style: _base,
    maxWidth: _size.width,
    runs: [StyledRun(start: 0, end: 3, style: _small)],
  );
  return Paginator(pageHeight: _size.height, topPadding: 20)
      .measureChapter(
        blocks: [PageBlock(layout: layout, style: _base)],
      )
      .pages
      .single;
}

Future<Uint8List> _pixels(void Function(Canvas) paint) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Offset.zero & _size,
    Paint()..color = const Color(0xFFFFFFFF),
  );
  paint(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 120);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('小字号章序与大字号章名逐行绘制保持整段基线，缓存重绘一致', () async {
    final reference = _reference();
    addTearDown(reference.dispose);
    final expected = await _pixels(
      (canvas) => reference.paint(canvas, const Offset(0, 20)),
    );
    final page = _page();
    expect(page.slices.single.block.layout.lines.first.height, 32);
    expect(
      page.slices.single.block.layout.lines.first.baseline,
      closeTo(reference.computeLineMetrics().first.baseline, 0.01),
    );
    final cache = ParagraphCache();
    addTearDown(cache.dispose);
    final painter = PagePainter(paragraphCache: cache);
    for (var pass = 0; pass < 2; pass++) {
      final actual = await _pixels(
        (canvas) => painter.paint(canvas, page, pageSize: _size),
      );
      expect(actual, orderedEquals(expected), reason: '小字号首行不能使用自己的行顶基线');
    }
    expect(cache.hits, greaterThan(0));
  });

  test('小字号首行选区与整段排版位置一致', () {
    final reference = _reference();
    addTearDown(reference.dispose);
    final line = TextHitTester.lineBoxes(_page()).first;
    final expected = reference
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 3),
        )
        .single
        .toRect();
    final actual = TextHitTester.selectionRects(line, 0, 3).single;
    expect(actual.left, expected.left);
    expect(actual.right, expected.right);
    // Skia 选区框受整数行高取整影响，允许半像素误差，不允许丢掉基线偏移。
    expect(actual.top, closeTo(expected.top, 0.5));
    expect(actual.bottom, closeTo(expected.bottom, 0.5));
  });

  test('小字号独占段落不增加占位，行顶搬移时基线同步移动', () {
    final layout = TextLayoutEngine.layout(
      text: 'abcdefgh',
      style: _base,
      maxWidth: 56,
      runs: [StyledRun(start: 0, end: 8, style: _small)],
    );
    expect(layout.lineCount, 2);
    expect(layout.height, 44, reason: '不强制撑大已排好的行盒');
    final first = layout.lines.first;
    final moved = first.copyWith(top: first.top + 22);
    expect(moved.baseline - moved.top, first.baseline - first.top);
  });
}
