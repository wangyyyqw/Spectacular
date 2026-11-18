import 'location_anchor.dart';

/// 跨版本位置迁移。路径只提供候选，内容证据决定是否可自动关联。
abstract final class RevisionRelocator {
  static final _indexes = Expando<_BookIndex>();

  static AnchorRecord relocate({
    required AnchorBook oldBook,
    required AnchorBook newBook,
    required AnchorRecord record,
    bool progress = false,
  }) {
    final index = _indexes[newBook] ??= _BookIndex(newBook);
    final matcher = _Matcher(oldBook, index);
    final located = matcher.find(record.effective);
    if (located != null) return _success(record, located, newBook);
    if (record.current != null) {
      final original = matcher.find(record.original);
      if (original != null) return _success(record, original, newBook);
    }
    if (progress) {
      final approximate = matcher.approximate(record.effective);
      if (approximate != null) {
        return AnchorRecord(
          original: record.original,
          current: approximate,
          status: 'approximate',
          reason: '原阅读位置无法精确匹配，已近似恢复',
        );
      }
    }
    return AnchorRecord(
      original: record.original,
      current: record.current,
      status: 'pending',
      reason: matcher.ambiguous ? '原文多处出现，无法可靠消歧' : '原文已修改或删除，需重新定位',
    );
  }

  static AnchorRecord _success(
    AnchorRecord old,
    LocationAnchor current,
    AnchorBook book,
  ) {
    final source = old.effective;
    final unchanged =
        source.revision == book.revision &&
        source.start.cfi == current.start.cfi &&
        source.end?.cfi == current.end?.cfi;
    return AnchorRecord(
      original: old.original,
      current: current,
      status: current.approximate
          ? 'approximate'
          : (unchanged ? 'verified' : 'relocated'),
      reason: current.approximate ? '原内容位置只能近似还原' : null,
    );
  }

  /// 用未变化文本扣除拆合与搬移；剩余新增段落或新章节才重置读完。
  static bool hasAddedReadableContent(AnchorBook oldBook, AnchorBook newBook) {
    final old = oldBook.chapters
        .where((chapter) => chapter.readable && chapter.text.trim().isNotEmpty)
        .toList();
    final current = newBook.chapters
        .where((chapter) => chapter.readable && chapter.text.trim().isNotEmpty)
        .toList();
    final oldText = normalizeAnchorText(
      old.map((chapter) => chapter.text).join(),
    );
    final newText = normalizeAnchorText(
      current.map((chapter) => chapter.text).join(),
    );
    if (oldText == newText) return false;
    if (newText.length > oldText.length && _hasExtraCopies(old, current)) {
      return true;
    }
    final fingerprints = old
        .expand((chapter) => chapter.paragraphFingerprints)
        .toSet();
    final currentFingerprints = current
        .expand((chapter) => chapter.paragraphFingerprints)
        .toSet();
    final oldChanged = _unmatchedParagraphs(old, currentFingerprints, newText);
    final newChanged = _unmatchedParagraphs(current, fingerprints, oldText);
    if (newChanged > oldChanged) return true;
    return _hasNewChapter(old, current, oldText);
  }

  static bool _hasExtraCopies(
    List<AnchorChapter> old,
    List<AnchorChapter> current,
  ) {
    final oldCounts = <String, int>{};
    final newCounts = <String, int>{};
    for (final chapter in old) {
      for (final fingerprint in chapter.paragraphFingerprints) {
        oldCounts[fingerprint] = (oldCounts[fingerprint] ?? 0) + 1;
      }
    }
    for (final chapter in current) {
      for (var i = 0; i < chapter.blocks.length; i++) {
        if (chapter.blocks[i].text.trim().isEmpty) continue;
        final fingerprint = chapter.paragraphFingerprints[i];
        final count = (newCounts[fingerprint] ?? 0) + 1;
        newCounts[fingerprint] = count;
        final previous = oldCounts[fingerprint];
        if (previous != null && count > previous) return true;
      }
    }
    return false;
  }

  static bool _hasNewChapter(
    List<AnchorChapter> old,
    List<AnchorChapter> current,
    String oldText,
  ) {
    final chapterFingerprints = old
        .map((chapter) => chapter.fingerprint)
        .toSet();
    final paths = old.map((chapter) => chapter.href).toSet();
    final titles = old
        .map((chapter) => chapter.title)
        .where((title) => title.isNotEmpty)
        .toSet();
    for (final chapter in current) {
      if (chapterFingerprints.contains(chapter.fingerprint)) continue;
      final sameIdentity =
          paths.contains(chapter.href) || titles.contains(chapter.title);
      final sharesText = chapter.blocks.any(
        (block) =>
            block.text.trim().isNotEmpty &&
            oldText.contains(normalizeAnchorText(block.text)),
      );
      if (!sameIdentity && !sharesText) return true;
    }
    return false;
  }

  static int _unmatchedParagraphs(
    List<AnchorChapter> chapters,
    Set<String> fingerprints,
    String otherText,
  ) {
    var count = 0;
    for (final chapter in chapters) {
      for (var i = 0; i < chapter.blocks.length; i++) {
        final text = normalizeAnchorText(chapter.blocks[i].text);
        if (text.trim().isEmpty ||
            fingerprints.contains(chapter.paragraphFingerprints[i])) {
          continue;
        }
        if (!otherText.contains(text)) count++;
      }
    }
    return count;
  }
}

class _BookIndex {
  _BookIndex(this.book) {
    final text = StringBuffer();
    var offset = 0;
    for (final chapter in book.chapters) {
      starts.add(offset);
      positions[chapter.spineIndex] = starts.length - 1;
      text.write(chapter.text);
      offset += chapter.text.length;
      (chaptersByFingerprint[chapter.fingerprint] ??= []).add(chapter);
      (chaptersByHref[chapter.href] ??= []).add(chapter);
      if (chapter.title.isNotEmpty) {
        (chaptersByTitle[chapter.title] ??= []).add(chapter);
      }
      for (var i = 0; i < chapter.blocks.length; i++) {
        if (chapter.blocks[i].text.trim().isEmpty) continue;
        (paragraphs[chapter.paragraphFingerprints[i]] ??= []).add(chapter);
      }
    }
    normalized = NormalizedAnchorText(text.toString());
  }

  final AnchorBook book;
  final List<int> starts = [];
  final Map<int, int> positions = {};
  final Map<String, List<AnchorChapter>> chaptersByFingerprint = {};
  final Map<String, List<AnchorChapter>> chaptersByHref = {};
  final Map<String, List<AnchorChapter>> chaptersByTitle = {};
  final Map<String, List<AnchorChapter>> paragraphs = {};
  final relationships = Expando<_ChapterRelations>();
  late final NormalizedAnchorText normalized;
  String get normalizedText => normalized.text;

  int globalOffset(AnchorPoint point) {
    final chapter = book.chapter(point.spineIndex);
    if (chapter == null) return -1;
    return normalized.normalizedOffset(
      starts[positions[point.spineIndex]!] + point.charOffset,
    );
  }

  AnchorPoint? pointAt(int offset, {bool end = false}) {
    if (offset < 0 || offset > normalizedText.length) return null;
    if (book.chapters.isEmpty) return null;
    final raw = end ? normalized.rawEnd(offset) : normalized.rawStart(offset);
    var low = 0;
    var high = starts.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (starts[middle] <= raw) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    var position = (low - 1).clamp(0, starts.length - 1);
    if (end && position > 0 && starts[position] == raw) position--;
    final chapter = book.chapters[position];
    return book.anchorAt(chapter.spineIndex, raw - starts[position])?.start;
  }

  LocationAnchor? locationAt(int start, int? end, {bool approximate = false}) {
    final first = pointAt(start);
    if (first == null) return null;
    if (end == null) {
      return book.anchorAt(
        first.spineIndex,
        first.charOffset,
        approximate: approximate,
      );
    }
    final last = pointAt(end, end: true);
    return last == null ? null : book.rangeAt(first, last);
  }

  List<int> hits(String quote, {List<AnchorChapter>? chapters}) {
    if (quote.isEmpty) return [];
    final hits = <int>[];
    final ranges = chapters == null
        ? [(0, normalizedText.length)]
        : chapters.map((chapter) {
            final raw = starts[positions[chapter.spineIndex]!];
            return (
              normalized.normalizedOffset(raw),
              normalized.normalizedOffset(raw + chapter.text.length),
            );
          });
    for (final range in ranges) {
      var from = range.$1;
      while (from <= normalizedText.length - quote.length && from < range.$2) {
        final hit = normalizedText.indexOf(quote, from);
        if (hit < 0 || hit >= range.$2) break;
        hits.add(hit);
        from = hit + 1;
      }
    }
    return hits;
  }
}

/// 每组版本只计算一次相邻章节关联，迁移大量记录时复用。
class _ChapterRelations {
  _ChapterRelations(AnchorBook old, _BookIndex index) {
    _collect(old.chapters, index, before);
    _collect(old.chapters.reversed, index, after);
  }

  final Map<int, AnchorChapter> before = {};
  final Map<int, AnchorChapter> after = {};
  final Map<(String, String, int, String, String), List<AnchorChapter>>
  mappings = {};

  void _collect(
    Iterable<AnchorChapter> old,
    _BookIndex index,
    Map<int, AnchorChapter> result,
  ) {
    AnchorChapter? previous;
    for (final chapter in old) {
      if (previous != null) result[chapter.spineIndex] = previous;
      final matched = index.chaptersByFingerprint[chapter.fingerprint] ?? [];
      if (matched.length == 1) previous = matched.single;
    }
  }
}

class _Matcher {
  _Matcher(this.oldBook, this.index)
    : relations = index.relationships[oldBook] ??= _ChapterRelations(
        oldBook,
        index,
      );

  final AnchorBook oldBook;
  final _BookIndex index;
  final _ChapterRelations relations;
  bool ambiguous = false;

  LocationAnchor? find(LocationAnchor source) {
    final direct = index.book.capture(
      source.start.cfi,
      endCfi: source.end?.cfi,
    );
    if (direct != null && _directVerified(source, direct)) {
      return _inheritApproximate(source, direct);
    }
    final exact = _findQuote(source);
    if (exact != null) return _inheritApproximate(source, exact);
    if (!source.isRange && source.quote.isEmpty) {
      final endPoint = _findPoint(source.start);
      final end = endPoint == null ? null : index.locationAt(endPoint, null);
      if (end != null) return _inheritApproximate(source, end);
    }
    final endpoints = source.isRange ? _findEndpoints(source) : null;
    if (endpoints != null) return _inheritApproximate(source, endpoints);
    final bracketed = _findBracketed(source);
    return bracketed == null ? null : _inheritApproximate(source, bracketed);
  }

  LocationAnchor _inheritApproximate(
    LocationAnchor source,
    LocationAnchor result,
  ) => LocationAnchor(
    revision: result.revision,
    start: result.start,
    end: result.end,
    quote: result.quote,
    approximate: source.approximate,
  );

  bool _directVerified(LocationAnchor source, LocationAnchor target) {
    if (normalizeAnchorText(source.quote) !=
        normalizeAnchorText(target.quote)) {
      return false;
    }
    if (!_rangeContexts(
      source,
      index.globalOffset(target.start),
      index.globalOffset(target.end ?? target.start),
    )) {
      return false;
    }
    if (source.revision == index.book.revision) return true;
    final mapped = _mappedChapters(source.start);
    return mapped.length == 1 &&
        mapped.single.spineIndex == target.start.spineIndex;
  }

  LocationAnchor? _findQuote(LocationAnchor source) {
    final quote = normalizeAnchorText(source.quote);
    if (quote.isEmpty) return null;
    final chosen = _findCandidate(
      quote,
      source.start,
      (hit) =>
          _rangeContexts(source, hit, hit + quote.length) ||
          _unchangedParagraphQuote(source, hit, hit + quote.length),
    );
    if (chosen == null) return null;
    return index.locationAt(
      chosen,
      source.isRange ? chosen + quote.length : null,
    );
  }

  int? _findCandidate(
    String quote,
    AnchorPoint source,
    bool Function(int) accepts,
  ) {
    final mapped = _mappedChapters(source);
    if (mapped.isNotEmpty) {
      final candidates = index
          .hits(quote, chapters: mapped)
          .where(accepts)
          .toList();
      final chosen = _choose(candidates, source);
      if (chosen != null) return chosen;
    }
    return _choose(index.hits(quote).where(accepts).toList(), source);
  }

  int? _choose(List<int> candidates, AnchorPoint source) {
    if (candidates.length == 1) return candidates.single;
    if (candidates.isEmpty) return null;
    final mapped = _mappedChapters(source);
    if (mapped.length == 1) {
      final narrowed = candidates
          .where(
            (hit) => index.pointAt(hit)?.spineIndex == mapped.single.spineIndex,
          )
          .toList();
      if (narrowed.length == 1) return narrowed.single;
    }
    ambiguous = true;
    return null;
  }

  bool _rangeContexts(LocationAnchor source, int start, int end) {
    if (start < 0 || end < start) return false;
    final before = normalizeAnchorText(source.start.contextBefore);
    final after = normalizeAnchorText(
      source.isRange ? source.end!.quote : source.start.contextAfter,
    );
    final actualEnd = source.isRange
        ? end
        : start + normalizeAnchorText(source.quote).length;
    return _matchesBefore(before, start) && _matchesAfter(after, actualEnd);
  }

  /// 完整引用已命中，段外章名变动由唯一不变段落及段内偏移提供定位证据。
  /// 范围同时核对两端；点锚点只需确认其所在段落中的唯一原位置。
  bool _unchangedParagraphQuote(LocationAnchor source, int start, int end) {
    final target = index.locationAt(start, source.isRange ? end : null);
    return target != null &&
        _unchangedParagraphPoint(source.start, target.start) &&
        (!source.isRange ||
            _unchangedParagraphPoint(source.end!, target.end!, end: true));
  }

  bool _unchangedParagraphPoint(
    AnchorPoint source,
    AnchorPoint target, {
    bool end = false,
  }) {
    final old = oldBook.chapter(source.spineIndex);
    final current = index.book.chapter(target.spineIndex);
    if (old == null ||
        current == null ||
        old.fingerprint != source.chapterFingerprint) {
      return false;
    }
    final oldBlock = _paragraphAt(old, source.charOffset, end: end);
    final newBlock = _paragraphAt(current, target.charOffset, end: end);
    if (oldBlock == null || newBlock == null) return false;
    final fingerprint = old.paragraphFingerprints[oldBlock];
    if (fingerprint != current.paragraphFingerprints[newBlock] ||
        _paragraphOffset(old, oldBlock, source.charOffset) !=
            _paragraphOffset(current, newBlock, target.charOffset)) {
      return false;
    }
    if (index.paragraphs[fingerprint]?.length == 1) return true;
    return old.fingerprint == current.fingerprint &&
        index.chaptersByFingerprint[current.fingerprint]?.length == 1 &&
        old.normalized.normalizedOffset(source.charOffset) ==
            current.normalized.normalizedOffset(target.charOffset);
  }

  /// 结束锚点可能记录下一段指纹；排他结束边界须核对实际选中的前一段。
  int? _paragraphAt(AnchorChapter chapter, int offset, {required bool end}) {
    if (offset < 0 || offset > chapter.text.length) return null;
    for (var i = chapter.blocks.length - 1; i >= 0; i--) {
      final start = chapter.blockStarts[i];
      if (end ? offset > start : offset >= start) return i;
    }
    return null;
  }

  int _paragraphOffset(AnchorChapter chapter, int block, int offset) =>
      normalizeAnchorText(
        chapter.blocks[block].text.substring(
          0,
          offset - chapter.blockStarts[block],
        ),
      ).length;

  bool _matchesBefore(String context, int start) {
    if (context.isEmpty) return true;
    final from = utf16Boundary(index.normalizedText, start - context.length);
    final available = index.normalizedText.substring(from, start);
    if (available.endsWith(context)) return true;
    for (var length = context.length - 1; length >= 16; length--) {
      final boundary = utf16Boundary(
        context,
        context.length - length,
        forward: true,
      );
      if (context.length - boundary < 16) continue;
      if (available.endsWith(context.substring(boundary))) return true;
    }
    return false;
  }

  bool _matchesAfter(String context, int end) {
    if (context.isEmpty) return true;
    if (end > index.normalizedText.length) return false;
    final to = utf16Boundary(index.normalizedText, end + context.length);
    final available = index.normalizedText.substring(end, to);
    if (available.startsWith(context)) return true;
    for (var length = context.length - 1; length >= 16; length--) {
      final boundary = utf16Boundary(context, length);
      if (boundary < 16) continue;
      if (available.startsWith(context.substring(0, boundary))) return true;
    }
    return false;
  }

  LocationAnchor? _findEndpoints(LocationAnchor source) {
    final start = _findStrongEndpoint(source.start);
    final end = _findStrongEndpoint(source.end!);
    if (start == null || end == null || end <= start) return null;
    final located = index.locationAt(start, end);
    if (located == null || located.quote.trim().isEmpty) return null;
    return located;
  }

  /// 原范围未完整命中时，两端均须有至少 16 单元的不变文字证据。
  /// 章末短引用只能由唯一的长前文夹定，不能凭几个字自动迁移修改范围。
  int? _findStrongEndpoint(AnchorPoint source) {
    final point = _findPoint(source);
    if (point == null) return null;
    if (normalizeAnchorText(source.quote).length >= 16) return point;
    final before = _uniqueBefore(source.contextBefore);
    return before != null && point == before.$1 + before.$2 ? point : null;
  }

  int? _findPoint(AnchorPoint source) {
    final quote = normalizeAnchorText(source.quote);
    if (quote.isEmpty) {
      final before = _uniqueBefore(source.contextBefore);
      return before == null ? null : before.$1 + before.$2;
    }
    return _findCandidate(
      quote,
      source,
      (hit) =>
          _matchesBefore(normalizeAnchorText(source.contextBefore), hit) &&
          _matchesAfter(
            normalizeAnchorText(source.contextAfter),
            hit + quote.length,
          ),
    );
  }

  LocationAnchor? _findBracketed(LocationAnchor source) {
    final left = _uniqueBefore(source.start.contextBefore);
    final right = _uniqueAfter(
      source.isRange ? source.end!.quote : source.start.contextAfter,
    );
    if (left == null || right == null) return null;
    final start = left.$1 + left.$2;
    final end = right.$1;
    if (end <= start) return null;
    final located = index.locationAt(start, source.isRange ? end : null);
    if (located == null) return null;
    final text = index.normalizedText.substring(start, end);
    if (text.trim().isEmpty) return null;
    if (!source.isRange &&
        !_sharesFragment(normalizeAnchorText(source.quote), text)) {
      return null;
    }
    return located;
  }

  /// 修改范围内至少保留一段旧文字，防止把完全删除的引用挂到邻文。
  bool _sharesFragment(String old, String current) {
    if (old == current && old.isNotEmpty) return true;
    if (old.length < 16 || current.length < 16) return false;
    for (var i = 0; i <= old.length - 16; i++) {
      if (utf16Boundary(old, i) != i) continue;
      final end = utf16Boundary(old, i + 16, forward: true);
      if (current.contains(old.substring(i, end))) return true;
    }
    return false;
  }

  (int, int)? _uniqueBefore(String raw) {
    final context = normalizeAnchorText(raw);
    for (var length = context.length; length >= 16; length--) {
      final from = utf16Boundary(
        context,
        context.length - length,
        forward: true,
      );
      final quote = context.substring(from);
      if (quote.length < 16) continue;
      final hits = index.hits(quote);
      if (hits.length == 1) return (hits.single, quote.length);
    }
    return null;
  }

  (int, int)? _uniqueAfter(String raw) {
    final context = normalizeAnchorText(raw);
    for (var length = context.length; length >= 16; length--) {
      final boundary = utf16Boundary(context, length);
      if (boundary < 16) continue;
      final hits = index.hits(context.substring(0, boundary));
      if (hits.length == 1) return (hits.single, boundary);
    }
    return null;
  }

  List<AnchorChapter> _mappedChapters(AnchorPoint source) {
    final key = (
      source.chapterFingerprint,
      source.paragraphFingerprint,
      source.spineIndex,
      source.href,
      source.title,
    );
    return relations.mappings[key] ??= _resolveChapters(source);
  }

  List<AnchorChapter> _resolveChapters(AnchorPoint source) {
    final exact = index.chaptersByFingerprint[source.chapterFingerprint] ?? [];
    if (exact.length == 1) return exact;
    if (exact.length > 1) {
      final identified = exact
          .where(
            (chapter) =>
                chapter.href == source.href && chapter.title == source.title,
          )
          .toList();
      return identified.length == 1 ? identified : [];
    }
    final paragraph = index.paragraphs[source.paragraphFingerprint] ?? [];
    if (paragraph.length == 1) return paragraph;
    final shared = _mapBySharedParagraphs(source);
    return shared.isEmpty ? _mapByNeighbors(source) : shared;
  }

  List<AnchorChapter> _mapBySharedParagraphs(AnchorPoint source) {
    final old = oldBook.chapter(source.spineIndex);
    if (old == null || old.fingerprint != source.chapterFingerprint) return [];
    final votes = <AnchorChapter, int>{};
    for (final fingerprint in old.paragraphFingerprints.toSet()) {
      final matches = index.paragraphs[fingerprint] ?? [];
      if (matches.length != 1) continue;
      final chapter = matches.single;
      votes[chapter] = (votes[chapter] ?? 0) + 1;
    }
    if (votes.isEmpty) return [];
    final maximum = votes.values.reduce((a, b) => a > b ? a : b);
    final best = votes.entries
        .where((entry) => entry.value == maximum)
        .map((entry) => entry.key)
        .toList();
    return best.length == 1 ? best : [];
  }

  /// 路径和标题只有得到两侧已验证章节夹定时才能建立关联。
  List<AnchorChapter> _mapByNeighbors(AnchorPoint source) {
    final previous = oldBook.chapter(source.spineIndex);
    if (previous == null || previous.fingerprint != source.chapterFingerprint) {
      return [];
    }
    final candidates = <AnchorChapter>{
      ...?index.chaptersByHref[source.href],
      ...?index.chaptersByTitle[source.title],
    };
    if (candidates.isEmpty) return [];
    final before = relations.before[source.spineIndex];
    final after = relations.after[source.spineIndex];
    if (before == null ||
        after == null ||
        before.spineIndex >= after.spineIndex) {
      return [];
    }
    final between = candidates
        .where(
          (chapter) =>
              chapter.spineIndex > before.spineIndex &&
              chapter.spineIndex < after.spineIndex,
        )
        .toList();
    return between.length == 1 ? between : [];
  }

  LocationAnchor? approximate(LocationAnchor source) {
    final mapped = _mappedChapters(source.start);
    if (mapped.length == 1 && mapped.single.readable) {
      final fraction = source.start.chapterLength == 0
          ? 0.0
          : source.start.charOffset / source.start.chapterLength;
      final offset = (fraction.clamp(0.0, 1.0) * mapped.single.text.length)
          .round();
      return index.book.anchorAt(
        mapped.single.spineIndex,
        offset,
        approximate: true,
      );
    }
    return _neighborFallback(source.start.spineIndex);
  }

  LocationAnchor? _neighborFallback(int spine) {
    final later = oldBook.chapters.where(
      (chapter) => chapter.spineIndex > spine,
    );
    for (final chapter in later) {
      final target = _neighbor(chapter);
      if (target != null) {
        return index.book.anchorAt(target.spineIndex, 0, approximate: true);
      }
    }
    final earlier = oldBook.chapters
        .where((chapter) => chapter.spineIndex < spine)
        .toList()
        .reversed;
    for (final chapter in earlier) {
      final target = _neighbor(chapter);
      if (target != null) {
        return index.book.anchorAt(
          target.spineIndex,
          target.text.length,
          approximate: true,
        );
      }
    }
    for (final chapter in index.book.chapters) {
      if (!chapter.readable || chapter.text.isEmpty) continue;
      return index.book.anchorAt(chapter.spineIndex, 0, approximate: true);
    }
    return null;
  }

  AnchorChapter? _neighbor(AnchorChapter old) {
    final anchor = oldBook.anchorAt(old.spineIndex, 0);
    if (anchor == null) return null;
    final targets = _mappedChapters(anchor.start)
        .where((chapter) => chapter.readable && chapter.text.isNotEmpty)
        .toList();
    return targets.length == 1 ? targets.single : null;
  }
}
