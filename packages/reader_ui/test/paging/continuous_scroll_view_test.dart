import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
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
  Future<List<PageContent>> loadChapter(int spineIndex) async =>
      [for (var page = 0; page < 3; page++) _page(spineIndex, page)];
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
    await store.save('scroll', const ReaderProgress(spineIndex: 2, pageIndex: 1));
    final session = ReaderSession(source: source, store: store, bookId: 'scroll');
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
    expect(find.byKey(const ValueKey<String>('scroll-page-2-1')), findsOneWidget);
    expect(session.progress, const ReaderProgress(spineIndex: 2, pageIndex: 1));
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
    final session = ReaderSession(source: source, store: store, bookId: 'progress');
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

    expect(session.progress, const ReaderProgress(spineIndex: 0, pageIndex: 1));
    session.dispose();
  });
}
