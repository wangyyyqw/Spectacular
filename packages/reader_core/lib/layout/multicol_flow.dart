import 'dart:math' as math;

import '../css/computed_style.dart';
import 'paginator.dart';

/// 子块仍各自保留文本坐标，只在列边界切行；段落之间连续流动。
class MulticolFlow {
  MulticolFlow(this.content);

  MulticolFlow._resume(this.content, _ColumnCursor cursor)
    : _cursor = cursor.copy();

  final PageMulticolContent content;
  _ColumnCursor _cursor = _ColumnCursor();
  bool get isDone => _cursor.block >= content.blocks.length;

  /// 在不消耗游标的情况下寻找能容纳剩余内容的最小均衡列高。
  double balancedHeight() {
    var upper = _remainingExtent();
    var lower = 0.0;
    for (var attempt = 0; attempt < 24 && upper - lower > .01; attempt++) {
      final height = (lower + upper) / 2;
      final probe = _fill(height, forceProgress: false);
      if (probe._cursor.block >= content.blocks.length || probe.pageBreak) {
        upper = height;
      } else {
        lower = height;
      }
    }
    return upper;
  }

  double _remainingExtent() {
    var extent = 0.0;
    for (var index = _cursor.block; index < content.blocks.length; index++) {
      final block = content.blocks[index];
      if (block.absolute || block.style?.display == CssDisplay.none) continue;
      final current = index == _cursor.block;
      final start = current ? _cursor.line : 0;
      final nested = block.multicolContent;
      final measured = block.layout.lines
          .skip(start)
          .fold(0.0, (height, line) => height + line.height);
      final remaining = nested == null
          ? math.max(measured, start == 0 ? block.height : 0)
          : MulticolFlow._resume(
              nested,
              current ? _cursor.nested ?? _ColumnCursor() : _ColumnCursor(),
            )._remainingExtent();
      extent +=
          (!current || !_cursor.started ? block.leadingExtent : 0) +
          math.max(remaining, !current || !_cursor.started ? block.height : 0) +
          block.trailingExtent;
    }
    return math.max(0, extent);
  }

  MulticolBand take(double height, {bool forceProgress = true}) {
    final result = _fill(math.max(0, height), forceProgress: forceProgress);
    _cursor = result._cursor;
    return result;
  }

  /// 容器声明的盒高参与放置；续片的自然高度按剩余原文重新均衡。
  double heightForContainer(PageBlock source) => _hasHeightConstraint(source)
      ? source.height
      : _naturalContainerHeight(source);

  double _naturalContainerHeight(PageBlock source) =>
      _cursor.isInitial ? source.layout.height : balancedHeight();

  static bool _hasHeightConstraint(PageBlock source) =>
      (source.height - source.measuredHeight).abs() > .01;

  /// room 已扣上留白；末片先预留底装饰，再截断超出页底的正外边距。
  ({MulticolBand band, double trailing}) takeContainerBand(
    PageBlock source,
    double room, {
    required bool forceProgress,
  }) {
    if (_hasHeightConstraint(source) &&
        !forceProgress &&
        source.height + source.bottomInset > room + .01) {
      return (band: MulticolBand._(const [], 0, _cursor.copy()), trailing: 0);
    }
    final (:flow, :band) = _probeContainerBand(source, (
      room: math.max(0, room),
      forceProgress: forceProgress,
    ));
    _cursor = flow._cursor;
    return (
      band: band,
      trailing: isDone ? source.trailingExtentForPage(room - band.height) : 0,
    );
  }

  ({MulticolFlow flow, MulticolBand band}) _probeContainerBand(
    PageBlock source,
    ({double room, bool forceProgress}) constraints,
  ) {
    MulticolFlow resume() => MulticolFlow._resume(content, _cursor);
    var flow = resume();
    final balanced = _naturalContainerHeight(source);
    final constrained = _hasHeightConstraint(source);
    var band = flow.take(
      constrained || balanced + source.trailingExtent <= constraints.room + .01
          ? balanced
          : constraints.room,
      forceProgress: constraints.forceProgress,
    );
    if (flow.isDone && constrained) {
      band = band._withHeight(source.height);
    } else if (flow.isDone &&
        band.height + source.bottomInset > constraints.room + .01) {
      final retry = resume();
      final fitted = retry.take(
        math.max(0.0, constraints.room - source.bottomInset),
        forceProgress: false,
      );
      if (fitted.pieces.isNotEmpty || !constraints.forceProgress) {
        flow = retry;
        band = fitted;
      }
    }
    return (flow: flow, band: band);
  }

  MulticolBand _fill(double limit, {bool forceProgress = true}) {
    final cursor = _cursor.copy();
    final pieces = <MulticolPiece>[];
    var tallest = 0.0;
    var pageBreak = false;
    for (var column = 0; column < content.geometry.count; column++) {
      final filled = _fillColumn(cursor, column, limit, forceProgress);
      pieces.addAll(filled.pieces);
      tallest = math.max(tallest, filled.height);
      pageBreak = filled.pageBreak;
      if (pageBreak || cursor.block >= content.blocks.length) break;
    }
    return MulticolBand._(pieces, tallest, cursor, pageBreak: pageBreak);
  }

  ({List<MulticolPiece> pieces, double height, bool pageBreak}) _fillColumn(
    _ColumnCursor cursor,
    int column,
    double limit,
    bool forceProgress,
  ) {
    final pieces = <MulticolPiece>[];
    var top = 0.0;
    var pageBreak = false;
    while (cursor.block < content.blocks.length) {
      final source = content.blocks[cursor.block];
      if (source.style?.display == CssDisplay.none) {
        cursor.nextBlock();
        continue;
      }
      if (_breakBefore(source, cursor)) {
        pageBreak = true;
        break;
      }
      final step = _nextPiece(source, cursor, (
        column: column,
        top: top,
        limit: limit,
      ), forceProgress);
      final piece = step.piece;
      if (piece != null) {
        pieces.add(piece);
        if (!source.absolute) top += piece.height;
      }
      pageBreak = step.pageBreak;
      if (pageBreak || piece == null || !piece.endsBlock) break;
    }
    return (pieces: pieces, height: top, pageBreak: pageBreak);
  }

  bool _breakBefore(PageBlock source, _ColumnCursor cursor) {
    if (source.absolute ||
        cursor.started ||
        cursor.beforeHandled ||
        !source.pageBreakBefore) {
      return false;
    }
    cursor.beforeHandled = true;
    return true;
  }

  ({MulticolPiece? piece, bool pageBreak}) _nextPiece(
    PageBlock source,
    _ColumnCursor cursor,
    ({int column, double top, double limit}) position,
    bool forceProgress,
  ) {
    if (source.multicolContent != null && !source.absolute) {
      return _nestedPiece(source, cursor, position, forceProgress);
    }
    final piece = _piece(source, cursor.line, position, forceProgress);
    if (piece == null) return (piece: null, pageBreak: false);
    if (piece.endsBlock) {
      cursor.nextBlock();
    } else {
      cursor.line = piece.endLine;
      cursor.started = true;
    }
    return (
      piece: piece,
      pageBreak: !source.absolute && piece.endsBlock && source.pageBreakAfter,
    );
  }

  double _leading(PageBlock source, bool first, int column, double top) =>
      !first
      ? 0.0
      : source.topInset +
            (top == 0 && (column > 0 || _cursor.block > 0)
                ? math.min(0.0, source.spaceBefore)
                : source.spaceBefore);

  // 取片和父子游标提交保留在同一流程，避免递归续排只更新一层状态。
  ({MulticolPiece? piece, bool pageBreak}) _nestedPiece(
    PageBlock source,
    _ColumnCursor cursor,
    ({int column, double top, double limit}) position,
    bool forceProgress,
  ) {
    final first = !cursor.started;
    final leading = _leading(source, first, position.column, position.top);
    final room = math.max(0.0, position.limit - position.top - leading);
    final flow = MulticolFlow._resume(
      source.multicolContent!,
      cursor.nested ?? _ColumnCursor(),
    );
    if (first &&
        source.breakInsideAvoid &&
        position.top > 0 &&
        flow.heightForContainer(source) + source.trailingExtent > room + .01) {
      return (piece: null, pageBreak: false);
    }
    final (:band, :trailing) = flow.takeContainerBand(
      source,
      room,
      forceProgress: forceProgress && position.top == 0,
    );
    cursor.nested = flow._cursor;
    final last = flow.isDone;
    final piece = band.pieces.isEmpty
        ? null
        : MulticolPiece(
            source,
            (0, 0),
            (column: position.column, top: position.top, leading: leading),
            (trailing: trailing, height: leading + band.height + trailing),
            nested: (band: band, first: first, last: last),
          );
    if (last) {
      cursor.nextBlock();
    } else if (piece != null) {
      cursor.started = true;
    }
    return (
      piece: piece,
      pageBreak: band.pageBreak || last && source.pageBreakAfter,
    );
  }

  MulticolPiece? _piece(
    PageBlock source,
    int start,
    ({int column, double top, double limit}) position,
    bool forceProgress,
  ) {
    final (:column, :top, :limit) = position;
    final leading = _leading(source, start == 0, column, top);
    final room = limit - top;
    final atomic =
        source.absolute ||
        source.isReplaced ||
        source.table != null ||
        source.gallery != null ||
        source.isVertical ||
        (source.height - source.measuredHeight).abs() > .01;
    if (atomic || source.layout.lines.isEmpty) {
      final extent = leading + source.height + source.trailingExtent;
      if (!source.absolute &&
          (top > 0 || !forceProgress) &&
          extent > room + .01) {
        return null;
      }
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
    while (end < lines.length) {
      final bottom = end + 1 == lines.length ? source.bottomInset : 0.0;
      if (height + lines[end].height + bottom > room + .01) break;
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
  int block = 0;
  int line = 0;
  bool started = false;
  bool beforeHandled = false;
  _ColumnCursor? nested;

  bool get isInitial =>
      block == 0 && line == 0 && !started && !beforeHandled && nested == null;

  _ColumnCursor copy() => _ColumnCursor()
    ..block = block
    ..line = line
    ..started = started
    ..beforeHandled = beforeHandled
    ..nested = nested?.copy();

  void nextBlock() {
    block += 1;
    line = 0;
    started = beforeHandled = false;
    nested = null;
  }
}

/// 一页上的列带；游标表示紧接在本页之后的原块与原行。
class MulticolBand {
  const MulticolBand._(
    this.pieces,
    this.height,
    this._cursor, {
    this.pageBreak = false,
  });
  final List<MulticolPiece> pieces;
  final double height;
  final _ColumnCursor _cursor;
  final bool pageBreak;

  MulticolBand _withHeight(double height) =>
      MulticolBand._(pieces, height, _cursor, pageBreak: pageBreak);
}

/// 单列内一个原块的片段，所有偏移都以原块为准。
class MulticolPiece {
  const MulticolPiece(
    this.source,
    this.range,
    this.position,
    this.extent, {
    this.atomic = false,
    this.nested,
  });
  final PageBlock source;
  final (int, int) range;
  final ({int column, double top, double leading}) position;
  final ({double trailing, double height}) extent;
  final bool atomic;
  final ({MulticolBand band, bool first, bool last})? nested;
  bool get startsBlock => nested?.first ?? startLine == 0;
  bool get endsBlock => nested?.last ?? endLine >= source.layout.lineCount;
  int get startLine => range.$1;
  int get endLine => range.$2;
  int get column => position.column;
  double get top => position.top;
  double get leading => position.leading;
  double get trailing => extent.trailing;
  double get height => extent.height;
}
