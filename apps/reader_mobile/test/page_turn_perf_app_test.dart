import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/source/chapter_source.dart';
import 'package:reader_ui/paging/continuous_scroll_view.dart';
import 'package:reader_ui/reader_session.dart';

import '../integration_test/page_turn_perf_app.dart' as perf;

class _Source implements ReaderChapterSource {
  @override
  int get chapterCount => 4;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    final style = ComputedStyle(const {'font-size': '16px'});
    final layout = TextLayoutEngine.layout(
      text: '实际滚动位置',
      style: style,
      maxWidth: 280,
    );
    return [
      for (var page = 0; page < 5; page++)
        PageContent(
          spineIndex: spineIndex,
          pageIndex: page,
          slices: [
            PageBlockSlice(
              block: PageBlock(
                layout: layout,
                style: style,
                startCfi:
                    'epubcfi(/6/${2 + spineIndex * 2}!/4/${2 + page * 2}/1:0)',
              ),
              startLine: 0,
              endLine: layout.lineCount,
              height: 300,
            ),
          ],
          usedHeight: 300,
          pageHeight: 300,
          topPadding: 0,
        ),
    ];
  }
}

void main() {
  testWidgets('翻屏后等待暂未命中的布局，位置变化时重新累计稳定帧', (tester) async {
    final session = ReaderSession(
      source: _Source(),
      store: MemoryReaderProgressStore(),
      bookId: '滚动落页等待',
    );
    await session.open();
    final key = GlobalKey<ContinuousScrollViewState>();
    var complete = false;
    final ready = perf.waitForScrollPerfPosition(() => key.currentState).then((
      value,
    ) {
      complete = true;
      return value;
    });
    await tester.pump();
    expect(complete, isFalse, reason: '没有实际布局时不能直接判定输入失败或采样成功');
    await tester.pumpWidget(
      MaterialApp(
        home: ContinuousScrollView(
          key: key,
          session: session,
          revision: 0,
          padding: const EdgeInsets.only(top: 20),
          paperBuilder: (_, _) => const ColoredBox(color: Colors.white),
        ),
      ),
    );
    for (
      var i = 0;
      i < 15 &&
          (key.currentState == null ||
              perf.readScrollPerfPosition(key.currentState!) == null);
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    scrollable.position.jumpTo(350);
    await tester.pump();
    expect(complete, isFalse);
    scrollable.position.jumpTo(370);
    await tester.pump();
    expect(complete, isFalse);
    await tester.pump();
    expect(complete, isFalse);
    await tester.pump();
    expect(complete, isTrue);
    expect(await ready, (
      spine: 0,
      page: 1,
      offset: 50.0,
    ), reason: '视口 0 命中必须扣除列表顶部20px，而非再加padding');
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });

  testWidgets('滚动采样读取实际切片与偏移，不把延迟会话页当成视口', (tester) async {
    final session = ReaderSession(
      source: _Source(),
      store: MemoryReaderProgressStore(),
      bookId: '滚动采样',
    );
    await session.open();
    final key = GlobalKey<ContinuousScrollViewState>();
    await tester.pumpWidget(
      MaterialApp(
        home: ContinuousScrollView(
          key: key,
          session: session,
          revision: 0,
          padding: EdgeInsets.zero,
          paperBuilder: (_, _) => const ColoredBox(color: Colors.white),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    scrollable.position.jumpTo(350);
    expect(session.page!.pageIndex, 0);
    expect(perf.readScrollPerfPosition(key.currentState!), (
      spine: 0,
      page: 1,
      offset: 50.0,
    ));
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });

  testWidgets('等待跳章拒绝已到目标章的会话，直到实际窗口重建且稳定', (tester) async {
    final session = ReaderSession(
      source: _Source(),
      store: MemoryReaderProgressStore(),
      bookId: '滚动跳章采样',
    );
    await session.open();
    final key = GlobalKey<ContinuousScrollViewState>();
    Widget reader() => MaterialApp(
      home: ContinuousScrollView(
        key: key,
        session: session,
        revision: session.generation,
        padding: EdgeInsets.zero,
        paperBuilder: (_, _) => const ColoredBox(color: Colors.white),
      ),
    );
    await tester.pumpWidget(reader());
    await tester.pumpAndSettle();
    await session.jumpToChapter(2);
    expect(session.page!.spineIndex, 2);
    expect(perf.readScrollPerfPosition(key.currentState!)?.spine, 0);
    var complete = false;
    final ready = perf
        .waitForScrollPerfPosition(() => key.currentState, spine: 2, page: 0)
        .then((value) {
          complete = true;
          return value;
        });
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(complete, isFalse);
    final cfi = session.cfiAtPageOffset(session.page!, null)!;
    await session.jumpToCfi(cfi, continuous: true);
    await tester.pumpWidget(reader());
    for (var i = 0; i < 15 && !complete; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(complete, isTrue);
    final actual = await ready;
    expect(actual.spine, 2);
    expect(actual.page, 0);
    expect(actual.offset, closeTo(0, 0.5));
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });
}
