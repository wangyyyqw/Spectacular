import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';

import 'support/css_chapter_book.dart';

Future<PageBlock> _block(String content, [String css = '']) async {
  final source = await openCssChapter(
    body: '<p>前$content后</p>',
    css:
        'p { margin: 0; font-size: 24px; line-height: 2; } '
        '.box { display: inline-block; width: 90px; padding: 2px; '
        'border: 1px solid black; } $css',
    contentWidth: 350,
    contentHeight: 900,
  );
  return (await source.loadChapter(0)).first.slices.first.block;
}

InlineBoxPlacement _box(PageBlock block) =>
    block.layout.lines.expand((line) => line.inlineBoxes).single;

void _expectContentBaseline(InlineBoxPlacement placement) {
  final payload = placement.spec.payload! as PageBlock;
  final style = payload.style!;
  final expected =
      style.margin.top +
      style.borders.top.width +
      style.padding.top +
      payload.layout.lines.last.baseline;
  expect(placement.ascent, closeTo(expected, .01));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('非空盒以实际末行基线加顶部 inset 对齐，不计底部 inset', () async {
    final block = await _block(
      '<span class="box">盒</span>',
      '.box { padding: 4px 2px 9px; margin: 5px 0 2px; }',
    );
    _expectContentBaseline(_box(block));
  });

  test('子盒不同字号与行高不借用外部行的字体基线', () async {
    final block = await _block(
      '<span class="box">盒</span>',
      'p { font-size: 12px; line-height: 1.2; } '
          '.box { font-size: 33px; line-height: 1.7; }',
    );
    _expectContentBaseline(_box(block));
  });

  test('多行盒对齐最后一行基线而不是第一行或内容底边', () async {
    final block = await _block('<span class="box">甲<br/>乙</span>');
    final placement = _box(block);
    final payload = placement.spec.payload! as PageBlock;
    expect(payload.layout.lines, hasLength(2));
    _expectContentBaseline(placement);
  });

  test('嵌套盒每层都以各自最后内容行基线对齐', () async {
    var block = await _block(
      '<span class="box outer">甲<span class="box">乙</span>丙</span>',
      '.outer { width: 160px; }',
    );
    for (var depth = 0; depth < 2; depth++) {
      final placement = _box(block);
      _expectContentBaseline(placement);
      block = placement.spec.payload! as PageBlock;
    }
  });

  for (final overflow in ['hidden', 'auto', 'scroll']) {
    test('overflow: $overflow 以底部 margin 边缘对齐且溢出不撑高行盒', () async {
      final block = await _block(
        '<span class="box">甲<br/>乙<br/>丙</span>',
        '.box { height: 18px; margin: 3px 0 4px; overflow: $overflow; }',
      );
      final placement = _box(block);
      expect(placement.height, 24);
      expect(placement.ascent, closeTo(3 + 24 + 4, .01));
      expect(placement.descent, closeTo(0, .01));
      final plain = TextLayoutEngine.layout(
        text: '前后',
        style: block.style!,
        maxWidth: 350,
      ).lines.single;
      final ascent = placement.ascent > plain.baseline
          ? placement.ascent
          : plain.baseline;
      expect(
        block.layout.height,
        closeTo(ascent + plain.height - plain.baseline, .01),
      );
    });
  }
}
