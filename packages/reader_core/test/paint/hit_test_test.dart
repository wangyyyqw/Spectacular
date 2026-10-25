import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/hit_test.dart';

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

PageBlock _block(String text, {double maxWidth = 160}) {
  final layout = TextLayoutEngine.layout(
    text: text,
    style: _style(),
    maxWidth: maxWidth,
  );
  return PageBlock(layout: layout, style: _style());
}

PageContent _page(List<PageBlockSlice> slices, {double topPadding = 8}) =>
    PageContent(
      spineIndex: 0,
      pageIndex: 0,
      slices: slices,
      usedHeight: slices.fold<double>(0, (sum, s) => sum + s.height),
      pageHeight: 600,
      topPadding: topPadding,
    );

PageBlockSlice _slice(PageBlock block, {double leading = 0}) => PageBlockSlice(
  block: block,
  startLine: 0,
  endLine: block.layout.lineCount,
  height: block.layout.height + leading,
  leadingExtent: leading,
);

void main() {
  group('字符级命中测试（P4-14）', () {
    test('行内坐标映射到正确字符（逐字符中心）', () {
      final block = _block('abcdefgh');
      final page = _page(<PageBlockSlice>[_slice(block)]);
      final boxes = TextHitTester.lineBoxes(page);
      expect(boxes, hasLength(1));
      final box = boxes.single;
      final charWidth = box.rect.width / box.text.length;

      for (var i = 0; i < box.text.length; i++) {
        final hit = TextHitTester.hitTest(
          page,
          Offset(box.rect.left + charWidth * (i + 0.5), box.rect.center.dy),
        )!;
        expect(hit.lineIndex, 0);
        expect(
          hit.charOffset,
          inInclusiveRange(i, i + 1),
          reason: '第 $i 个字符中心应命中该字符附近',
        );
        expect(hit.textOffset, inInclusiveRange(i, i + 1));
      }
    });

    test('多行：点击第二行命中第二行且偏移在行内', () {
      // 宽度 160 → 每个字符 16px → 每行 10 字符，两行。
      final block = _block('0123456789abcdefghij');
      final page = _page(<PageBlockSlice>[_slice(block)]);
      final boxes = TextHitTester.lineBoxes(page);
      expect(boxes.length, greaterThanOrEqualTo(2), reason: '应断成多行');

      final second = boxes[1];
      final hit = TextHitTester.hitTest(
        page,
        Offset(second.rect.left + second.rect.width * 0.5, second.rect.center.dy),
      )!;
      expect(hit.lineIndex, 1);
      expect(hit.lineBox.rect.top, greaterThan(boxes[0].rect.top));
      expect(hit.charOffset, greaterThan(0));
    });

    test('跨块：点击第二块不会落回第一块（不越界）', () {
      final first = _block('第一块文字');
      final second = _block('第二块文字');
      final page = _page(<PageBlockSlice>[
        _slice(first, leading: 4),
        _slice(second, leading: 8),
      ]);
      final boxes = TextHitTester.lineBoxes(page);
      expect(boxes.length, greaterThanOrEqualTo(2));
      final secondBox = boxes.last;

      final hit = TextHitTester.hitTest(
        page,
        Offset(secondBox.rect.left + 2, secondBox.rect.center.dy),
      )!;
      expect(hit.sliceIndex, 1, reason: '应命中第二块');
      // 命中行的文本必须来自第二块。
      expect(hit.lineBox.text, contains('二'));
    });

    test('越界坐标钳制：右侧超出行宽 → 行尾，页底之下 → 最后一行', () {
      final block = _block('0123456789abcdefghij');
      final page = _page(<PageBlockSlice>[_slice(block)]);
      final boxes = TextHitTester.lineBoxes(page);

      final farRight = TextHitTester.hitTest(
        page,
        Offset(boxes.first.rect.right + 200, boxes.first.rect.center.dy),
      )!;
      expect(farRight.atLineEnd, isTrue);
      expect(farRight.charOffset, boxes.first.text.length);

      final below = TextHitTester.hitTest(page, const Offset(20, 5000))!;
      expect(below.lineIndex, boxes.last.lineIndex);
      expect(below.sliceIndex, 0);

      final above = TextHitTester.hitTest(page, const Offset(20, -100))!;
      expect(above.lineIndex, boxes.first.lineIndex);
    });

    test('行几何：按阅读顺序、top 递增、宽度不为负', () {
      final block = _block('0123456789abcdefghij');
      final page = _page(<PageBlockSlice>[_slice(block, leading: 6)]);
      final boxes = TextHitTester.lineBoxes(page);
      expect(boxes.first.rect.top, 8 + 6, reason: '首行 y = topPadding + leading');
      for (var i = 1; i < boxes.length; i++) {
        expect(boxes[i].rect.top, greaterThan(boxes[i - 1].rect.top));
      }
      for (final box in boxes) {
        expect(box.rect.width, greaterThan(0));
        expect(box.textOffset, isNonNegative);
      }
    });

    test('空页返回 null', () {
      final page = _page(const <PageBlockSlice>[]);
      expect(TextHitTester.hitTest(page, const Offset(10, 10)), isNull);
      expect(TextHitTester.lineBoxes(page), isEmpty);
    });
  });
}
