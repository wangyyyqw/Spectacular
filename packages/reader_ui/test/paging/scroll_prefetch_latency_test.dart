import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_ui/paging/continuous_scroll_view.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_core/source/chapter_source.dart';

class _Source implements ReaderChapterSource {
  final loads = <int>[];
  @override
  int get chapterCount => 4;
  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    loads.add(spineIndex);
    final style = ComputedStyle(const {'font-size': '16px'});
    final layout = TextLayoutEngine.layout(
      text: '滚动正文',
      style: style,
      maxWidth: 300,
    );
    return [
      for (var i = 0; i < 10; i++)
        PageContent(
          spineIndex: spineIndex,
          pageIndex: i,
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
        ),
    ];
  }
}

void main() {
  testWidgets('滚动余量不足两屏时提前补章，不等抵达半屏才加载', (tester) async {
    final source = _Source();
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: '滚动提前补章',
    );
    await session.open();
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 480,
          child: ContinuousScrollView(
            session: session,
            revision: 1,
            padding: EdgeInsets.zero,
            paperBuilder: (_, _) => const ColoredBox(color: Colors.white),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(source.loads, containsAll([0, 1]));
    expect(source.loads, isNot(contains(2)));
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    scroll.position.jumpTo(scroll.position.maxScrollExtent - 800);
    await tester.pumpAndSettle();
    expect(source.loads, contains(2), reason: '800px 余量仍应提前准备后一章');
    await tester.pumpWidget(const SizedBox.shrink());
    await session.flushProgress();
  });
}
