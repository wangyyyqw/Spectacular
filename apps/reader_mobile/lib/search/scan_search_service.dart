import 'dart:async';

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
  ScanSearchService({
    required this.source,
    this.maxResults = 200,
    this.onLog,
  });

  /// 章节来源。
  final ReaderChapterSource source;

  /// 结果上限（防爆量）。
  final int maxResults;

  /// 诊断日志回调（搜索耗时打点，由 app 层写入 ReaderLog）。
  final void Function(String event, Map<String, Object?> fields)? onLog;

  void _log(String event, Map<String, Object?> fields) =>
      onLog?.call(event, fields);

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
    final textWatch = Stopwatch()..start();
    final texts = await _collectTexts();
    textWatch.stop();
    if (texts.isEmpty) {
      return const <SearchResult>[];
    }
    // 直接在主 isolate 扫描：368 万字符 indexOf 约十几毫秒，
    // 而把 9MB 文本序列化传给 isolate 反而更贵（真机实测）。
    final scanWatch = Stopwatch()..start();
    final rawHits = scanTexts(texts, trimmed, maxResults);
    scanWatch.stop();
    _log('search_scan', <String, Object?>{
      'query': trimmed,
      'chapters': texts.length,
      'hits': rawHits.length,
      'extract_ms': textWatch.elapsedMilliseconds,
      'scan_ms': scanWatch.elapsedMilliseconds,
    });
    if (rawHits.isEmpty) {
      return const <SearchResult>[];
    }
    final expandWatch = Stopwatch()..start();
    final results = await _expandHits(rawHits, trimmed);
    expandWatch.stop();
    _log('search_done', <String, Object?>{
      'query': trimmed,
      'results': results.length,
      'expand_ms': expandWatch.elapsedMilliseconds,
    });
    return results;
  }

  /// 流式搜索：逐章扫描、边扫边推（搜到就显示，不等全书扫完）。
  ///
  /// 每章产出一次「当前累计结果」，UI 逐批渲染；`total` 是章节总数，供进度显示。
  Stream<ScanProgress> searchStream(String query) async* {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      yield const ScanProgress(results: <SearchResult>[], scanned: 0, total: 0);
      return;
    }
    final source = this.source;
    if (source is! EpubChapterSource) {
      yield const ScanProgress(results: <SearchResult>[], scanned: 0, total: 0);
      return;
    }
    final titles = _chapterTitles();
    final total = source.chapterCount;
    final results = <SearchResult>[];
    final watch = Stopwatch()..start();
    for (var spine = 0; spine < total; spine++) {
      final text = _textCache[spine] ?? source.chapterPlainText(spine);
      _textCache[spine] = text;
      var from = 0;
      var added = false;
      while (results.length < maxResults) {
        final at = text.indexOf(trimmed, from);
        if (at < 0) {
          break;
        }
        results.add(
          SearchResult(
            spineIndex: spine,
            charOffset: at,
            chapterTitle: titles[spine] ?? '',
            context: _contextOf(text, at, trimmed.length),
            matchLength: trimmed.length,
          ),
        );
        from = at + trimmed.length;
        added = true;
      }
      if (added) {
        yield ScanProgress(
          results: List<SearchResult>.of(results),
          scanned: spine + 1,
          total: total,
          elapsedMs: watch.elapsedMilliseconds,
        );
      }
      if (results.length >= maxResults) {
        return;
      }
      // 每章让出一次事件循环，避免长书把主线程占住。
      await Future<void>.delayed(Duration.zero);
    }
    _log('search_scan', <String, Object?>{
      'query': trimmed,
      'chapters': total,
      'hits': results.length,
      'extract_scan_ms': watch.elapsedMilliseconds,
    });
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

  /// 命中：用同一份轻量文本校正偏移并截上下文（不排版、不算 CFI）。
  ///
  /// 之前这里为每条命中走 `loadChapter` 拿块级 CFI，200 条命中要 19 秒；
  /// 现在只在用户点开某一条时才排版算 CFI（见 [resolveCfi]）。
  Future<List<SearchResult>> _expandHits(
    List<ScanHit> hits,
    String query,
  ) async {
    final titles = _chapterTitles();
    final results = <SearchResult>[];
    for (final hit in hits) {
      final chapter = _textCache[hit.spineIndex];
      if (chapter == null) {
        continue;
      }
      final offset = recenterOffset(chapter, query, hit.charOffset);
      if (offset < 0) {
        continue;
      }
      results.add(
        SearchResult(
          spineIndex: hit.spineIndex,
          charOffset: offset,
          chapterTitle: titles[hit.spineIndex] ?? '',
          context: _contextOf(chapter, offset, query.length),
          matchLength: query.length,
          cfi: null,
        ),
      );
      if (results.length >= maxResults) {
        break;
      }
    }
    return results;
  }

  /// 解析一条命中的 CFI（点击时才调用，只排版这一章，约 440ms）。
  Future<String?> resolveCfi(SearchResult result) async {
    final chapter = await _chapterTextOf(result.spineIndex);
    if (chapter == null) {
      return null;
    }
    return _cfiOf(chapter, result.charOffset);
  }

  Future<ChapterText?> _chapterTextOf(int spineIndex) async {
    try {
      final pages = await source.loadChapter(spineIndex);
      return ChapterText.fromPages(pages);
    } catch (_) {
      return null;
    }
  }

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

/// 在命中位置附近重新找一次 query，校正两种文本来源之间的偏移差。
///
/// 扫描文本（xhtml 纯文本）与排版块文本长度并不一致，扫描偏移可能超出
/// 本章排版文本长度，切片前必须夹到 `[0, text.length]`，否则 substring 会抛
/// RangeError。窗口内找不到时退回全章查找，覆盖偏移差超过窗口的情况。
int recenterOffset(String text, String query, int approx) {
  final anchor = approx < 0 ? 0 : (approx > text.length ? text.length : approx);
  final lower = anchor - 200 < 0 ? 0 : anchor - 200;
  final upper = anchor + 200 > text.length ? text.length : anchor + 200;
  final at = text.substring(lower, upper).indexOf(query);
  if (at >= 0) {
    return lower + at;
  }
  return text.indexOf(query);
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

/// 线性扫描章节纯文本（顶层函数，便于单独测试）。
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

/// 流式搜索的一次进度快照。
class ScanProgress {
  /// 创建快照。
  const ScanProgress({
    required this.results,
    required this.scanned,
    required this.total,
    this.elapsedMs = 0,
  });

  /// 当前累计结果。
  final List<SearchResult> results;

  /// 已扫描章数。
  final int scanned;

  /// 章节总数。
  final int total;

  /// 已耗时（毫秒）。
  final int elapsedMs;
}
