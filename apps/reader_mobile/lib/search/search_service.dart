import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/text/search.dart';
import 'package:reader_ui/reader_session.dart';

import 'chapter_text.dart';
import 'search_index_store.dart';

/// 一条搜索结果（P4-25，§66.5）。
class SearchResult {
  /// 创建结果。
  const SearchResult({
    required this.spineIndex,
    required this.charOffset,
    required this.chapterTitle,
    required this.context,
    required this.matchLength,
    this.cfi,
  });

  /// 章节序号。
  final int spineIndex;

  /// 章内字符偏移（命中起点）。
  final int charOffset;

  /// 章名。
  final String chapterTitle;

  /// 上下文片段（命中前后各约 12 字）。
  final String context;

  /// 命中词长度。
  final int matchLength;

  /// 命中位置的 CFI（块 CFI + 块内偏移）；无法定位时为 null。
  final String? cfi;
}

/// 全文查询与命中定位（P4-25，§66.4～§66.5）。
class SearchService {
  /// 创建服务。
  SearchService({required this.source, required this.store});

  /// 章节来源（定位与上下文用）。
  final ReaderChapterSource source;

  /// 索引存储。
  final SearchIndexStore store;

  /// 上下文半径（§66.5：前后各 12 字）。
  static const int contextRadius = 12;

  /// 结果上限（防爆量，Reeden 240 号同类防护）。
  static const int maxResults = 200;

  /// 查询：gram 交集 → 原文校验 → 上下文 + CFI。
  Future<List<SearchResult>> search(int bookId, String query) async {
    final trimmed = query.trim();
    final grams = SearchTokenizer.queryGrams(trimmed);
    if (grams.isEmpty) {
      return const <SearchResult>[];
    }
    // 取最稀有的 gram 作为主查询（§66.4）。
    var bestGram = grams.first;
    var bestCount = await _countGram(bookId, bestGram);
    for (final gram in grams.skip(1)) {
      final count = await _countGram(bookId, gram);
      if (count < bestCount) {
        bestCount = count;
        bestGram = gram;
        if (count == 0) {
          break;
        }
      }
    }
    if (bestCount == 0) {
      return const <SearchResult>[];
    }
    final candidates = await store.lookup(bookId, bestGram);
    final chapterCache = <int, ChapterText>{};
    final chapterTitle = await _chapterTitles();
    final results = <SearchResult>[];
    for (final candidate in candidates) {
      final chapterText = await _loadChapter(
        bookId,
        candidate.spineIndex,
        chapterCache,
      );
      if (chapterText == null) {
        continue;
      }
      // 原文校验：2-gram 候选必须真的以 query 开头（§66.4）。
      if (!chapterText.text.startsWith(trimmed, candidate.charOffset)) {
        continue;
      }
      results.add(
        SearchResult(
          spineIndex: candidate.spineIndex,
          charOffset: candidate.charOffset,
          chapterTitle: chapterTitle[candidate.spineIndex] ?? '',
          context: _contextOf(chapterText.text, candidate.charOffset, trimmed.length),
          matchLength: trimmed.length,
          cfi: _cfiOf(chapterText, candidate.charOffset),
        ),
      );
      if (results.length >= maxResults) {
        break;
      }
    }
    return results;
  }

  /// 命中位置的 CFI：块级 CFI + 块内字符偏移（§66.5 / §29.3）。
  String? _cfiOf(ChapterText chapter, int charOffset) {
    final located = chapter.locate(charOffset);
    if (located == null) {
      return null;
    }
    final base = located.block.block.startCfi;
    if (base == null || base.isEmpty) {
      return null;
    }
    return cfiWithCharOffset(base, located.localOffset);
  }

  static String _contextOf(String text, int offset, int length) {
    final start = offset - contextRadius < 0 ? 0 : offset - contextRadius;
    final end = offset + length + contextRadius > text.length
        ? text.length
        : offset + length + contextRadius;
    return text.substring(start, end);
  }

  Future<int> _countGram(int bookId, String gram) =>
      store.countGram(bookId, gram);

  Future<ChapterText?> _loadChapter(
    int bookId,
    int spineIndex,
    Map<int, ChapterText> cache,
  ) async {
    final cached = cache[spineIndex];
    if (cached != null) {
      return cached;
    }
    final saved = await store.chapterText(bookId, spineIndex);
    if (saved == null) {
      return null;
    }
    final pages = await source.loadChapter(spineIndex);
    final chapter = ChapterText.fromPages(pages);
    cache[spineIndex] = chapter;
    return chapter;
  }

  Future<Map<int, String>> _chapterTitles() async {
    final chapterSource = source;
    if (chapterSource is! TocChapterSource) {
      return const <int, String>{};
    }
    final titles = <int, String>{};
    for (final row in flattenToc(chapterSource.toc)) {
      titles.putIfAbsent(row.entry.spineIndex, () => row.entry.title);
    }
    return titles;
  }
}
