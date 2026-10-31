import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/paint/paragraph_cache.dart';

ComputedStyle _style([Map<String, String> properties = const {}]) =>
    ComputedStyle({'font-size': '24px', 'line-height': '2', ...properties});

PageBlock _redBox() => PageBlock.styled(
  layout: TextLayoutResult(
    text: '',
    lines: [],
    width: 0,
    height: 0,
    maxWidth: 40,
  ),
  style: _style({'width': '40px', 'height': '18px', 'background-color': 'red'}),
  containingWidth: 140,
);

PageBlock _wrap(PageBlock child, {bool withText = false, bool clip = false}) {
  final style = _style({
    'width': '140px',
    'background-color': '#ddeeff',
    if (clip) 'height': '20px',
    if (clip) 'overflow': 'hidden',
  });
  final layout = TextLayoutEngine.layout(
    text: withText ? '前后' : '',
    style: style,
    maxWidth: 140,
    inlineBoxes: [
      InlineBoxSpec(
        offset: withText ? 1 : 0,
        width: child.style!.width!.resolve(140)!,
        height: child.style!.height?.resolve(140) ?? child.layout.height,
        contentHeight: child.layout.height,
        contentBaseline: child.layout.lines.isEmpty
            ? 18
            : child.layout.lines.last.baseline,
        payload: child,
      ),
    ],
  );
  return PageBlock.styled(layout: layout, style: style, containingWidth: 140);
}

Future<ByteData> _paint(PageBlock block, {ParagraphCache? cache}) async {
  final page = Paginator(pageHeight: 160)
      .measureChapter(blocks: [block])
      .pages
      .first;
  final recorder = ui.PictureRecorder();
  PagePainter(paragraphCache: cache)
      .paint(Canvas(recorder), page, pageSize: const Size(180, 160));
  final picture = recorder.endRecording();
  final image = await picture.toImage(180, 160);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return data!;
}

int _redPixels(ByteData data) {
  var count = 0;
  for (var i = 0; i < data.lengthInBytes; i += 4) {
    if (data.getUint8(i) > 240 &&
        data.getUint8(i + 1) < 10 &&
        data.getUint8(i + 2) < 10 &&
        data.getUint8(i + 3) > 240) {
      count++;
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('嵌套载荷绘制内盒背景，缓存与非缓存结果一致', () async {
    final block = _wrap(_wrap(_redBox(), withText: true));
    final pixels = await _paint(block);
    expect(_redPixels(pixels), 40 * 18);
    final cache = ParagraphCache();
    final cached = await _paint(block, cache: cache);
    expect(cached.buffer.asUint8List(), pixels.buffer.asUint8List());
    cache.clear();
  });

  test('没有文字的多层原子盒仍递归绘制子盒', () async {
    expect(_redPixels(await _paint(_wrap(_wrap(_redBox())))), 40 * 18);
  });

  test('内盒递归绘制不逃逸外盒 overflow 裁剪', () async {
    final full = _redPixels(
      await _paint(_wrap(_wrap(_redBox(), withText: true))),
    );
    final clipped = _redPixels(
      await _paint(_wrap(_wrap(_redBox(), withText: true, clip: true))),
    );
    expect(clipped, greaterThan(0));
    expect(clipped, lessThan(full));
  });
}
