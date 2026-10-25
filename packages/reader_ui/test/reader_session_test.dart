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
  FakeSource({this.chapterCount = 30, this.pagesPerChapter = 2});
  @override
  final int chapterCount;
  final int pagesPerChapter;
  final List<int> loads = <int>[];

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    loads.add(spineIndex);
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
