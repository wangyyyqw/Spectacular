import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_session.dart';

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

PageContent _page(int spine) {
  final layout = TextLayoutEngine.layout(
    text: '第${spine + 1}章',
    style: _style(),
    maxWidth: 280,
  );
  return PageContent(
    spineIndex: spine,
    pageIndex: 0,
    slices: [
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

class _Source implements ReaderChapterSource {
  final List<int> loads = <int>[];

  @override
  int get chapterCount => 3;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    loads.add(spineIndex);
    return [_page(spineIndex)];
  }
}

void main() {
  testWidgets('静止时预热前后章快照且不改变阅读位置', (tester) async {
    final source = _Source();
    final store = MemoryReaderProgressStore();
    await store.save('warm', const ReaderProgress(spineIndex: 1, pageIndex: 0));
    final session = ReaderSession(source: source, store: store, bookId: 'warm');
    await session.open();
    final key = GlobalKey<PageTurnViewState>();
    final built = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 480,
          child: PageTurnView(
            key: key,
            session: session,
            mode: PageTurnMode.cover,
            revision: 1,
            paperBuilder: (page, size) {
              built.add(page.spineIndex);
              return ColoredBox(
                color: const Color(0xFFFFFFFF),
                child: Text('${page.spineIndex}'),
              );
            },
            paperColor: const Color(0xFFFFFFFF),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(source.loads.toSet(), containsAll(<int>[0, 1, 2]));
    expect(built.toSet(), containsAll(<int>[0, 1, 2]));
    expect(key.currentState!.snapshotCount, 3);
    expect(session.progress, const ReaderProgress(spineIndex: 1, pageIndex: 0));
    session.dispose();
  });
}
