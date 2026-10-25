import 'package:reader_ui/reader_session.dart';

import 'chapter_text.dart';
import 'search_index_store.dart';

/// 2-gram 索引构建任务（P4-24，§66.1）：逐章写入，可中断续建。
///
/// 每章一个事务（原文 + gram 一起提交），因此「最后写入的 spine」就是可靠
/// 断点；重跑时从下一章继续，不会重复也不会漏。
class SearchIndexer {
  /// 创建索引任务。
  SearchIndexer({required this.source, required this.store});

  /// 章节来源。
  final ReaderChapterSource source;

  /// 索引存储。
  final SearchIndexStore store;

  /// 建索引：从断点续建到最后一章，返回本次新增章数。
  ///
  /// [onProgress] 回调 (已完成章数, 总章数)。
  Future<int> build(
    int bookId, {
    void Function(int done, int total)? onProgress,
  }) async {
    final total = source.chapterCount;
    final lastIndexed = await store.lastIndexedSpine(bookId);
    final startSpine = lastIndexed == null ? 0 : lastIndexed + 1;
    if (startSpine >= total) {
      return 0;
    }
    var charStart = await store.indexedCharCount(bookId);
    var done = 0;
    for (var spine = startSpine; spine < total; spine++) {
      final text = await _plainTextOf(spine);
      await store.saveChapter(
        bookId: bookId,
        spineIndex: spine,
        text: text,
        charStart: charStart,
      );
      charStart += text.length;
      done++;
      onProgress?.call(spine + 1, total);
    }
    return done;
  }

  /// 章节纯文本（§66.1：块间插 `\n`，同块多页切片只取一次）。
  ///
  /// 与查询期定位共用 [ChapterText]，保证索引偏移与命中定位一致。
  Future<String> _plainTextOf(int spineIndex) async {
    final pages = await source.loadChapter(spineIndex);
    return ChapterText.fromPages(pages).text;
  }
}
