import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/reader_session.dart';

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

/// 0、1 章各一页，末尾第 2 章为空。
class _TrailingEmptySource implements ReaderChapterSource {
  @override
  int get chapterCount => 3;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    if (spineIndex == 2) {
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

ReaderSession _session(_BoundarySource source, [ReaderProgressStore? store]) =>
    ReaderSession(
      source: source,
      store: store ?? MemoryReaderProgressStore(),
      bookId: 'boundary',
    );

void main() {
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
      const ReaderProgress(spineIndex: 0, pageIndex: 1),
      reason: '跳过空章 1，回到章 0 末页',
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
      const ReaderProgress(spineIndex: 2, pageIndex: 0, finished: true),
    );
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
}
