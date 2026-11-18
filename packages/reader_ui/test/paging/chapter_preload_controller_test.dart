import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/paging/chapter_preload_controller.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/progressive_source.dart';

void main() {
  testWidgets('内容预排独立于位图视口，计数和暂停恢复不重复加载同一章', (tester) async {
    final source = ProgressiveTestSource(counts: [20, 6, 1]);
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: '独立预排',
    );
    await session.open();
    var ready = 0;
    final controller = ChapterPreloadController(
      session,
      onFirstPage: () => ready++,
    );
    controller.update(paused: false);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(source.requests, [0, 1]);
    expect(controller.firstPage, same(source.chapters[1].first));
    expect(ready, 1);
    final pagesRevision = session.availablePagesRevision;
    source.publishPageCount(1);
    expect(session.availablePagesRevision, pagesRevision);
    controller.update(paused: true);
    expect(source.backgroundPaused, isTrue);
    controller.update(paused: false);
    await tester.pump(const Duration(milliseconds: 150));
    expect(source.requests, [0, 1]);
    expect(ready, 1);
    expect(source.backgroundPaused, isFalse);
    controller.dispose();
    await session.flushProgress();
    session.dispose();
    source.cancelPendingLayouts();
  });
}
