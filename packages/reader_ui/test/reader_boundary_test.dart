import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_core/source/chapter_source.dart';

import 'support/progressive_source.dart';

/// 章节页数：0 章 2 页、1 章空、2 章 1 页。
class _BoundarySource implements ReaderChapterSource {
  @override
  int get chapterCount => 3;

  final Map<int, int> pageCounts = <int, int>{0: 2, 1: 0, 2: 1};

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    final count = pageCounts[spineIndex] ?? 0;
    return <PageContent>[
      for (var page = 0; page < count; page++)
        PageContent(
          spineIndex: spineIndex,
          pageIndex: page,
          slices: const <PageBlockSlice>[],
          usedHeight: 0,
          pageHeight: 100,
          topPadding: 0,
        ),
    ];
  }
}

/// 0、1 章各一页，其后章节均为空。
class _TrailingEmptySource implements ReaderChapterSource {
  _TrailingEmptySource({this.emptyChapters = 1});

  final int emptyChapters;

  @override
  int get chapterCount => 2 + emptyChapters;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    if (spineIndex >= 2) {
      return const <PageContent>[];
    }
    return <PageContent>[
      PageContent(
        spineIndex: spineIndex,
        pageIndex: 0,
        slices: const <PageBlockSlice>[],
        usedHeight: 0,
        pageHeight: 100,
        topPadding: 0,
      ),
    ];
  }
}

class _FinishStore extends MemoryReaderProgressStore {
  Future<void> Function(ReaderProgress)? beforeFinish;

  @override
  Future<void> save(String bookId, ReaderProgress progress) async {
    if (progress.finished) await beforeFinish?.call(progress);
    await super.save(bookId, progress);
  }
}

ReaderSession _session(_BoundarySource source, [ReaderProgressStore? store]) =>
    ReaderSession(
      source: source,
      store: store ?? MemoryReaderProgressStore(),
      bookId: 'boundary',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('关闭自动读完后到达末页和继续翻页均不标记，也不产生人工尾页', () async {
    final session = ReaderSession(
      source: _BoundarySource(),
      store: MemoryReaderProgressStore(),
      bookId: '手动确认书尾',
      autoFinish: false,
    );
    addTearDown(session.dispose);
    await session.open();
    expect(session.atBookEnd, isFalse);

    await session.next();
    await session.next();
    final lastPage = session.page;
    final lastProgress = session.progress;
    expect(lastProgress, const ReaderProgress(spineIndex: 2, pageIndex: 0));
    expect(session.atBookEnd, isTrue);

    expect(await session.preparePageTurn(true), isNull);
    expect(await session.next(), isFalse);
    expect(session.page, same(lastPage));
    expect(session.progress, lastProgress);
    expect(session.pageTurns, 2);
    await session.flushProgress();
    expect(await session.store.load(session.bookId), lastProgress);
  });

  for (final withReview in [false, true]) {
    final action = withReview ? '连同书评保存' : '只保存读完';
    test('$action成功前不提前完成，正文锚点不变且回翻保留完成状态', () async {
      final source = ProgressiveTestSource(counts: [2], heldSpines: {});
      final store = _FinishStore();
      final session = ReaderSession(
        source: source,
        store: store,
        bookId: action,
        contentRevision: '正文版本',
        autoFinish: false,
      );
      addTearDown(() {
        session.dispose();
        source.cancelPendingLayouts();
      });
      await session.open();
      await session.next();
      final cfi = cfiWithCharOffset(progressiveCfi(0, 1), 4);
      await session.commitScrollPosition(0, 1, 12, cfi: cfi);
      await session.flushProgress();
      final lastPage = session.page;
      final lastProgress = session.progress!;
      expect(lastProgress.cfi, cfi);
      expect(lastProgress.finished, isFalse);
      expect(await session.preparePageTurn(true), isNull);
      expect(await session.next(), isFalse);
      expect(session.page, same(lastPage));
      expect(session.progress, lastProgress);

      final gate = Completer<void>();
      ReaderProgress? submitted;
      Future<void> waitForSave(ReaderProgress progress) async {
        submitted = progress;
        await gate.future;
      }

      if (!withReview) store.beforeFinish = waitForSave;
      final saving = session.markFinished(
        saveWithReview: withReview
            ? (progress) async {
                await waitForSave(progress);
                await store.save(session.bookId, progress);
              }
            : null,
      );
      await Future<void>.delayed(Duration.zero);
      expect(submitted, lastProgress.withFinished(true));
      expect(session.progress, lastProgress);
      expect(await store.load(session.bookId), lastProgress);

      gate.complete();
      await saving;
      expect(session.page, same(lastPage));
      expect(session.readingCfi, cfi);
      expect(session.progress, lastProgress.withFinished(true));
      expect(await store.load(session.bookId), lastProgress.withFinished(true));
      expect(await session.previous(), isTrue);
      expect(session.progress?.pageIndex, 0);
      expect(session.progress?.finished, isTrue);
      await session.flushProgress();
      expect((await store.load(session.bookId))?.finished, isTrue);
    });

    test('$action失败后仍在读并保留正文位置，允许显式重试', () async {
      final store = _FinishStore();
      final session = ReaderSession(
        source: _BoundarySource(),
        store: store,
        bookId: '$action失败重试',
        autoFinish: false,
      );
      addTearDown(session.dispose);
      await session.open();
      await session.next();
      await session.next();
      await session.flushProgress();
      final lastPage = session.page;
      final lastProgress = session.progress!;
      final failure = StateError('保存失败');
      var attempts = 0;
      Future<void> failFirstSave(ReaderProgress progress) async {
        expect(progress, lastProgress.withFinished(true));
        attempts += 1;
        if (attempts == 1) throw failure;
      }

      if (!withReview) store.beforeFinish = failFirstSave;
      Future<void> save() => session.markFinished(
        saveWithReview: withReview
            ? (progress) async {
                await failFirstSave(progress);
                await store.save(session.bookId, progress);
              }
            : null,
      );

      await expectLater(save(), throwsA(same(failure)));
      expect(session.page, same(lastPage));
      expect(session.progress, lastProgress);
      expect(await store.load(session.bookId), lastProgress);
      await save();
      expect(attempts, 2);
      expect(session.progress, lastProgress.withFinished(true));
      expect(await store.load(session.bookId), lastProgress.withFinished(true));
    });
  }

  test('关闭自动读完时仅在多个尾部空章确认后识别书尾，探测不覆盖正文位置', () async {
    final session = ReaderSession(
      source: _TrailingEmptySource(emptyChapters: 3),
      store: MemoryReaderProgressStore(),
      bookId: '多个尾部空章',
      autoFinish: false,
    );
    addTearDown(session.dispose);
    await session.open();
    await session.next();
    final lastPage = session.page;
    final lastProgress = session.progress;
    expect(session.atBookEnd, isFalse, reason: '尚未加载的尾章不能当成已确认的书尾');

    expect(await session.preparePageTurn(true), isNull);
    expect(session.atBookEnd, isTrue);
    expect(session.page, same(lastPage));
    expect(session.progress, lastProgress);
    expect(lastProgress, const ReaderProgress(spineIndex: 1, pageIndex: 0));
    await session.markFinished();
    expect(session.progress?.finished, isTrue);
    expect(session.page, same(lastPage));
  });

  test('章尾翻页进入下一章，页码从 0 开始且 progress 不回跳', () async {
    final session = _session(_BoundarySource());
    await session.open();
    expect(session.progress, const ReaderProgress(spineIndex: 0, pageIndex: 0));

    await session.next();
    expect(session.progress, const ReaderProgress(spineIndex: 0, pageIndex: 1));

    await session.next();
    expect(
      session.progress,
      const ReaderProgress(spineIndex: 2, pageIndex: 0, finished: true),
      reason: '空章 1 应被跳过，页码从 0 开始',
    );

    expect(await session.next(), isFalse, reason: '末页不再前进');
    expect(
      session.progress,
      const ReaderProgress(spineIndex: 2, pageIndex: 0, finished: true),
    );
    session.dispose();
  });

  test('章首向前翻页回到上一章末页', () async {
    final session = _session(_BoundarySource());
    await session.open();
    await session.next();
    await session.next();
    expect(session.progress!.spineIndex, 2);

    expect(await session.previous(), isTrue);
    expect(
      session.progress,
      const ReaderProgress(spineIndex: 0, pageIndex: 1, finished: true),
      reason: '跳过空章 1，回到章 0 末页，已读完状态独立保留',
    );
    session.dispose();
  });

  test('恢复到空章时落到下一个有内容章节', () async {
    final store = MemoryReaderProgressStore();
    await store.save(
      'boundary',
      const ReaderProgress(spineIndex: 1, pageIndex: 0),
    );
    final session = _session(_BoundarySource(), store);
    await session.open();

    expect(session.page, isNotNull, reason: '不应停在空白页');
    expect(
      session.progress,
      const ReaderProgress(spineIndex: 2, pageIndex: 0),
      reason: '恢复时跳过空章不算真实导航，保留原在读状态',
    );
    await session.previous();
    await session.next();
    expect(session.progress!.finished, isTrue, reason: '真实导航返回末页后可标为读完');
    session.dispose();
  });

  test('末尾空章被跳过后仍能识别全书完成', () async {
    final session = ReaderSession(
      source: _TrailingEmptySource(),
      store: MemoryReaderProgressStore(),
      bookId: 'trailing-empty',
    );
    await session.open();
    await session.next();
    expect(session.progress?.finished, isFalse, reason: '末尾章节尚未确认');

    expect(await session.next(), isFalse);
    expect(
      session.progress,
      const ReaderProgress(spineIndex: 1, pageIndex: 0, finished: true),
    );
    session.dispose();
  });

  test('恢复为已读完后回翻仍保持读完标记', () async {
    final store = MemoryReaderProgressStore();
    await store.save(
      'boundary',
      const ReaderProgress(spineIndex: 2, pageIndex: 0, finished: true),
    );
    final session = _session(_BoundarySource(), store);
    await session.open();
    expect(session.progress?.finished, isTrue);

    await session.previous();
    expect(session.progress?.finished, isTrue, reason: '手动读完标记不应因回翻而丢失');
    session.dispose();
  });
}
