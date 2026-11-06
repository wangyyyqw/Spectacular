import 'dart:math' as math;

import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/position/cfi.dart';

import 'selection.dart';

/// 可对应到原文的完整选区，不包含图片或脚注引用。
class ReaderSupportedSelection {
  /// 创建已核验的原文选区。
  const ReaderSupportedSelection({
    required this.startCfi,
    required this.endCfi,
    required this.quote,
    this.contextBefore,
    this.contextAfter,
  });

  /// 原文区间与未插入排版空格的引用。
  final String startCfi;
  final String endCfi;
  final String quote;

  /// 区间前后的原文上下文。
  final String? contextBefore;
  final String? contextAfter;
}

/// 三个选区功能共享的前置校验，拒绝半成品标注。
abstract final class ReaderSelectionSupport {
  /// 以原文块而非换行后的显示文字生成引用。
  static ReaderSupportedSelection? capture(
    List<PageContent> pages,
    ReaderSelection selection,
  ) {
    final cfi = SelectionOps.cfiOf(selection);
    if (cfi == null || (!selection.isMultiPage && selection.isCollapsed)) {
      return null;
    }
    final start = EpubCfi.parse(cfi.start);
    final end = EpubCfi.parse(cfi.end);
    if (start == null || end == null || start.compareTo(end) >= 0) return null;
    final blocks = _blocks(pages);
    if (!_endpointCovered(blocks, start, isEnd: false) ||
        !_endpointCovered(blocks, end, isEnd: true) ||
        _hasUnmappedSlices(pages, selection)) {
      return null;
    }
    final quote = _quoteOf(blocks, start, end);
    if (quote == null || quote.isEmpty) return null;
    return _withContext(selection, cfi, quote);
  }

  static ReaderSupportedSelection? _withContext(
    ReaderSelection selection,
    ({String start, String end}) cfi,
    String quote,
  ) {
    final first = selection.start.lineBox.slice.block.layout.text;
    final last = selection.end.lineBox.slice.block.layout.text;
    final from =
        selection.start.lineBox.blockTextOffset + selection.start.charOffset;
    final to = selection.end.lineBox.blockTextOffset + selection.end.charOffset;
    if (from < 0 || from > first.length || to < 0 || to > last.length) {
      return null;
    }
    return ReaderSupportedSelection(
      startCfi: cfi.start,
      endCfi: cfi.end,
      quote: quote,
      contextBefore: first.substring(math.max(0, from - 20), from),
      contextAfter: last.substring(to, math.min(last.length, to + 20)),
    );
  }

  static bool _endpointCovered(
    List<PageBlock> blocks,
    EpubCfi endpoint, {
    required bool isEnd,
  }) => blocks.any((block) {
    final parsed = EpubCfi.parse(block.startCfi!);
    if (parsed == null ||
        parsed.withCharOffset(0).compareTo(endpoint.withCharOffset(0)) != 0) {
      return false;
    }
    final offset = (endpoint.charOffset ?? 0) - (parsed.charOffset ?? 0);
    return isEnd
        ? offset > 0 && offset <= block.layout.text.length
        : offset >= 0 && offset < block.layout.text.length;
  });

  static bool _hasUnmappedSlices(
    List<PageContent> pages,
    ReaderSelection selection,
  ) {
    for (final page in pages) {
      if (page.pageIndex < selection.startPageIndex ||
          page.pageIndex > selection.endPageIndex) {
        continue;
      }
      for (var index = 0; index < page.slices.length; index++) {
        if (page.pageIndex == selection.startPageIndex &&
            index < selection.start.sliceIndex) {
          continue;
        }
        if (page.pageIndex == selection.endPageIndex &&
            index > selection.end.sliceIndex) {
          continue;
        }
        final slice = page.slices[index];
        if (slice.overlay) continue;
        final block = slice.block;
        if (block.table != null || !block.textRuleEligible) return true;
        if (block.layout.text.isEmpty &&
            block.inlineImages.isEmpty &&
            block.table == null) {
          continue;
        }
        if (block.layout.text.isEmpty && block.inlineImages.isNotEmpty) {
          return true;
        }
        if (EpubCfi.parse(block.startCfi ?? '') == null) return true;
      }
    }
    return false;
  }

  static String? _quoteOf(List<PageBlock> blocks, EpubCfi start, EpubCfi end) {
    final pieces = <(String, int, String)>[];
    for (final block in blocks) {
      final range = _range(block, start, end);
      if (range == null) continue;
      if (!_supported(block, range.$1, range.$2)) return null;
      final offset = (cfiCharOffset(block.startCfi!) ?? 0) + range.$1;
      final text = block.layout.text.substring(range.$1, range.$2);
      final piece = (cfiBase(block.startCfi!), offset, text);
      if (!_appendPiece(pieces, piece)) return null;
    }
    return pieces.map((piece) => piece.$3).join();
  }

  static bool _appendPiece(
    List<(String, int, String)> pieces,
    (String, int, String) piece,
  ) {
    if (pieces.isEmpty || pieces.last.$1 != piece.$1) {
      pieces.add(piece);
      return true;
    }
    final previous = pieces.last;
    final offset = piece.$2 - previous.$2;
    if (offset < 0 || offset > previous.$3.length) return false;
    final overlap = math.min(previous.$3.length - offset, piece.$3.length);
    if (previous.$3.substring(offset, offset + overlap) !=
        piece.$3.substring(0, overlap)) {
      return false;
    }
    pieces[pieces.length - 1] = (
      previous.$1,
      previous.$2,
      previous.$3 + piece.$3.substring(overlap),
    );
    return true;
  }

  static List<PageBlock> _blocks(List<PageContent> pages) {
    final unique = <String, PageBlock>{};
    for (final page in pages) {
      for (final slice in page.slices) {
        final cfi = slice.block.startCfi;
        if (cfi != null && EpubCfi.parse(cfi) != null) {
          unique.putIfAbsent(cfi, () => slice.block);
        }
      }
    }
    return unique.values.toList()..sort(
      (left, right) =>
          EpubCfi.parse(left.startCfi!)!
              .compareTo(EpubCfi.parse(right.startCfi!)!),
    );
  }

  static (int, int)? _range(PageBlock block, EpubCfi start, EpubCfi end) {
    final parsed = EpubCfi.parse(block.startCfi!);
    if (parsed == null) return null;
    final base = parsed.withCharOffset(0);
    final fromStart = base.compareTo(start.withCharOffset(0));
    final toEnd = base.compareTo(end.withCharOffset(0));
    if (fromStart < 0 || toEnd > 0) return null;
    final offset = parsed.charOffset ?? 0;
    final length = block.layout.text.length;
    final from = fromStart == 0 ? (start.charOffset ?? 0) - offset : 0;
    final to = toEnd == 0 ? (end.charOffset ?? 0) - offset : length;
    final clippedFrom = from.clamp(0, length);
    final clippedTo = to.clamp(0, length);
    return clippedFrom >= clippedTo ? null : (clippedFrom, clippedTo);
  }

  static bool _supported(PageBlock block, int start, int end) {
    if (block.table != null || !block.textRuleEligible) return false;
    final text = block.layout.text;
    if (text.substring(start, end).contains('\uFFFC')) return false;
    if (block.footnotes.any((note) => note.start < end && note.end > start)) {
      return false;
    }
    return !_splitsSurrogate(text, start) && !_splitsSurrogate(text, end);
  }

  static bool _splitsSurrogate(String text, int offset) =>
      offset > 0 &&
      offset < text.length &&
      text.codeUnitAt(offset - 1) >= 0xD800 &&
      text.codeUnitAt(offset - 1) <= 0xDBFF &&
      text.codeUnitAt(offset) >= 0xDC00 &&
      text.codeUnitAt(offset) <= 0xDFFF;
}
