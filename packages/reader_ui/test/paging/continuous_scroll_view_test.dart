import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/scroll_layout.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_ui/paging/continuous_scroll_view.dart';
import 'package:reader_ui/reader_session.dart';

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

PageContent _page(int spine, int page) {
  final style = _style();
  final layout = TextLayoutEngine.layout(
    text: '$spine-$page',
    style: style,
    maxWidth: 280,
  );
  return PageContent(
    spineIndex: spine,
    pageIndex: page,
    slices: [
      PageBlockSlice(
        block: PageBlock(layout: layout, style: style),
        startLine: 0,
        endLine: layout.lineCount,
        height: 300,
      ),
    ],
    usedHeight: 300,
    pageHeight: 300,
    topPadding: 0,
  );
}

PageContent _pageWithHeight(int spine, int page, double height) {
  final style = _style();
  final layout = TextLayoutEngine.layout(
    text: '$spine-$page',
    style: style,
    maxWidth: 280,
  );
  return PageContent(
    spineIndex: spine,
    pageIndex: page,
    slices: [
      PageBlockSlice(
        block: PageBlock(layout: layout, style: style),
        startLine: 0,
        endLine: layout.lineCount,
        height: height,
      ),
    ],
    usedHeight: height,
    pageHeight: height,
    topPadding: 0,
  );
}

class _Source implements ReaderChapterSource {
  final loads = <int>[];

  @override
  int get chapterCount => 5;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    loads.add(spineIndex);
    final count = spineIndex == 0 ? 2 : 30;
    return [for (var page = 0; page < count; page++) _page(spineIndex, page)];
  }
}

class _SingleChapterSource implements ReaderChapterSource {
  @override
  int get chapterCount => 1;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => [
    for (var page = 0; page < 3; page++) _page(spineIndex, page),
  ];
}

class _CfiPageSource implements ReaderChapterSource {
  _CfiPageSource() {
    final style = _style();
    final layout = TextLayoutEngine.layout(
      text: [for (var i = 0; i < 120; i++) '第$i行'].join('\n'),
      style: style,
      maxWidth: 280,
    );
    pages = Paginator(pageHeight: 200)
        .measureChapter(
          blocks: [
            PageBlock(
              layout: layout,
              style: style,
              startCfi: 'epubcfi(/6/2!/4/2/1:0)',
            ),
          ],
          spineIndex: 0,
        )
        .pages;
  }

  late final List<PageContent> pages;

  @override
  int get chapterCount => 1;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => pages;
}

class _VariablePageSource implements ReaderChapterSource {
  final loads = <int>[];

  @override
  int get chapterCount => 4;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    loads.add(spineIndex);
    final count = spineIndex == 0 ? 20 : 5;
    return [
      for (var page = 0; page < count; page++)
        _pageWithHeight(
          spineIndex,
          page,
          switch (spineIndex) {
            0 => page < 10 ? 300.0 : 320.0,
            1 => 300.0 + page * 20,
            _ => 300.0,
          },
        ),
    ];
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 20 && !condition(); i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('连续滚动恢复位置、懒构建并跨章扩展', (tester) async {
    final source = _Source();
    final store = MemoryReaderProgressStore();
    await store.save(
      'scroll',
      const ReaderProgress(spineIndex: 2, pageIndex: 1, scrollOffset: 125),
    );
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: 'scroll',
    );
    await session.open();
    final built = <String>{};

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            height: 480,
            child: ContinuousScrollView(
              session: session,
              revision: 1,
              padding: const EdgeInsets.all(20),
              paperBuilder: (page, size) {
                built.add('${page.spineIndex}-${page.pageIndex}');
                return ColoredBox(
                  key: ValueKey<String>(
                    'scroll-page-${page.spineIndex}-${page.pageIndex}',
                  ),
                  color: Colors.white,
                );
              },
            ),
          ),
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () =>
          source.loads.toSet().containsAll(<int>[1, 2, 3]) &&
          find
              .byKey(const ValueKey<String>('scroll-page-2-1'))
              .evaluate()
              .isNotEmpty,
    );

    expect(source.loads.toSet(), containsAll(<int>[1, 2, 3]));
    expect(
      find.byKey(const ValueKey<String>('scroll-page-2-1')),
      findsOneWidget,
    );
    final restoredScrollable = tester.state<ScrollableState>(
      find.byType(Scrollable),
    );
    expect(restoredScrollable.position.pixels, closeTo(9445, 0.01));
    expect(
      session.progress,
      const ReaderProgress(spineIndex: 2, pageIndex: 1, scrollOffset: 125),
    );
    expect(built.length, lessThan(90), reason: '长章节只构建可见范围');

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    scrollable.position.jumpTo(0);
    await _pumpUntil(tester, () => source.loads.contains(0));
    expect(source.loads, contains(0));

    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await _pumpUntil(tester, () => source.loads.contains(4));
    expect(source.loads, contains(4));
    session.dispose();
  });

  testWidgets('滚动到下一张切片后同步阅读进度', (tester) async {
    final source = _SingleChapterSource();
    final store = MemoryReaderProgressStore();
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: 'progress',
    );
    await session.open();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 480,
          child: ContinuousScrollView(
            session: session,
            revision: 1,
            padding: const EdgeInsets.all(20),
            paperBuilder: (page, size) => const ColoredBox(color: Colors.white),
          ),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    scrollable.position.jumpTo(350);
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      session.progress,
      const ReaderProgress(spineIndex: 0, pageIndex: 1, scrollOffset: 30),
    );
    session.dispose();
  });

  testWidgets('前插章节后保持当前可见页位置', (tester) async {
    final source = _VariablePageSource();
    final store = MemoryReaderProgressStore();
    await store.save(
      'scroll-insert',
      const ReaderProgress(spineIndex: 2, pageIndex: 0, scrollOffset: 100),
    );
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: 'scroll-insert',
    );
    await session.open();

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            height: 480,
            child: ContinuousScrollView(
              session: session,
              revision: 1,
              padding: const EdgeInsets.all(20),
              paperBuilder: (page, size) => ColoredBox(
                key: ValueKey<String>(
                  'scroll-page-${page.spineIndex}-${page.pageIndex}',
                ),
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () =>
          find
              .byKey(const ValueKey<String>('scroll-page-2-0'))
              .evaluate()
              .isNotEmpty,
    );

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    scrollable.position.jumpTo(80);
    await tester.pump(const Duration(milliseconds: 200));
    await _pumpUntil(tester, () => source.loads.contains(0));
    await _pumpUntil(
      tester,
      () => scrollable.position.pixels > 6000,
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(source.loads, contains(0));
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey<String>('scroll-page-1-0')),
          )
          .dy,
      closeTo(-60, 1),
    );
    session.dispose();
  });

  testWidgets('跳转 CFI 后滚动到目标行而非页首', (tester) async {
    final source = _CfiPageSource();
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'scroll-cfi',
    );
    await session.open();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 480,
          child: AnimatedBuilder(
            animation: session,
            builder: (context, _) => ContinuousScrollView(
              session: session,
              revision: 1,
              padding: const EdgeInsets.all(20),
              paperBuilder: (page, size) =>
                  const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () =>
          find.byKey(const ValueKey<(int, int)>((0, 5))).evaluate().isNotEmpty,
    );

    final targetPage = source.pages[5];
    final slice = targetPage.slices.first;
    final targetLineIndex = slice.startLine + 1;
    final targetLine = slice.block.layout.lines[targetLineIndex];
    final targetCfi = cfiWithCharOffset(
      'epubcfi(/6/2!/4/2/1:0)',
      targetLine.start,
    );
    await session.jumpToCfi(targetCfi, continuous: true);
    await _pumpUntil(
      tester,
      () =>
          session.progress?.pageIndex == 5 &&
          session.progress?.scrollOffset != null,
    );

    final layout = ScrollChapterLayout.fromPages(0, source.pages);
    var targetY = 0.0;
    for (var i = slice.startLine; i < targetLineIndex; i++) {
      targetY += slice.block.layout.lines[i].height;
    }
    final expected = 20 + layout.offsetOfPage(targetPage.pageIndex) + targetY;
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    await _pumpUntil(tester, () => scrollable.position.pixels > 20);
    expect(scrollable.position.pixels, closeTo(expected, 0.01));
    session.dispose();
  });
}
