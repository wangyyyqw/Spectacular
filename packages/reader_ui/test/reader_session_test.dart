import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_ui/paging/continuous_scroll_view.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

PageContent _makePage(int spine, int page) {
  final layout = TextLayoutEngine.layout(
    text: '第$spine章 第$page页',
    style: _style(),
    maxWidth: 280,
  );
  return PageContent(
    spineIndex: spine,
    pageIndex: page,
    slices: <PageBlockSlice>[
      PageBlockSlice(
        block: PageBlock(layout: layout, style: _style()),
        startLine: 0,
        endLine: layout.lineCount,
        height: layout.height,
      ),
    ],
    usedHeight: layout.height,
    pageHeight: 200,
    topPadding: 0,
  );
}

class FakeSource implements ReaderChapterSource {
  FakeSource({
    this.chapterCount = 30,
    this.pagesPerChapter = 2,
    this.delay = Duration.zero,
  });
  @override
  final int chapterCount;
  final int pagesPerChapter;
  final Duration delay;
  final List<int> loads = <int>[];

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    loads.add(spineIndex);
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return <PageContent>[
      for (var i = 0; i < pagesPerChapter; i++) _makePage(spineIndex, i),
    ];
  }
}

class _MultiLineSource implements ReaderChapterSource {
  _MultiLineSource() {
    final style = ComputedStyle(const <String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'white-space': 'pre-wrap',
    });
    final layout = TextLayoutEngine.layout(
      text: '第一行\n第二行\n第三行\n第四行\n第五行\n第六行\n第七行\n第八行',
      style: style,
      maxWidth: 400,
    );
    pages = Paginator(pageHeight: 48)
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

void main() {
  test('30 章整书翻页、章节切换、进度恢复', () async {
    final source = FakeSource();
    final store = MemoryReaderProgressStore();
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: 'book-1',
    );
    await session.open();
    expect(session.page, isNotNull);
    expect(session.currentText, contains('第0章'));
    expect(session.progress, const ReaderProgress(spineIndex: 0, pageIndex: 0));

    final visited = <ReaderProgress>[];
    visited.add(session.progress!);
    while (await session.next()) {
      final progress = session.progress!;
      visited.add(progress);
      expect(session.page, isNotNull);
      expect(session.currentText.trim(), isNotEmpty);
    }
    expect(visited, hasLength(60));
    expect(visited.map((p) => p.spineIndex).toSet(), hasLength(30));
    expect(visited.first, const ReaderProgress(spineIndex: 0, pageIndex: 0));
    expect(
      visited.last,
      const ReaderProgress(spineIndex: 29, pageIndex: 1, finished: true),
    );
    expect(session.currentVirtualPage, 59);
    expect(await session.next(), isFalse);

    // P4-10：进度写入节流，测试里显式落盘再断言。
    await session.flushProgress();
    final saved = await store.load('book-1');
    expect(
      saved,
      const ReaderProgress(spineIndex: 29, pageIndex: 1, finished: true),
    );

    final restored = ReaderSession(
      source: source,
      store: store,
      bookId: 'book-1',
    );
    await restored.open();
    expect(
      restored.progress,
      const ReaderProgress(spineIndex: 29, pageIndex: 1, finished: true),
    );
    expect(restored.currentText, contains('第29章'));
  });

  test('目录跳转：jumpToChapter 定位到目标章首屏（P4-11）', () async {
    final session = ReaderSession(
      source: FakeSource(),
      store: MemoryReaderProgressStore(),
      bookId: 'toc-book',
    );
    await session.open();
    expect(session.progress, const ReaderProgress(spineIndex: 0, pageIndex: 0));

    expect(await session.jumpToChapter(5), isTrue);
    expect(session.progress, const ReaderProgress(spineIndex: 5, pageIndex: 0));
    expect(session.page, isNotNull);
    expect(
      session.currentVirtualPage,
      2,
      reason: '只映射已加载的第 0、5 章，不为窗口页码排版中间章节',
    );

    // 越界章节不动（pager 返回 false）。
    expect(await session.jumpToChapter(99), isFalse);
    expect(session.progress?.spineIndex, 5);
    session.dispose();
  });

  test('连续跳转只保留最后一次结果（token 防竞态，P4-12）', () async {
    final session = ReaderSession(
      source: FakeSource(delay: const Duration(milliseconds: 20)),
      store: MemoryReaderProgressStore(),
      bookId: 'race-book',
    );
    await session.open();

    final first = session.jumpToChapter(5, title: '第五章');
    final second = session.jumpToChapter(20, title: '第二十章');
    expect(await first, isFalse, reason: '先发的跳转结果被丢弃');
    expect(await second, isTrue);
    expect(session.progress?.spineIndex, 20, reason: '最终停在最后一次目标');
    expect(session.jumpLoadingTitle, isNull);
    session.dispose();
  });

  test('跳转期间暴露目标章名，完成后清空（P4-12 浮层）', () async {
    final session = ReaderSession(
      source: FakeSource(delay: const Duration(milliseconds: 30)),
      store: MemoryReaderProgressStore(),
      bookId: 'loading-book',
    );
    await session.open();
    expect(session.jumpLoadingTitle, isNull);

    final pending = session.jumpToChapter(7, title: '第七章 出发');
    expect(session.jumpLoadingTitle, '第七章 出发');
    await pending;
    expect(session.jumpLoadingTitle, isNull);
    expect(session.progress?.spineIndex, 7);
    session.dispose();
  });

  test('章节源无目录能力时 toc 为空', () async {
    final session = ReaderSession(
      source: FakeSource(),
      store: MemoryReaderProgressStore(),
      bookId: 'no-toc',
    );
    await session.open();
    expect(session.toc, isEmpty);
    session.dispose();
  });

  test('恢复后回到首页 previous 停止', () async {
    final source = FakeSource();
    final store = MemoryReaderProgressStore();
    final first = ReaderSession(source: source, store: store, bookId: 'b');
    await first.open();
    while (await first.next()) {}
    final restored = ReaderSession(source: source, store: store, bookId: 'b');
    await restored.open();
    while (await restored.previous()) {}
    expect(
      restored.progress,
      const ReaderProgress(spineIndex: 0, pageIndex: 0),
    );
    expect(await restored.previous(), isFalse);
  });

  test('连续滚动加载整章并同步当前页', () async {
    final session = ReaderSession(
      source: FakeSource(),
      store: MemoryReaderProgressStore(),
      bookId: 'scroll-sync',
    );
    await session.open();

    expect(session.pageTurns, 0);
    expect(session.charactersRead, 0);
    expect(await session.commitScrollPosition(1, 1, 42.5), isTrue);
    expect(session.pageTurns, 1);
    expect(session.charactersRead, 6);
    await session.flushProgress();
    expect(
      await session.store.load('scroll-sync'),
      const ReaderProgress(spineIndex: 1, pageIndex: 1, scrollOffset: 42.5),
    );
  });

  test('连续滚动跳转 CFI 定位到目标页内行', () async {
    final source = _MultiLineSource();
    final store = MemoryReaderProgressStore();
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: 'scroll-cfi',
    );
    addTearDown(session.dispose);
    await session.open();

    expect(source.pages.length, greaterThan(1));
    final targetPage = source.pages[1];
    final slice = targetPage.slices.first;
    final targetLine = slice.block.layout.lines[slice.startLine + 1];
    final targetCfi = cfiWithCharOffset(
      'epubcfi(/6/2!/4/2/1:0)',
      targetLine.start,
    );

    expect(await session.jumpToCfi(targetCfi, continuous: true), isTrue);
    expect(session.progress!.pageIndex, 1);
    expect(session.progress!.scrollOffset, closeTo(targetLine.height, 0.01));

    await session.jumpToCfi(cfiWithCharOffset(targetCfi, 0));
    expect(session.progress!.scrollOffset, isNull);
  });

  test('连续滚动当前 CFI 跟随视口顶部可见行', () async {
    final source = _MultiLineSource();
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'scroll-current-cfi',
    );
    addTearDown(session.dispose);
    await session.open();

    await session.commitScrollPosition(0, 0, 0);
    final firstLineCfi = session.currentCfi;
    expect(session.currentLineText, '第一行');

    final secondLineHeight =
        source.pages[0].slices.first.block.layout.lines[0].height;
    await session.commitScrollPosition(0, 0, secondLineHeight);
    final secondLineCfi = session.currentCfi;
    expect(session.currentLineText, '第二行');
    expect(secondLineCfi, isNotNull);
    expect(secondLineCfi, isNot(firstLineCfi));

    await session.commitScrollPosition(0, 0, 0);
    await session.jumpToCfi(secondLineCfi!, continuous: true);
    expect(
      session.progress!.scrollOffset,
      closeTo(secondLineHeight, 0.01),
    );
    expect(session.currentLineText, '第二行');

    // 真实滚动容器会把行首坐标量化到略小于理论值，仍应命中该行。
    await session.commitScrollPosition(0, 0, secondLineHeight - 1e-9);
    expect(session.currentLineText, '第二行');
  });

  test('翻页准备不修改进度，收尾只提交一次', () async {
    final session = ReaderSession(
      source: FakeSource(),
      store: MemoryReaderProgressStore(),
      bookId: 'prepare-turn',
    );
    await session.open();
    final origin = session.page;
    expect(session.pageTurns, 0);
    expect(session.charactersRead, 0);
    final prepared = await session.preparePageTurn(true);

    expect(prepared, isNotNull);
    expect(identical(session.page, origin), isTrue);
    expect(session.progress, const ReaderProgress(spineIndex: 0, pageIndex: 0));

    expect(session.commitPageTurn(prepared!), isTrue);
    expect(session.progress, const ReaderProgress(spineIndex: 0, pageIndex: 1));
    expect(session.pageTurns, 1);
    expect(session.charactersRead, 6);
    expect(session.commitPageTurn(prepared), isFalse);
    expect(session.pageTurns, 1);
    expect(session.charactersRead, 6);
    session.dispose();
  });

  test('目录跳转不计翻页，连续滚动跨页计一次', () async {
    final session = ReaderSession(
      source: FakeSource(),
      store: MemoryReaderProgressStore(),
      bookId: 'count-turns',
    );
    addTearDown(session.dispose);
    await session.open();

    expect(await session.next(), isTrue);
    expect(session.pageTurns, 1);
    expect(await session.jumpToChapter(5), isTrue);
    expect(session.pageTurns, 1);

    expect(await session.commitScrollPosition(5, 1, 0), isTrue);
    expect(session.pageTurns, 2);
    expect(await session.commitScrollPosition(5, 1, 24), isTrue);
    expect(session.pageTurns, 2, reason: '同一页内滚动不算翻页');
    expect(await session.commitScrollPosition(5, 0, 0), isTrue);
    expect(session.pageTurns, 3);
  });

  test('外部跳转后丢弃旧翻页准备结果', () async {
    final session = ReaderSession(
      source: FakeSource(),
      store: MemoryReaderProgressStore(),
      bookId: 'stale-turn',
    );
    await session.open();
    final stale = await session.preparePageTurn(true);
    expect(await session.jumpToChapter(5), isTrue);

    expect(session.commitPageTurn(stale!), isFalse);
    expect(session.progress, const ReaderProgress(spineIndex: 5, pageIndex: 0));
    session.dispose();
  });

  testWidgets('连续滚动视图可翻越页切片并报告当前页', (tester) async {
    final source = FakeSource(pagesPerChapter: 40);
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'scroll-widget',
    );
    await session.open();
    final visible = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 520,
            child: ContinuousScrollView(
              session: session,
              revision: 1,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              onPageVisible: (page) => visible.add(page.pageIndex),
              paperBuilder: (page, size) => Text(page.pageIndex.toString()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('continuous-scroll')),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(const ValueKey<String>('continuous-scroll')),
      const Offset(0, -420),
    );
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pumpAndSettle();

    expect(visible, isNotEmpty);
    expect(session.progress?.pageIndex, greaterThan(0));
    session.dispose();
  });

  testWidgets('分页与连续滚动切换保留同一阅读进度', (tester) async {
    final source = FakeSource(pagesPerChapter: 40);
    final store = MemoryReaderProgressStore();
    late ReaderSession session;
    Widget build(PageTurnMode mode) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            height: 520,
            child: ReaderPage(
              source: source,
              store: store,
              bookId: 'scroll-round-trip',
              pageTurnMode: mode,
              onSessionReady: (value) => session = value,
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(build(PageTurnMode.cover));
    await tester.pumpAndSettle();
    expect(await session.next(), isTrue);
    expect(await session.next(), isTrue);
    await tester.pumpAndSettle();
    expect(session.progress, const ReaderProgress(spineIndex: 0, pageIndex: 2));

    await tester.pumpWidget(build(PageTurnMode.scroll));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('continuous-scroll')),
      findsOneWidget,
    );
    await tester.drag(
      find.byKey(const ValueKey<String>('continuous-scroll')),
      const Offset(0, -220),
    );
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pumpAndSettle();
    final scrolled = session.progress!;
    expect(scrolled.pageIndex, greaterThan(2));

    await tester.pumpWidget(build(PageTurnMode.cover));
    await tester.pumpAndSettle();
    expect(session.progress, scrolled);
    expect(
      find.byKey(
        ValueKey<String>(
          'reader-page-${scrolled.spineIndex}-${scrolled.pageIndex}',
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('跳转时显示目标章名浮层，完成后消失（P4-12）', (tester) async {
    final source = FakeSource(delay: const Duration(milliseconds: 40));
    late ReaderSession session;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 520,
              child: ReaderPage(
                source: source,
                store: MemoryReaderProgressStore(),
                bookId: 'jump-overlay',
                onSessionReady: (value) => session = value,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('reader-jump-loading')),
      findsNothing,
    );

    final pending = session.jumpToChapter(5, title: '第五章 出发');
    await tester.pump();
    expect(find.textContaining('正在打开 第五章 出发'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('reader-jump-loading')),
      findsOneWidget,
    );

    // 推进假时间让加载完成（不能直接 await pending：它等的是 fake timer）。
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    unawaited(pending);
    expect(find.textContaining('正在打开'), findsNothing);
    expect(session.progress?.spineIndex, 5);
  });

  testWidgets('阅读页可绘制并响应翻页', (tester) async {
    final source = FakeSource();
    final store = MemoryReaderProgressStore();
    ReaderSession? session;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 200,
            child: ReaderPage(
              source: source,
              store: store,
              bookId: 'widget-book',
              onSessionReady: (value) => session = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(session, isNotNull);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(
      session!.progress,
      const ReaderProgress(spineIndex: 0, pageIndex: 0),
    );

    final origin = tester.getTopLeft(find.byType(ReaderPage));
    await tester.tapAt(origin + const Offset(270, 100));
    await tester.pumpAndSettle();
    expect(
      session!.progress,
      const ReaderProgress(spineIndex: 0, pageIndex: 1),
    );

    await tester.fling(find.byType(ReaderPage), const Offset(-160, 0), 1000);
    await tester.pumpAndSettle();
    expect(session!.progress!.spineIndex, 1);
    expect(tester.takeException(), isNull);
  });
}
