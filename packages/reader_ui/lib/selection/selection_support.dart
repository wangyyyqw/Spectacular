import 'dart:math' as math;

import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/text_cfi_map.dart';

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
    this.sourceQuote,
  });

  /// 原文区间与未插入排版空格的引用。
  final String startCfi;
  final String endCfi;
  final String quote;

  /// OCR 显示文字对应的原始码点证据；定位始终使用原文，不使用识别文字。
  final String? sourceQuote;

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
    if (quote == null || quote.trim().isEmpty) return null;
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
    final offset = block.offsetForCfi(endpoint.serialize(), end: isEnd);
    if (offset == null) return false;
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
    final pieces = <(TextCfiMap, String)>[];
    for (final block in blocks) {
      final range = _range(block, start, end);
      if (range == null) continue;
      if (!_supported(block, range.$1, range.$2)) return null;
      final text = block.layout.text.substring(range.$1, range.$2);
      final map = block.textCoordinates?.slice(range.$1, range.$2);
      if (map == null) return null;
      final piece = (map, text);
      if (!_appendPiece(pieces, piece)) return null;
    }
    return pieces.map((piece) => piece.$2).join();
  }

  static bool _appendPiece(
    List<(TextCfiMap, String)> pieces,
    (TextCfiMap, String) piece,
  ) {
    final offset = pieces.isEmpty ? null : piece.$1.offsetFrom(pieces.last.$1);
    if (offset == null) {
      pieces.add(piece);
      return true;
    }
    final previous = pieces.last;
    if (offset < 0 || offset > previous.$2.length) return false;
    final overlap = math.min(previous.$2.length - offset, piece.$2.length);
    if (previous.$2.substring(offset, offset + overlap) !=
        piece.$2.substring(0, overlap)) {
      return false;
    }
    pieces[pieces.length - 1] = (
      previous.$1,
      previous.$2 + piece.$2.substring(overlap),
    );
    return true;
  }

  static List<PageBlock> _blocks(List<PageContent> pages) {
    final unique = <PageBlock>{};
    for (final page in pages) {
      for (final slice in page.slices) {
        final cfi = slice.block.startCfi;
        if (cfi != null && EpubCfi.parse(cfi) != null) {
          unique.add(slice.block);
        }
      }
    }
    return unique.toList()..sort(
      (left, right) =>
          EpubCfi.parse(left.cfiAt(0) ?? left.startCfi!)!
              .compareTo(EpubCfi.parse(right.cfiAt(0) ?? right.startCfi!)!),
    );
  }

  static (int, int)? _range(PageBlock block, EpubCfi start, EpubCfi end) {
    final range = block.rangeForCfis(start.serialize(), end.serialize());
    if (range == null) return null;
    final length = block.layout.text.length;
    final clippedFrom = range.$1.clamp(0, length);
    final clippedTo = range.$2.clamp(0, length);
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
