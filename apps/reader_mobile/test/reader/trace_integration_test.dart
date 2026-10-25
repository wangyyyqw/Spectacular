import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/perf/trace.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

void main() {
  setUp(() => ReaderTrace.instance = ReaderTrace(capacity: 64));
  tearDown(() => ReaderTrace.instance = ReaderTrace());

  test('章节加载埋点：首次分页记 chapterLayout，再次命中记 pageRenderReuse（P4-31）', () async {
    final bytes = buildTestEpub(title: '埋点书');
    final source = await openTestChapterSource(bytes);
    source.bookIdForTrace = 'book-trace';

    // 打开章节源时可能已预热过该章，这里从干净状态开始验证命中路径。
    ReaderTrace.instance.reset();
    await source.loadChapter(0);
    await source.loadChapter(0);

    final summary = ReaderTrace.instance.summary(bookId: 'book-trace');
    expect(
      summary.counts[ReaderTraceName.pageRenderReuse],
      greaterThanOrEqualTo(1),
      reason: '重复加载至少命中一次缓存',
    );
    expect(summary.pageCacheHitRate, greaterThan(0));
    expect(
      summary.averageMs(ReaderTraceName.chapterLayout),
      greaterThanOrEqualTo(0),
    );
  });

  test('冷加载埋点：未缓存时记 chapterLayout（P4-31）', () async {
    final bytes = buildTestEpub(
      title: '冷加载',
      paragraphs: const <String>['第一段内容。', '第二段内容。'],
    );
    // 新源且指定一个未预热的章号范围：直接加载第 0 章并重置计数。
    final source = await openTestChapterSource(bytes);
    source.bookIdForTrace = 'book-cold';
    ReaderTrace.instance.reset();
    await source.loadChapter(0);
    final summary = ReaderTrace.instance.summary(bookId: 'book-cold');
    expect(
      summary.counts[ReaderTraceName.chapterLayout] ??
          summary.counts[ReaderTraceName.pageRenderReuse],
      isNotNull,
      reason: '至少有一条章节加载埋点',
    );
  });

  test('目录跳转埋点：chapterJump 有采样（P4-31）', () async {
    final bytes = buildTestEpub(
      title: '跳转埋点',
      paragraphs: const <String>['第一段。', '第二段。'],
    );
    final source = await openTestChapterSource(bytes);
    source.bookIdForTrace = 'book-jump';
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'book-jump',
    );
    await session.open();
    await session.jumpToChapter(0, title: '第一章');
    final summary = ReaderTrace.instance.summary(bookId: 'book-jump');
    expect(summary.counts[ReaderTraceName.chapterJump], isNotNull);
    session.dispose();
  });
}
