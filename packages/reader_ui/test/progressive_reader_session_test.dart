import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/source/chapter_source.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/virtual_pager.dart';

import 'support/progressive_source.dart';

Future<ReaderSession> _open(
  ProgressiveTestSource source, {
  int spine = 0,
}) async {
  final store = MemoryReaderProgressStore();
  await store.save('渐进翻页', ReaderProgress(spineIndex: spine, pageIndex: 0));
  final session = ReaderSession(source: source, store: store, bookId: '渐进翻页');
  addTearDown(() async {
    await session.flushProgress();
    session.dispose();
    source.cancelPendingLayouts();
  });
  await session.open();
  return session;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('章内首屏空闲就预排下一章，提前发布和后台补全不改变当前进度', () async {
    final source = ProgressiveTestSource(counts: [20, 6, 1]);
    final session = await _open(source);
    final page = session.page;
    final progress = session.progress;
    expect(await session.prefetchTurnChapter(true), isNull);
    final first = await session.prefetchTurnChapter(true, idle: true);
    expect(first, same(source.chapters[1].first));
    expect(source.requests, [0, 1], reason: '只预排下一章，不遍历后续章节');
    expect(source.handles[1]!.priority, ChapterLayoutPriority.background);
    source.complete(1);
    await Future<void>.delayed(Duration.zero);
    expect(session.isChapterComplete(1), isTrue);
    expect(session.page, same(page));
    expect(session.progress, progress);
    expect(session.pageTurns, 0);
  });

  test('下一章尚无首页时前台接管空闲作业，提升而不重新加载', () async {
    final source = ProgressiveTestSource(initialPages: 0);
    final session = await _open(source);
    final background = session.prefetchTurnChapter(true, idle: true);
    await Future<void>.delayed(Duration.zero);
    expect(source.handles[1]!.priority, ChapterLayoutPriority.background);
    final crossing = session.preparePageTurn(true);
    await Future<void>.delayed(Duration.zero);
    expect(source.handles[1]!.priority, ChapterLayoutPriority.reading);
    source.publish(1, 1);
    final turn = (await crossing)!;
    expect(await background, same(turn.target.content));
    expect(source.requests, [0, 1]);
    expect(session.commitPageTurn(turn), isTrue);
    source.complete(1);
  });

  test('首页可准备并提交，追加不改变动画代次、页身份或提前标记读完', () async {
    final source = ProgressiveTestSource();
    final session = await _open(source);
    final first = await session.prefetchTurnChapter(true);
    expect(source.handles[1]!.isComplete, isFalse);
    final turn = (await session.preparePageTurn(true))!;
    final revisions = (
      session.generation,
      session.navigationRevision,
      session.layoutRevision,
    );
    final available = session.availablePagesRevision;
    final pageCounts = session.pageCountRevision;
    source.publish(1, 3);
    expect((
      session.generation,
      session.navigationRevision,
      session.layoutRevision,
    ), revisions);
    expect(session.availablePagesRevision, greaterThan(available));
    expect(session.pageCountRevision, pageCounts);
    expect(session.commitPageTurn(turn), isTrue);
    expect(session.page, same(first));
    expect(session.chapterPageCount, 0);
    expect(session.pageLabelOf(session.page!), '第 1 页');
    expect(session.progress!.finished, isFalse);
    final next = await session.preparePageTurn(true);
    expect(next!.target.pageIndex, 1);
    expect(session.commitPageTurn(next), isTrue);
    source.complete(1);
    await Future<void>.delayed(Duration.zero);
    expect(session.chapterPageCount, 6);
    expect(session.pageLabelOf(session.page!), '2/6');
    expect(session.pageCountRevision, pageCounts + 1);
    expect(source.requests, [0, 1]);
  });

  test('总数确定后立即显示，页界通知不改变页面、阅读进度或整章完成状态', () async {
    final source = ProgressiveTestSource();
    final session = await _open(source, spine: 1);
    final page = session.page;
    final progress = session.progress;
    final revisions = (
      session.generation,
      session.navigationRevision,
      session.layoutRevision,
    );
    source.publishPageCount(1);
    expect(session.chapterPageCount, 6);
    expect(session.pageLabelOf(page!), '1/6');
    expect(session.pageCountRevision, 1);
    expect(session.isChapterComplete(1), isFalse);
    expect(session.page, same(page));
    expect(session.progress, progress);
    expect(session.progress!.finished, isFalse);
    expect((
      session.generation,
      session.navigationRevision,
      session.layoutRevision,
    ), revisions);
    source.complete(1);
    await Future<void>.delayed(Duration.zero);
    expect(session.isChapterComplete(1), isTrue);
    expect(session.pageCountRevision, 1, reason: '缓存收尾不重复刷新同一总数');
  });

  test('已发布末页等待同章追加并提升优先级，不跳到下一章', () async {
    final source = ProgressiveTestSource();
    final session = await _open(source, spine: 1);
    final original = session.page;
    var finished = false;
    final next = session.next().then((moved) {
      finished = true;
      return moved;
    });
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    expect(session.page, same(original));
    expect(source.handles[1]!.priority, ChapterLayoutPriority.reading);
    expect(source.requests, [1]);
    source.publish(1, 2);
    expect(await next, isTrue);
    expect(session.page!.spineIndex, 1);
    expect(session.page!.pageIndex, 1);
    expect(source.handles[1]!.priority, ChapterLayoutPriority.background);
    source.complete(1);
  });

  test('书尾未完成时仍可向后翻，完成前总页数与读完状态不成立', () async {
    final source = ProgressiveTestSource(counts: [6], heldSpines: {0});
    final session = await _open(source);
    expect(session.progress!.finished, isFalse);
    final pager = VirtualPager(
      spineCount: 1,
      loader: source.loadChapter,
      progressiveLoader: (spine, priority) =>
          source.scheduleProgressiveChapter(spine, priority: priority),
    );
    await pager.initialize();
    expect(pager.hasNext, isTrue);
    source.complete(0);
    await session.next();
    expect(session.progress!.finished, isFalse);
  });

  test('反向跨章等待上一章真实末页，不能回到临时前缀末页', () async {
    final source = ProgressiveTestSource();
    final session = await _open(source, spine: 2);
    var ready = false;
    final pending = session.preparePageTurn(false).then((turn) {
      ready = true;
      return turn;
    });
    await Future<void>.delayed(Duration.zero);
    expect(ready, isFalse);
    expect(source.requests, [2, 1]);
    source.complete(1);
    final turn = (await pending)!;
    expect(turn.target.spineIndex, 1);
    expect(turn.target.pageIndex, 5);
    expect(session.commitPageTurn(turn), isTrue);
  });

  test('复制和滚动消费者等待完整章节', () async {
    final source = ProgressiveTestSource();
    final session = await _open(source, spine: 1);
    var ready = false;
    final pages = session.chapterPages().then((value) {
      ready = true;
      return value;
    });
    final scroll = session.loadScrollChapter(1);
    await Future<void>.delayed(Duration.zero);
    expect(ready, isFalse);
    source.complete(1);
    expect(await pages, hasLength(6));
    expect((await scroll).segments, hasLength(6));
    expect(session.page!.pageIndex, 0);
  });

  test('尚未发布的 CFI 等完整正文后准确定位，避免退到临时末页', () async {
    final source = ProgressiveTestSource();
    final session = await _open(source);
    final jump = session.jumpToCfi(progressiveCfi(1, 4));
    await Future<void>.delayed(Duration.zero);
    expect(session.jumpLoadingTitle, isNotNull);
    source.complete(1);
    expect(await jump, isTrue);
    expect(session.page!.pageIndex, 4);
    expect(session.readingCfi, progressiveCfi(1, 4));
  });

  test('取消后台余章后重启继续同章，已显示页保留身份', () async {
    final source = ProgressiveTestSource();
    final session = await _open(source, spine: 1);
    final first = session.page;
    final original = source.handles[1]!;
    source.publishPageCount(1);
    session.cancelPendingLoads();
    expect(original.cancelled, isTrue);
    expect(session.page, same(first));
    final next = session.next();
    await Future<void>.delayed(Duration.zero);
    expect(source.handles[1], isNot(same(original)));
    expect(source.handles[1]!.pageCount, isNull);
    expect(session.chapterPageCount, 6, reason: '同版面重试保留已确定总数');
    source.complete(1);
    expect(await next, isTrue);
    await session.previous();
    expect(session.page, same(first));
  });

  test('准确总数移出章节页窗口后仍可复用', () async {
    final source = ProgressiveTestSource(
      counts: [2, 3, 4, 5, 6, 7],
      heldSpines: {},
    );
    final pager = VirtualPager(
      spineCount: source.chapterCount,
      loader: source.loadChapter,
      progressiveLoader: (spine, priority) =>
          source.scheduleProgressiveChapter(spine, priority: priority),
    );
    await pager.initialize();
    for (var spine = 1; spine < source.chapterCount; spine++) {
      expect(await pager.goTo(spine, 0), isTrue);
    }
    expect(pager.loadedSpines, isNot(contains(0)));
    expect(pager.pageCountOf(0), 2);
    expect(pager.loadedSpines, hasLength(VirtualPager.loadedSpineLimit));
    source.cancelPendingLayouts();
  });

  test('空首批仍等待正文，不能视为空章跳过', () async {
    final source = ProgressiveTestSource(initialPages: 0);
    final session = await _open(source);
    var ready = false;
    final pending = session.preparePageTurn(true).then((turn) {
      ready = true;
      return turn;
    });
    await Future<void>.delayed(Duration.zero);
    expect(ready, isFalse);
    expect(source.requests, [0, 1]);
    source.publish(1, 1);
    final turn = (await pending)!;
    expect(turn.target.spineIndex, 1);
    expect(turn.target.pageIndex, 0);
    source.complete(1);
  });
}
