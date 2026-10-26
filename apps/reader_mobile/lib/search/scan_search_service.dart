import 'dart:async';
import 'dart:isolate';

import 'package:reader_core/position/cfi.dart';
import 'package:reader_ui/reader_session.dart';

import '../reader/epub_chapter_source.dart';
import 'chapter_text.dart';

/// 扫描式全文搜索（对照 Reeden 2.0 的「即时扫描 + 独立 isolate」方案）。
///
/// 不建倒排索引：查询时逐章取纯文本（只解析不排版），把文本丢进 isolate
/// 做线性扫描；只有命中的章才走完整排版拿块级 CFI。
///
/// 为什么不用预建索引：156MB / 1541 章的书，建 2-gram 索引在真机上约
/// 440ms/章（全书十几分钟），而线性扫描 368 万字符只要十几毫秒——瓶颈在
/// 取文本，不在搜索本身。
class ScanSearchService {
  /// 创建服务。
  ScanSearchService({required this.source, this.maxResults = 200});

  /// 章节来源。
  final ReaderChapterSource source;

  /// 结果上限（防爆量）。
  final int maxResults;

  /// 上下文半径（前后各 12 字）。
  static const int contextRadius = 12;

  /// 全章纯文本缓存（一次查询内复用；章节文本不可变小，可跨查询保留）。
  final Map<int, String> _textCache = <int, String>{};

  /// 查询：取文本 → isolate 扫描 → 命中章校验并生成 CFI。
  Future<List<SearchResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const <SearchResult>[];
    }
    final texts = await _collectTexts();
    if (texts.isEmpty) {
      return const <SearchResult>[];
    }
    final rawHits = await Isolate.run(
      () => scanTexts(texts, trimmed, maxResults),
    );
    if (rawHits.isEmpty) {
      return const <SearchResult>[];
    }
    return _expandHits(rawHits, trimmed);
  }

  /// 逐章取纯文本：每章让出一次事件循环，避免长书把主线程占住。
  Future<List<String>> _collectTexts() async {
    final source = this.source;
    if (source is! EpubChapterSource) {
      return const <String>[];
    }
    final result = <String>[];
    for (var spine = 0; spine < source.chapterCount; spine++) {
      final cached = _textCache[spine];
      if (cached != null) {
        result.add(cached);
        continue;
      }
      final text = source.chapterPlainText(spine);
      _textCache[spine] = text;
      result.add(text);
      await Future<void>.delayed(Duration.zero);
    }
    return result;
  }

  /// 命中章：用排版后的块级文本重新定位（校验偏移）并生成 CFI。
  Future<List<SearchResult>> _expandHits(
    List<ScanHit> hits,
    String query,
  ) async {
    final titles = _chapterTitles();
    final results = <SearchResult>[];
    final chapterCache = <int, ChapterText>{};
    for (final hit in hits) {
      var chapter = chapterCache[hit.spineIndex];
      if (chapter == null) {
        chapter = await _chapterTextOf(hit.spineIndex);
        if (chapter == null) {
          continue;
        }
        chapterCache[hit.spineIndex] = chapter;
      }
      // 扫描用的是聚合文本，这里按块级文本校正到精确偏移。
      final offset = _recenter(chapter.text, query, hit.charOffset);
      if (offset < 0) {
        continue;
      }
      results.add(
        SearchResult(
          spineIndex: hit.spineIndex,
          charOffset: offset,
          chapterTitle: titles[hit.spineIndex] ?? '',
          context: _contextOf(chapter.text, offset, query.length),
          matchLength: query.length,
          cfi: _cfiOf(chapter, offset, query),
        ),
      );
      if (results.length >= maxResults) {
        break;
      }
    }
    return results;
  }

  /// 在命中位置附近重新找一次 query，校正两种文本来源之间的偏移差。
  static int _recenter(String text, String query, int approx) {
    final lower = approx - 200 < 0 ? 0 : approx - 200;
    final upper = approx + 200 > text.length ? text.length : approx + 200;
    final segment = text.substring(lower, upper);
    final at = segment.indexOf(query);
    if (at >= 0) {
      return lower + at;
    }
    final exact = text.indexOf(query, lower);
    return exact;
  }

  Future<ChapterText?> _chapterTextOf(int spineIndex) async {
    try {
      final pages = await source.loadChapter(spineIndex);
      return ChapterText.fromPages(pages);
    } catch (_) {
      return null;
    }
  }

  String? _cfiOf(ChapterText chapter, int charOffset, String query) {
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

  Map<int, String> _chapterTitles() {
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

/// 一次扫描命中（可跨 isolate 传递）。
class ScanHit {
  /// 创建命中。
  const ScanHit({required this.spineIndex, required this.charOffset});

  /// 章节序号。
  final int spineIndex;

  /// 章内字符偏移（聚合文本坐标，后续会校正）。
  final int charOffset;

  /// 序列化（isolate 返回值必须可传）。
  List<int> toList() => <int>[spineIndex, charOffset];

  /// 反序列化。
  static ScanHit fromList(List<int> value) =>
      ScanHit(spineIndex: value[0], charOffset: value[1]);
}

/// isolate 内执行的线性扫描（顶层函数，避免捕获不可传递的对象）。
List<ScanHit> scanTexts(List<String> texts, String query, int maxResults) {
  final hits = <ScanHit>[];
  for (var spine = 0; spine < texts.length; spine++) {
    final text = texts[spine];
    var from = 0;
    while (true) {
      final at = text.indexOf(query, from);
      if (at < 0) {
        break;
      }
      hits.add(ScanHit(spineIndex: spine, charOffset: at));
      if (hits.length >= maxResults) {
        return hits;
      }
      from = at + query.length;
    }
  }
  return hits;
}

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
