import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/source/chapter_source.dart';
import 'package:reader_ui/paging/chapter_preload_controller.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/progressive_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('邻章首页已就绪但余章被取消，停留原页也会继续预排总数', () async {
    final source = ProgressiveTestSource(counts: [20, 80, 1]);
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: '长章总数预排',
    );
    await session.open();
    final controller = ChapterPreloadController(session, onFirstPage: () {});
    addTearDown(() {
      controller.dispose();
      session.dispose();
      source.cancelPendingLayouts();
    });
    final original = session.page;
    final progress = session.progress;
    controller.update(paused: false);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final interrupted = source.handles[1]!;
    expect(controller.firstPage, same(source.chapters[1].first));
    expect(session.pageCountOf(1), 0);

    interrupted.cancel();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(source.handles[1], isNot(same(interrupted)));
    expect(source.handles[1]!.priority, ChapterLayoutPriority.background);
    source.publishPageCount(1);
    expect(session.pageCountOf(1), 80, reason: '仍在前一章时接收准确总数');
    expect(session.page, same(original));
    expect(session.progress, progress);
    source.complete(1);
    await Future<void>.delayed(Duration.zero);
    expect(session.isChapterComplete(1), isTrue);
    expect(source.requests, [0, 1, 1], reason: '只恢复被取消的邻章，不预排更远章节');
  });

  test('首页发布后切后台取消余章，回前台原页恢复整章预排', () async {
    final source = ProgressiveTestSource(counts: [20, 80, 1]);
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: '恢复邻章总数预排',
    );
    await session.open();
    final controller = ChapterPreloadController(session, onFirstPage: () {});
    addTearDown(() {
      controller.dispose();
      session.dispose();
      source.cancelPendingLayouts();
    });
    controller.update(paused: false);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final interrupted = source.handles[1]!;
    controller.update(paused: true);
    session.cancelTurnPrefetch();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(interrupted.cancelled, isTrue);
    expect(source.requests, [0, 1], reason: '后台期间不重启预排');

    controller.update(paused: false);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(source.handles[1], isNot(same(interrupted)));
    source.complete(1);
    await Future<void>.delayed(Duration.zero);
    expect(session.pageCountOf(1), 80);
    expect(session.page!.spineIndex, 0);
    expect(source.requests, [0, 1, 1]);
  });

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
