import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
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
    expect(visited.last, const ReaderProgress(spineIndex: 29, pageIndex: 1));
    expect(session.currentVirtualPage, 59);
    expect(await session.next(), isFalse);

    // P4-10：进度写入节流，测试里显式落盘再断言。
    await session.flushProgress();
    final saved = await store.load('book-1');
    expect(saved, const ReaderProgress(spineIndex: 29, pageIndex: 1));

    final restored = ReaderSession(
      source: source,
      store: store,
      bookId: 'book-1',
    );
    await restored.open();
    expect(
      restored.progress,
      const ReaderProgress(spineIndex: 29, pageIndex: 1),
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
    expect(find.byKey(const ValueKey<String>('reader-jump-loading')), findsNothing);

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
