import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/paint/hit_test.dart';

import 'support/css_chapter_book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('保留多看根容器时每页回收首尾行高，重开章节不恢复旧留白', () async {
    final source = await openCssChapter(
      body:
          '<p>abc<br/>def<br/>ghi<br/>jkl<br/>mno<br/>pqr</p>'
          '<span class="block">结束</span>',
      css:
          'html, body { margin: 0; padding: 0; height: 100%; width: 100%; }'
          'body { font-family: Ahem; font-size: 20px; line-height: 2; }'
          'p { margin: 0; } .block { display: block; }',
      contentWidth: 200,
      contentHeight: 100,
    );
    final pages = await source.loadChapter(0);
    expect(pages.length, 3);
    for (final page in pages.take(2)) {
      final slice = page.slices.single;
      expect(slice.block.containers.single.container.isPageRoot, isTrue);
      expect(slice.textTopTrim, closeTo(10, 0.01));
      expect(slice.textBottomTrim, closeTo(10, 0.01));
      expect(page.usedHeight, closeTo(100, 0.01));
      final boxes = TextHitTester.lineBoxes(page);
      expect(boxes.first.rect.top, closeTo(0, 0.01));
      expect(boxes.last.rect.bottom, closeTo(100, 0.01));
      expect(
        TextHitTester.hitTest(page, const Offset(10, 1))!.lineBox.text,
        boxes.first.text,
      );
    }
    source.clearPaginationCache();
    final replayed = await source.loadChapter(0);
    expect(replayed.length, pages.length);
    for (var i = 0; i < pages.length; i++) {
      expect(replayed[i].usedHeight, pages[i].usedHeight);
      expect(
        TextHitTester.lineBoxes(replayed[i]).map((box) => box.rect),
        TextHitTester.lineBoxes(pages[i]).map((box) => box.rect),
      );
    }
  });
}
