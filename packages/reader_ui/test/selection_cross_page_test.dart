import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_ui/selection/selection.dart';

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

/// 造一页：把给定文本切成固定宽度（160）的排版。
PageContent _page(String text, {required int pageIndex}) {
  final layout = TextLayoutEngine.layout(
    text: text,
    style: _style(),
    maxWidth: 160,
  );
  final block = PageBlock(layout: layout, style: _style(), startCfi: 'epubcfi(/6/4!/4/2/1)');
  final slice = PageBlockSlice(
    block: block,
    startLine: 0,
    endLine: layout.lineCount,
    height: layout.height,
  );
  return PageContent(
    spineIndex: 0,
    pageIndex: pageIndex,
    slices: <PageBlockSlice>[slice],
    usedHeight: layout.height,
    pageHeight: 400,
    topPadding: 8,
  );
}

void main() {
  group('跨页选区（P4-19）', () {
    late List<PageContent> pages;
    late TextHit startHit;
    late TextHit endHit;

    setUp(() {
      pages = <PageContent>[
        _page('第一页的文字内容第一页的文字内容', pageIndex: 0),
        _page('第二页的文字内容第二页的文字内容', pageIndex: 1),
        _page('第三页的文字内容第三页的文字内容', pageIndex: 2),
      ];
      final firstBoxes = TextHitTester.lineBoxes(pages[0]);
      final lastBoxes = TextHitTester.lineBoxes(pages[2]);
      startHit = TextHitTester.hitTest(
        pages[0],
        Offset(firstBoxes.first.rect.left + 2, firstBoxes.first.rect.center.dy),
      )!;
      endHit = TextHitTester.hitTest(
        pages[2],
        Offset(lastBoxes.last.rect.left + 30, lastBoxes.last.rect.center.dy),
      )!;
    });

    test('跨 3 页：每页只算与自身交集的范围', () {
      final selection = ReaderSelection.spanning(
        start: startHit,
        startPageIndex: 0,
        end: endHit,
        endPageIndex: 2,
      );
      expect(selection.isMultiPage, isTrue);

      // 第 1 页：从起点到页末。
      final g0 = SelectionOps.geometryForPage(pages[0], 0, selection)!;
      expect(g0.lineRects, isNotEmpty);
      final local0 = SelectionOps.localSelectionOf(pages[0], 0, selection)!;
      expect(local0.start.charOffset, startHit.charOffset);
      expect(
        local0.end.charOffset,
        TextHitTester.lineBoxes(pages[0]).last.text.length,
        reason: '起点页延伸到页末',
      );

      // 第 2 页（中间页）：整页。
      final local1 = SelectionOps.localSelectionOf(pages[1], 1, selection)!;
      expect(local1.start.charOffset, 0);
      expect(
        local1.end.charOffset,
        TextHitTester.lineBoxes(pages[1]).last.text.length,
      );

      // 第 3 页：从页首到终点。
      final local2 = SelectionOps.localSelectionOf(pages[2], 2, selection)!;
      expect(local2.start.charOffset, 0);
      expect(local2.end.charOffset, endHit.charOffset);
    });

    test('不在选区范围内的页返回 null', () {
      final selection = ReaderSelection.spanning(
        start: startHit,
        startPageIndex: 1,
        end: endHit,
        endPageIndex: 2,
      );
      expect(SelectionOps.geometryForPage(pages[0], 0, selection), isNull);
      expect(SelectionOps.geometryForPage(pages[1], 1, selection), isNotNull);
    });

    test('复制文本完整有序（按页拼接）', () {
      final selection = ReaderSelection.spanning(
        start: startHit,
        startPageIndex: 0,
        end: endHit,
        endPageIndex: 2,
      );
      final text = SelectionOps.textAcrossPages(pages, selection);
      expect(text, contains('第一页的文字内容'));
      expect(text, contains('第二页的文字内容'));
      expect(text, contains('第三页的文字内容'));
      expect(
        text.indexOf('第一页'),
        lessThan(text.indexOf('第二页')),
        reason: '顺序按页',
      );
      expect(text.indexOf('第二页'), lessThan(text.indexOf('第三页')));
    });

    test('起点页尾/终点页首边界：单页选区仍等价 geometryOf', () {
      final boxes = TextHitTester.lineBoxes(pages[0]);
      final a = TextHitTester.hitTest(
        pages[0],
        Offset(boxes.first.rect.left + 4, boxes.first.rect.center.dy),
      )!;
      final b = TextHitTester.hitTest(
        pages[0],
        Offset(boxes.first.rect.left + 40, boxes.first.rect.center.dy),
      )!;
      final single = ReaderSelection.spanning(
        start: a,
        startPageIndex: 0,
        end: b,
        endPageIndex: 0,
      );
      final viaPage = SelectionOps.geometryForPage(pages[0], 0, single)!;
      final direct = SelectionOps.geometryOf(pages[0], single);
      expect(viaPage.lineRects.length, direct.lineRects.length);
    });

    test('spanning 归一：起点页在后时自动交换', () {
      final selection = ReaderSelection.spanning(
        start: endHit,
        startPageIndex: 2,
        end: startHit,
        endPageIndex: 0,
      );
      expect(selection.startPageIndex, 0);
      expect(selection.endPageIndex, 2);
      expect(selection.start.charOffset, startHit.charOffset);
    });
  });
}
