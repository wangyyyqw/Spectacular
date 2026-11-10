import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/page_furniture/page_furniture.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/theme/reader_margins.dart';

PageContent _page(int spine, int index) {
  const text = '页脚测试内容，多页填充。';
  final layout = TextLayoutEngine.layout(
    text: text,
    style: ComputedStyle(const <String, String>{
      'font-size': '14px',
      'line-height': '1.4',
    }),
    maxWidth: 300,
  );
  final block = PageBlock(layout: layout);
  return PageContent(
    spineIndex: spine,
    pageIndex: index,
    slices: [
      PageBlockSlice(
        block: block,
        startLine: 0,
        endLine: layout.lineCount,
        height: layout.height,
      ),
    ],
    usedHeight: layout.height,
    pageHeight: 400,
    topPadding: 0,
  );
}

class _MultiPageSource implements ReaderChapterSource {
  _MultiPageSource({required this.chapters, required this.pagesPerChapter});

  final int chapters;

  final int pagesPerChapter;

  @override
  int get chapterCount => chapters;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => [
    for (var i = 0; i < pagesPerChapter; i++) _page(spineIndex, i),
  ];
}

class _SizedPageSource implements ResizableChapterSource {
  Size? contentSize;

  @override
  int get chapterCount => 1;

  @override
  Future<bool> applyContentSize({
    required double width,
    required double height,
    double topInset = 0,
  }) async {
    contentSize = Size(width, height);
    return true;
  }

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => [
    _page(0, 0),
    _page(0, 1),
  ];
}

void _expectFurniture(WidgetTester tester, {int? chapter}) {
  expect(
    find.byType(ReaderPageHeader),
    chapter == null ? findsNothing : findsOneWidget,
  );
  if (chapter != null) {
    expect(find.text('第 $chapter 章'), findsOneWidget);
    expect(find.text('2/2'), findsOneWidget);
  }
  expect(find.byType(ReaderPageFooter), findsOneWidget);
  expect(find.textContaining(RegExp(r'^\d{2}:\d{2}$')), findsOneWidget);
  expect(find.textContaining(RegExp(r'%$')), findsOneWidget);
}

void main() {
  testWidgets('每章首页隐藏页眉，前后翻页与目录跳转均保留页脚', (tester) async {
    late ReaderSession session;
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          source: _MultiPageSource(chapters: 2, pagesPerChapter: 2),
          store: MemoryReaderProgressStore(),
          bookId: 'footer-test',
          pageTurnMode: PageTurnMode.none,
          onSessionReady: (value) => session = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    _expectFurniture(tester);
    for (final chapter in [1, null, 2]) {
      await session.next();
      await tester.pumpAndSettle();
      _expectFurniture(tester, chapter: chapter);
    }
    await session.previous();
    await tester.pumpAndSettle();
    _expectFurniture(tester);
    await session.jumpToChapter(0);
    await tester.pumpAndSettle();
    _expectFurniture(tester);
  });

  testWidgets('showPageFooter=false 关闭页脚', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          source: _MultiPageSource(chapters: 2, pagesPerChapter: 3),
          store: MemoryReaderProgressStore(),
          bookId: 'footer-off',
          showPageFooter: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('第 1 章'), findsNothing);
    expect(find.textContaining(RegExp(r'%$')), findsNothing);
  });

  testWidgets('首页保留正文留白，后续页按显式外段定位页眉页脚', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(400, 800));
    final source = _SizedPageSource();
    late ReaderSession session;
    const margins = ReaderMargins(
      left: 20,
      right: 20,
      topOuter: 30,
      topInner: 14,
      bottomInner: 11,
      bottomOuter: 18,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          source: source,
          store: MemoryReaderProgressStore(),
          bookId: 'margin-layout',
          margins: margins,
          pageTurnMode: PageTurnMode.none,
          onSessionReady: (value) => session = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(source.contentSize?.width, 360);
    expect(
      source.contentSize?.height,
      800 -
          (30 + PageFurniture.headerHeight + 14) -
          (18 + PageFurniture.footerHeight + 11),
      reason: '正文高度只扣除外段、页眉页脚自身高度和内段',
    );

    final header = find.byType(ReaderPageHeader);
    final footer = find.byType(ReaderPageFooter);
    expect(header, findsNothing);
    expect(tester.getBottomLeft(footer), const Offset(20, 782));

    await session.next();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(header), const Offset(20, 30));
    expect(tester.getBottomLeft(footer), const Offset(20, 782));
  });
}
