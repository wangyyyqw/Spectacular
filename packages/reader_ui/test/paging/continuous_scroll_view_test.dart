import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/scroll_layout.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_ui/paging/continuous_scroll_view.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_core/source/chapter_source.dart';

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
        _pageWithHeight(spineIndex, page, switch (spineIndex) {
          0 => page < 10 ? 300.0 : 320.0,
          1 => 300.0 + page * 20,
          _ => 300.0,
        }),
    ];
  }
}

/// 章尾只有一页的短章，用于复现窗口边缘无法继续向下翻页。
class _ShortTailSource implements ReaderChapterSource {
  final loads = <int>[];

  @override
  int get chapterCount => 3;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    loads.add(spineIndex);
    final count = switch (spineIndex) {
      0 => 3,
      1 => 1,
      _ => 5,
    };
    final height = spineIndex == 1 ? 100.0 : 200.0;
    return [
      for (var page = 0; page < count; page++)
        _pageWithHeight(spineIndex, page, height),
    ];
  }
}

class _MissingScrollSource
    implements ReaderChapterSource, MissingChapterSource {
  final missing = <int>{1, 3};

  @override
  int get chapterCount => 5;

  @override
  bool isChapterMissing(int spineIndex) => missing.contains(spineIndex);

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    if (missing.contains(spineIndex)) return const <PageContent>[];
    return [for (var page = 0; page < 3; page++) _page(spineIndex, page)];
  }
}

/// 延迟指定章节加载，模拟真机补章期间的点击。
class _GatedSource implements ReaderChapterSource {
  _GatedSource(this.inner);

  final _ShortTailSource inner;
  final Completer<void> gate = Completer<void>();
  final int gatedSpine = 2;

  @override
  int get chapterCount => inner.chapterCount;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    if (spineIndex == gatedSpine) await gate.future;
    return inner.loadChapter(spineIndex);
  }
}

class _DelayedNeighbors extends _Source {
  final gate = Completer<void>();
  final requested = <int>[];

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    requested.add(spineIndex);
    if (spineIndex != 2) await gate.future;
    return super.loadChapter(spineIndex);
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
    await _pumpUntil(
      tester,
      () => (restoredScrollable.position.pixels - 9445).abs() < 0.01,
    );
    expect(restoredScrollable.position.pixels, closeTo(9445, 0.01));
    expect(session.progress?.spineIndex, 2);
    expect(session.progress?.pageIndex, 1);
    expect(session.progress?.scrollOffset, 125);
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

    expect(session.progress?.spineIndex, 0);
    expect(session.progress?.pageIndex, 1);
    expect(session.progress?.scrollOffset, 30);
    session.dispose();
  });

  testWidgets('切后台前立即提交连续滚动位置', (tester) async {
    final source = _SingleChapterSource();
    final store = MemoryReaderProgressStore();
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: 'scroll-flush',
      persistInterval: const Duration(minutes: 1),
    );
    await session.open();
    final key = GlobalKey<ContinuousScrollViewState>();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 480,
          child: ContinuousScrollView(
            key: key,
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
    tester.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(350);

    await key.currentState!.flushVisiblePosition();
    await session.flushProgress();

    final saved = await store.load('scroll-flush');
    expect(saved?.pageIndex, 1);
    expect(saved?.scrollOffset, 30);
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
      () => find
          .byKey(const ValueKey<String>('scroll-page-2-0'))
          .evaluate()
          .isNotEmpty,
    );

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    await _pumpUntil(tester, () => scrollable.position.pixels > 9000);
    scrollable.position.jumpTo(80);
    await tester.pump(const Duration(milliseconds: 200));
    await _pumpUntil(tester, () => source.loads.contains(0));
    await _pumpUntil(tester, () => scrollable.position.pixels > 6000);
    await tester.pump(const Duration(milliseconds: 300));

    expect(source.loads, contains(0));
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey<String>('scroll-page-1-0')))
          .dy,
      closeTo(-60, 1),
    );
    session.dispose();
  });

  testWidgets('滚动首屏不等待邻章，补章期间仍可阅读并保存最新位置', (tester) async {
    final source = _DelayedNeighbors();
    final store = MemoryReaderProgressStore();
    await store.save(
      'delayed-neighbors',
      const ReaderProgress(spineIndex: 2, pageIndex: 1, scrollOffset: 125),
    );
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: 'delayed-neighbors',
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
            paperBuilder: (page, size) => ColoredBox(
              key: ValueKey('delayed-${page.spineIndex}-${page.pageIndex}'),
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
    await _pumpUntil(tester, () => source.requested.contains(1));
    expect(source.gate.isCompleted, isFalse);
    expect(
      find.byKey(const ValueKey('continuous-scroll-loading')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('delayed-2-1')), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(session.progress!.pageIndex, greaterThanOrEqualTo(2));
    final before = session.progress;
    source.gate.complete();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(session.progress, before, reason: '补邻章不能把用户新位置还原成开书位置');
    await session.flushProgress();
    session.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('连续滚动只保留视口附近的章节', (tester) async {
    final source = _Source();
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'scroll-window',
    );
    await session.open();
    final key = GlobalKey<ContinuousScrollViewState>();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 480,
          child: ContinuousScrollView(
            key: key,
            session: session,
            revision: 1,
            padding: const EdgeInsets.all(20),
            paperBuilder: (page, size) => ColoredBox(
              key: ValueKey<String>(
                'window-page-${page.spineIndex}-${page.pageIndex}',
              ),
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => key.currentState?.debugLoadedSpineIndices.length == 3,
    );

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    for (var i = 0; i < 8 && !source.loads.contains(4); i++) {
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump(const Duration(milliseconds: 300));
    }
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 300));
    await _pumpUntil(
      tester,
      () => key.currentState?.debugLoadedSpineIndices.contains(1) == false,
    );

    final loaded = key.currentState?.debugLoadedSpineIndices ?? const <int>[];
    expect(loaded, isNot(contains(0)));
    expect(loaded.length, lessThanOrEqualTo(4));
    expect(key.currentState?.debugPageKeyCount, lessThanOrEqualTo(120));
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
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    await _pumpUntil(
      tester,
      () =>
          session.progress?.pageIndex == 5 &&
          session.progress?.scrollOffset != null &&
          scrollable.position.pixels > 100,
    );

    final layout = ScrollChapterLayout.fromPages(0, source.pages);
    var targetY = 0.0;
    for (var i = slice.startLine; i < targetLineIndex; i++) {
      targetY += slice.block.layout.lines[i].height;
    }
    final expected = 20 + layout.offsetOfPage(targetPage.pageIndex) + targetY;
    await _pumpUntil(tester, () => scrollable.position.pixels > 20);
    expect(scrollable.position.pixels, closeTo(expected, 0.01));
    session.dispose();
  });

  testWidgets('视口点击坐标映射到可见页切片的页内坐标', (tester) async {
    final source = _SingleChapterSource();
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'scroll-tap',
    );
    await session.open();
    final key = GlobalKey<ContinuousScrollViewState>();
    PageContent? tappedPage;
    Offset? tappedPosition;

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            height: 480,
            child: ContinuousScrollView(
              key: key,
              session: session,
              revision: 1,
              padding: const EdgeInsets.all(20),
              paperBuilder: (page, size) =>
                  const ColoredBox(color: Colors.white),
              onTapAtPage: (page, position) {
                tappedPage = page;
                tappedPosition = position;
                return true;
              },
            ),
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

    expect(key.currentState?.handleTapAt(const Offset(100, 50)), isTrue);
    expect(tappedPage?.pageIndex, 1);
    expect(tappedPosition, const Offset(80, 80));

    // 滚动后正文会滑入顶部 padding，点击仍应映射到对应页。
    expect(key.currentState?.handleTapAt(const Offset(100, 10)), isTrue);
    expect(tappedPage?.pageIndex, 1);
    expect(tappedPosition, const Offset(80, 40));

    scrollable.position.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(key.currentState?.handleTapAt(const Offset(100, 10)), isFalse);
    session.dispose();
  });

  testWidgets('窗口末尾点击下一页会补齐下一章并继续推进', (tester) async {
    final source = _ShortTailSource();
    final store = MemoryReaderProgressStore();
    await store.save(
      'scroll-tail',
      const ReaderProgress(spineIndex: 0, pageIndex: 0),
    );
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: 'scroll-tail',
    );
    await session.open();
    final key = GlobalKey<ContinuousScrollViewState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            height: 480,
            child: ContinuousScrollView(
              key: key,
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
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(key.currentState?.debugLoadedSpineIndices, <int>[0, 1]);

    for (var step = 0; step < 4; step++) {
      unawaited(key.currentState!.scrollPage(true));
      await tester.pumpAndSettle();
    }
    await tester.pump(const Duration(milliseconds: 200));

    expect(source.loads, contains(2));
    expect(session.progress?.spineIndex, 2);
    session.dispose();
  });

  testWidgets('邻章加载中点击下一页会等加载完成再推进', (tester) async {
    final source = _GatedSource(_ShortTailSource());
    final store = MemoryReaderProgressStore();
    await store.save(
      'scroll-gated',
      const ReaderProgress(spineIndex: 0, pageIndex: 0),
    );
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: 'scroll-gated',
    );
    await session.open();
    final key = GlobalKey<ContinuousScrollViewState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            height: 480,
            child: ContinuousScrollView(
              key: key,
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
      () => key.currentState?.debugLoadedSpineIndices.length == 2,
    );

    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    // 邻章仍在加载，窗口尚未到全书末尾，此时没有书尾恢复留白。
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 200));

    final room = scrollable.position.pixels;
    unawaited(key.currentState!.scrollPage(true));
    await tester.pump(const Duration(milliseconds: 200));
    expect(scrollable.position.pixels, closeTo(room, 0.01), reason: '补章未完成前不动');

    source.gate.complete();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));

    expect(scrollable.position.pixels, greaterThan(room + 300));
    expect(session.progress?.spineIndex, 1);
    session.dispose();
  });

  testWidgets('连续滚动窗口跳过缺章并从最近的后续章节冷开', (tester) async {
    final source = _MissingScrollSource();
    final store = MemoryReaderProgressStore();
    await store.save(
      'scroll-missing',
      const ReaderProgress(spineIndex: 1, pageIndex: 0),
    );
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: 'scroll-missing',
    );
    await session.open();
    expect(session.progress?.spineIndex, 2);
    final key = GlobalKey<ContinuousScrollViewState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            height: 480,
            child: ContinuousScrollView(
              key: key,
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
      () => key.currentState?.debugLoadedSpineIndices.length == 3,
    );
    expect(key.currentState?.debugLoadedSpineIndices, <int>[0, 2, 4]);
    session.dispose();
  });
}
