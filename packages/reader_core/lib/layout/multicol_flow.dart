import 'dart:math' as math;

import '../css/computed_style.dart';
import 'paginator.dart';

/// 子块仍各自保留文本坐标，只在列边界切行；段落之间连续流动。
class MulticolFlow {
  MulticolFlow(this.content);

  final PageMulticolContent content;
  int _block = 0;
  int _line = 0;
  bool get isDone => _block >= content.blocks.length;

  /// 在不消耗游标的情况下寻找能容纳剩余内容的最小均衡列高。
  double balancedHeight() {
    var upper = 0.0;
    for (var index = _block; index < content.blocks.length; index++) {
      final block = content.blocks[index];
      final start = index == _block ? _line : 0;
      final measured = block.layout.lines
          .skip(start)
          .fold(0.0, (height, line) => height + line.height);
      upper +=
          (start == 0 ? block.leadingExtent : 0) +
          math.max(measured, start == 0 ? block.height : 0) +
          block.trailingExtent;
    }
    upper = math.max(0, upper);
    var lower = upper / content.geometry.count;
    for (var attempt = 0; attempt < 24 && upper - lower > .01; attempt++) {
      final height = (lower + upper) / 2;
      final probe = _fill(height, forceProgress: false);
      if (probe.block >= content.blocks.length) {
        upper = height;
      } else {
        lower = height;
      }
    }
    return upper;
  }

  MulticolBand take(double height, {bool forceProgress = true}) {
    final result = _fill(math.max(0, height), forceProgress: forceProgress);
    _block = result.block;
    _line = result.line;
    return result;
  }

  MulticolBand _fill(double limit, {bool forceProgress = true}) {
    final cursor = _ColumnCursor(_block, _line);
    final pieces = <MulticolPiece>[];
    var tallest = 0.0;
    for (var column = 0; column < content.geometry.count; column++) {
      var top = 0.0;
      while (cursor.block < content.blocks.length) {
        final source = content.blocks[cursor.block];
        if (source.style?.display == CssDisplay.none) {
          cursor.nextBlock();
          continue;
        }
        final piece = _piece(source, cursor.line, (
          column: column,
          top: top,
          limit: limit,
        ), forceProgress);
        if (piece == null) break;
        pieces.add(piece);
        top += piece.height;
        if (piece.endLine >= source.layout.lineCount) {
          cursor.nextBlock();
        } else {
          cursor.line = piece.endLine;
          break;
        }
      }
      tallest = math.max(tallest, top);
      if (cursor.block >= content.blocks.length) break;
    }
    return MulticolBand(pieces, tallest, cursor.block, cursor.line);
  }

  MulticolPiece? _piece(
    PageBlock source,
    int start,
    ({int column, double top, double limit}) position,
    bool forceProgress,
  ) {
    final (:column, :top, :limit) = position;
    final leading = start == 0
        ? source.topInset +
              (top == 0 && (column > 0 || _block > 0)
                  ? math.min(0.0, source.spaceBefore)
                  : source.spaceBefore)
        : 0.0;
    final room = limit - top;
    final atomic =
        source.isReplaced ||
        source.table != null ||
        source.gallery != null ||
        source.isVertical ||
        source.multicolContent != null ||
        (source.height - source.measuredHeight).abs() > .01;
    if (atomic || source.layout.lines.isEmpty) {
      final extent = leading + source.height + source.trailingExtent;
      if ((top > 0 || !forceProgress) && extent > room + .01) return null;
      return MulticolPiece(
        source,
        (start, source.layout.lineCount),
        (column: column, top: top, leading: leading),
        (trailing: source.trailingExtent, height: extent),
        atomic: true,
      );
    }
    return _textPiece(
      source,
      start,
      (column: column, top: top, leading: leading),
      room,
      forceProgress,
    );
  }

  MulticolPiece? _textPiece(
    PageBlock source,
    int start,
    ({int column, double top, double leading}) position,
    double room,
    bool forceProgress,
  ) {
    final (:column, :top, :leading) = position;
    final lines = source.layout.lines;
    final full = leading + source.height + source.trailingExtent;
    if (start == 0 && source.breakInsideAvoid && top > 0 && full > room) {
      return null;
    }
    var end = start;
    var height = leading;
    while (end < lines.length && height + lines[end].height <= room + .01) {
      height += lines[end].height;
      end += 1;
    }
    if (end == start) {
      if (top > 0 || !forceProgress) return null;
      height += lines[end].height;
      end += 1;
    }
    final trailing = end == lines.length
        ? source.trailingExtentForPage(room - height)
        : 0.0;
    return MulticolPiece(
      source,
      (start, end),
      (column: column, top: top, leading: leading),
      (trailing: trailing, height: height + trailing),
    );
  }
}

class _ColumnCursor {
  _ColumnCursor(this.block, this.line);
  int block;
  int line;
  void nextBlock() {
    block += 1;
    line = 0;
  }
}

/// 一页上的列带；游标表示紧接在本页之后的原块与原行。
class MulticolBand {
  const MulticolBand(this.pieces, this.height, this.block, this.line);
  final List<MulticolPiece> pieces;
  final double height;
  final int block;
  final int line;
}

/// 单列内一个原块的片段，所有偏移都以原块为准。
class MulticolPiece {
  const MulticolPiece(
    this.source,
    this.range,
    this.position,
    this.extent, {
    this.atomic = false,
  });
  final PageBlock source;
  final (int, int) range;
  final ({int column, double top, double leading}) position;
  final ({double trailing, double height}) extent;
  final bool atomic;
  int get startLine => range.$1;
  int get endLine => range.$2;
  int get column => position.column;
  double get top => position.top;
  double get leading => position.leading;
  double get trailing => extent.trailing;
  double get height => extent.height;
}
