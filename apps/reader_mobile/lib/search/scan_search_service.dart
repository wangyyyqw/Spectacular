import 'dart:async';

import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart' show applyTextTransform;
import 'package:reader_core/position/cfi.dart';

import 'package:reader_core/epub/epub_chapter_source.dart';
import 'chapter_text.dart';
import 'package:reader_core/source/toc.dart';

/// 扫描式全文搜索：只提取轻量正文，用户点击命中时才复用当前章节源排版。
///
/// 服务由阅读页持有；不重复解包、不另存一份全文缓存，退出时取消在途查询。
class ScanSearchService {
  /// 创建服务；章节源生命周期由阅读页负责。
  ScanSearchService({required this.source, this.maxResults = 200, this.onLog})
    : assert(maxResults > 0);

  /// 与正文阅读共用的章节源，保持排版几何与缓存一致。
  final EpubChapterSource source;

  /// 结果上限（防爆量）。
  final int maxResults;

  /// 诊断日志回调（搜索耗时由宿主记录）。
  final void Function(String event, Map<String, Object?> fields)? onLog;

  /// 上下文半径（前后各 12 字）。
  static const int contextRadius = 12;

  bool _disposed = false;
  int _generation = 0;

  /// 取消查询；不关闭共用章节源，也不保留已退出书籍的全文副本。
  void dispose() {
    _disposed = true;
    _generation++;
  }

  bool _canContinue(int generation) =>
      !_disposed && !source.isClosed && generation == _generation;

  /// 一次性查询与流式查询共用同一扫描路径；结果达到上限后不再读后续章节。
  Future<List<SearchResult>> search(String query) async {
    final stream = searchStream(query);
    final generation = _generation;
    var results = const <SearchResult>[];
    await for (final progress in stream) {
      results = progress.results;
    }
    return _canContinue(generation) ? results : const <SearchResult>[];
  }

  /// 逐章产出累计结果；开始新查询或退出阅读页后，旧查询不再访问章节源。
  Stream<ScanProgress> searchStream(String query) =>
      _scan(query.trim(), ++_generation);

  Stream<ScanProgress> _scan(String query, int generation) async* {
    if (!_canContinue(generation)) return;
    if (query.isEmpty) {
      yield const ScanProgress(results: <SearchResult>[], scanned: 0, total: 0);
      return;
    }
    final titles = _chapterTitles();
    final results = <SearchResult>[];
    final total = source.chapterCount;
    final watch = Stopwatch()..start();
    for (var spine = 0; spine < total; spine++) {
      if (!_canContinue(generation)) return;
      _scanChapter(spine, query, titles[spine] ?? '', results);
      yield ScanProgress(
        results: List<SearchResult>.of(results),
        scanned: spine + 1,
        total: total,
        elapsedMs: watch.elapsedMilliseconds,
      );
      if (results.length >= maxResults) break;
      await Future<void>.delayed(Duration.zero);
    }
    if (_canContinue(generation)) {
      onLog?.call('search_scan', <String, Object?>{
        'query': query,
        'chapters': total,
        'hits': results.length,
        'extract_scan_ms': watch.elapsedMilliseconds,
      });
    }
  }

  void _scanChapter(
    int spine,
    String query,
    String title,
    List<SearchResult> results,
  ) {
    final text = source.chapterPlainText(spine);
    var from = 0;
    while (results.length < maxResults) {
      final at = text.indexOf(query, from);
      if (at < 0) return;
      results.add(
        SearchResult(
          spineIndex: spine,
          charOffset: at,
          chapterTitle: title,
          context: _contextOf(text, at, query.length),
          matchLength: query.length,
        ),
      );
      from = at + query.length;
    }
  }

  /// 仅排版被点击的章节，退出期间完成的旧结果会被丢弃。
  Future<String?> resolveCfi(SearchResult result) async {
    if (_disposed || source.isClosed) return null;
    final generation = _generation;
    try {
      final pages = await source.loadChapter(result.spineIndex);
      if (!_canContinue(generation)) return null;
      final scanned = source.chapterPlainText(result.spineIndex);
      final end = result.charOffset + result.matchLength;
      if (result.charOffset < 0 ||
          result.matchLength <= 0 ||
          end > scanned.length) {
        return null;
      }
      final chapter = ChapterText.fromPages(pages);
      final offset = mapSearchOffset(
        chapter.text,
        scanned,
        scanned.substring(result.charOffset, end),
        result.charOffset,
        chapter: chapter,
      );
      final located = chapter.locate(offset);
      final base = located?.block.startCfi;
      if (base == null || base.isEmpty) return null;
      // 单元格聚合了多个文本节点及原子盒，只返回精确元素页锚点，不能把
      // 显示串偏移冒充某个原始文本节点的字符偏移。
      if (located!.block.cell != null) return base;
      return cfiWithCharOffset(base, located.localOffset);
    } catch (_) {
      return null;
    }
  }

  static String _contextOf(String text, int offset, int length) {
    final start = offset - contextRadius < 0 ? 0 : offset - contextRadius;
    final end = offset + length + contextRadius > text.length
        ? text.length
        : offset + length + contextRadius;
    return text.substring(start, end);
  }

  Map<int, String> _chapterTitles() {
    final titles = <int, String>{};
    for (final row in flattenToc(source.toc)) {
      titles.putIfAbsent(row.entry.spineIndex, () => row.entry.title);
    }
    return titles;
  }
}

/// 扫描偏移映射到排版正文；先比较去空白上下文，同上下文时保持命中序号。
///
/// 两套文本的块间换行、隐藏内容和生成内容不同，不能直接复用字符偏移；
/// 也不能只取窗口内第一个同词命中，否则重复词会跳错位置。
int mapSearchOffset(
  String rendered,
  String scanned,
  String query,
  int offset, {
  ChapterText? chapter,
}) {
  if (query.isEmpty ||
      offset < 0 ||
      offset + query.length > scanned.length ||
      !scanned.startsWith(query, offset)) {
    return -1;
  }
  final transforms = chapter == null
      ? {CssTextTransform.none}
      : {for (final b in chapter.blocks) _blockTransform(b)};
  final foldCase = transforms.any((value) => value != CssTextTransform.none);
  var best = (offset: -1, score: -1, distance: rendered.length);
  for (final transform in transforms) {
    final pattern = _searchPattern(scanned, query, offset, transform, foldCase);
    final candidate = _bestSearchMatch(rendered, pattern, transform, chapter);
    if (candidate.score > best.score ||
        (candidate.score == best.score && candidate.distance < best.distance)) {
      best = candidate;
    }
  }
  return best.offset;
}

CssTextTransform _blockTransform(ChapterBlock block) =>
    block.style?.textTransform ?? CssTextTransform.none;

typedef _SearchPattern = ({
  String query,
  int ordinal,
  (String, String) context,
  bool foldCase,
});

_SearchPattern _searchPattern(
  String scanned,
  String query,
  int offset,
  CssTextTransform transform,
  bool foldCase,
) {
  final text = applyTextTransform(scanned, transform);
  // 按实际变换后的前缀长度换算 UTF-16 偏移，不依赖大小写变换保持等长。
  final start = applyTextTransform(
    scanned.substring(0, offset),
    transform,
  ).length;
  final end = applyTextTransform(
    scanned.substring(0, offset + query.length),
    transform,
  ).length;
  final transformedQuery = text.substring(start, end);
  final ordinalText = foldCase ? text.toUpperCase() : text;
  final ordinalQuery = foldCase
      ? transformedQuery.toUpperCase()
      : transformedQuery;
  final ordinalOffset = foldCase
      ? text.substring(0, start).toUpperCase().length
      : start;
  return (
    query: transformedQuery,
    ordinal: _matchOrdinal(ordinalText, ordinalQuery, ordinalOffset),
    context: _matchContext(text, start, end - start, foldCase: foldCase),
    foldCase: foldCase,
  );
}

({int offset, int score, int distance}) _bestSearchMatch(
  String rendered,
  _SearchPattern pattern,
  CssTextTransform transform,
  ChapterText? chapter,
) {
  var best = (offset: -1, score: -1, distance: rendered.length);
  for (final (at, ordinal) in _searchCandidates(rendered, pattern)) {
    final block = chapter?.blockAt(at);
    if (chapter == null ||
        block != null && _blockTransform(block) == transform) {
      final candidate = _matchContext(
        rendered,
        at,
        pattern.query.length,
        foldCase: pattern.foldCase,
      );
      final score =
          _commonEdge(pattern.context.$1, candidate.$1, fromEnd: true) +
          _commonEdge(pattern.context.$2, candidate.$2, fromEnd: false);
      final distance = (ordinal - pattern.ordinal).abs();
      if (score > best.score ||
          (score == best.score && distance < best.distance)) {
        best = (offset: at, score: score, distance: distance);
      }
    }
  }
  return best;
}

Iterable<(int, int)> _searchCandidates(
  String rendered,
  _SearchPattern pattern,
) sync* {
  final folded = pattern.foldCase ? rendered.toUpperCase() : rendered;
  final query = pattern.foldCase ? pattern.query.toUpperCase() : pattern.query;
  var foldedAt = folded.indexOf(query);
  var ordinal = 0;
  var previous = 0;
  var foldedOffset = 0;
  var at = rendered.indexOf(pattern.query);
  while (at >= 0) {
    // 混合变换的段落共用全章序号；逐段转换前缀，避免每个命中重复扫描整章。
    foldedOffset += pattern.foldCase
        ? rendered.substring(previous, at).toUpperCase().length
        : at - previous;
    previous = at;
    while (foldedAt >= 0 && foldedAt < foldedOffset) {
      ordinal++;
      foldedAt = folded.indexOf(query, foldedAt + query.length);
    }
    yield (at, ordinal);
    at = rendered.indexOf(pattern.query, at + pattern.query.length);
  }
}

int _matchOrdinal(String text, String query, int offset) {
  var ordinal = 0;
  var at = text.indexOf(query);
  while (at >= 0 && at < offset) {
    ordinal++;
    at = text.indexOf(query, at + query.length);
  }
  return ordinal;
}

final RegExp _contextWhitespace = RegExp(r'\s+');

(String, String) _matchContext(
  String text,
  int offset,
  int length, {
  bool foldCase = false,
}) {
  const radius = ScanSearchService.contextRadius;
  final start = (offset - radius).clamp(0, text.length);
  final end = (offset + length + radius).clamp(0, text.length);
  final before = text
      .substring(start, offset)
      .replaceAll(_contextWhitespace, '');
  final after = text
      .substring(offset + length, end)
      .replaceAll(_contextWhitespace, '');
  return foldCase
      ? (before.toUpperCase(), after.toUpperCase())
      : (before, after);
}

int _commonEdge(String a, String b, {required bool fromEnd}) {
  var count = 0;
  while (count < a.length && count < b.length) {
    final ai = fromEnd ? a.length - 1 - count : count;
    final bi = fromEnd ? b.length - 1 - count : count;
    if (a.codeUnitAt(ai) != b.codeUnitAt(bi)) break;
    count++;
  }
  return count;
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

  /// 命中位置的 CFI；正文带字符偏移，表格使用元素页锚点，无法定位时为空。
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
