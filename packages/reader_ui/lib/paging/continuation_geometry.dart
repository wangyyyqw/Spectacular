import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_edges.dart';

/// 接续的一行或完整装饰块快照；裁剪沿行间留白切分，保留原始墨迹。
class ContinuationPartGeometry {
  const ContinuationPartGeometry({required this.clip, required this.bounds});

  final Rect clip;
  final Rect bounds;
}

/// 基于正式分页切片与共享字形边界确定安全条带，不改变分页或文本位置。
class ContinuationPageGeometry {
  const ContinuationPageGeometry({
    required this.parts,
    required this.body,
    this.vertical = false,
  });

  final List<ContinuationPartGeometry> parts;
  final Rect body;
  final bool vertical;

  factory ContinuationPageGeometry.resolve(
    PageContent? page,
    Size size, {
    EdgeInsets pageInsets = EdgeInsets.zero,
  }) {
    final sheet = Offset.zero & size;
    final body = Rect.fromLTWH(
      pageInsets.left,
      pageInsets.top,
      math.max(1, size.width - pageInsets.horizontal),
      math.max(1, size.height - pageInsets.vertical),
    );
    ContinuationPageGeometry whole() => ContinuationPageGeometry(
      body: body,
      parts: [ContinuationPartGeometry(clip: sheet, bounds: body)],
    );
    if (page == null || page.slices.isEmpty || page.background != null) {
      return whole();
    }
    // 阴影、滤镜与变换可越出分页盒；完整保留原纸面的合成结果。
    if (page.slices.any(
      (slice) =>
          _hasUnboundedEffects(slice.block.style) ||
          slice.block.layout.runs.any(
            (run) => _hasUnboundedEffects(run.style) || run.baselineShift != 0,
          ) ||
          slice.block.containers.any(
            (fragment) => _hasUnboundedEffects(fragment.container.style),
          ),
    )) {
      return whole();
    }
    bool isVertical(PageBlockSlice slice) =>
        slice.block.layout.isVertical ||
        slice.lines.any((line) => line.vertical);
    final vertical = page.slices.every(isVertical);
    if (!vertical && page.slices.any(isVertical)) return whole();
    if (vertical &&
        page.slices.any(
          (slice) =>
              slice.overlay ||
              slice.block.isReplaced ||
              slice.block.table != null ||
              slice.block.gallery != null ||
              slice.block.multicolContent != null ||
              (slice.block.rubies?.isNotEmpty ?? false) ||
              (slice.block.style?.hasTextEmphasis ?? false) ||
              slice.block.layout.runs.any((run) => run.style.hasTextEmphasis),
        )) {
      return whole();
    }
    final bands = <_Band>[];
    var y = page.topPadding;
    for (final slice in page.slices) {
      final block = slice.block;
      final style = block.style;
      final top = slice.overlay ? slice.absoluteTop ?? y : y;
      final owners = <Object>{
        if (block.groupId != 0) block.groupId,
        for (final fragment in block.containers)
          if (_hasSharedDecoration(
            fragment.container.style,
            pageRoot: fragment.container.isPageRoot,
          ))
            fragment.container,
      };
      if (vertical) {
        if (_hasSharedDecoration(style)) owners.add(block);
        final left =
            pageInsets.left +
            slice.leftInset +
            (style?.margin.left ?? 0) +
            block.verticalColumnOffset;
        for (final line in slice.lines) {
          final x = left + (line.columnX ?? line.offsetX);
          bands.add(_Band(x, x + line.width, Set.of(owners)));
        }
      } else {
        var start = top + slice.leadingExtent;
        var end = top + slice.height - slice.trailingExtent;
        final decorated =
            _hasSharedDecoration(style) ||
            block.containerSides ||
            block.isReplaced ||
            block.table != null ||
            block.gallery != null ||
            block.multicolContent != null ||
            block.bleedTop ||
            block.bleedBottom;
        if (decorated) {
          start -= block.topInset;
          end += block.bottomInset;
        }
        // 注音、着重号和大字号行内内容可以超出行框，切口留在它们之外。
        var overhang = 2.0;
        if ((block.rubies?.isNotEmpty ?? false) ||
            (style?.hasTextEmphasis ?? false)) {
          overhang = math.max(overhang, (style?.fontSize ?? 16) * 0.75);
        }
        for (final run in block.layout.runs) {
          if (run.style.hasTextEmphasis || run.style.borders.hasBorder) {
            overhang = math.max(overhang, run.style.fontSize * 0.75);
          }
        }
        if (!decorated && slice.lines.isNotEmpty) {
          bands.addAll(
            _textLineBands(slice, pageInsets.top + start, overhang, owners),
          );
        } else {
          if (block.bleedTop) start = -pageInsets.top;
          if (block.bleedBottom) end = size.height - pageInsets.top;
          bands.add(
            _Band(
              pageInsets.top + start - overhang,
              pageInsets.top + end + overhang,
              owners,
            ),
          );
        }
      }
      if (!slice.overlay) y += slice.height;
    }
    final extent = vertical ? size.width : size.height;
    bands.removeWhere(
      (band) =>
          !band.start.isFinite ||
          !band.end.isFinite ||
          band.end <= 0 ||
          band.start >= extent,
    );
    if (bands.isEmpty) return whole();
    // 浮动、负段距与共用容器装饰的区域合为原子条带，避免切断同一张图或边框。
    _mergeBands(bands);
    bands.sort((a, b) => a.start.compareTo(b.start));
    final parts = <ContinuationPartGeometry>[];
    var edge = 0.0;
    for (var index = 0; index < bands.length; index++) {
      final band = bands[index];
      final end = index + 1 == bands.length
          ? extent
          : ((band.end + bands[index + 1].start) / 2).clamp(edge, extent);
      if (end <= edge) continue;
      final from = band.start.clamp(0.0, extent);
      final to = band.end.clamp(from, extent);
      parts.add(
        ContinuationPartGeometry(
          clip: vertical
              ? Rect.fromLTRB(edge, 0, end, size.height)
              : Rect.fromLTRB(0, edge, size.width, end),
          bounds: vertical
              ? Rect.fromLTRB(from, body.top, to, body.bottom)
              : Rect.fromLTRB(body.left, from, body.right, to),
        ),
      );
      edge = end;
    }
    return ContinuationPageGeometry(
      body: body,
      vertical: vertical,
      parts: List.unmodifiable(parts),
    );
  }

  /// 同一行由旧内容先让位、新内容再进入；按实际空间边界错峰。
  double progressFor(
    ContinuationPartGeometry part,
    double progress, {
    required bool outgoing,
    required double direction,
  }) {
    final double rank;
    if (vertical) {
      final column = direction < 0
          ? 1 -
                ((outgoing ? part.bounds.right : part.bounds.left) -
                        body.left) /
                    body.width
          : ((outgoing ? part.bounds.left : part.bounds.right) - body.left) /
                body.width;
      rank = (outgoing ? 0.0 : 0.5) + 0.5 * column.clamp(0.0, 1.0);
    } else {
      rank =
          ((outgoing ? part.bounds.top : part.bounds.bottom) - body.top) /
          body.height;
    }
    final start = 0.02 + 0.18 * rank.clamp(0.0, 1.0);
    return Interval(
      start,
      start + 0.80,
      curve: Curves.easeInOutSine,
    ).transform(progress.clamp(0.0, 1.0));
  }
}

Iterable<_Band> _textLineBands(
  PageBlockSlice slice,
  double top,
  double overhang,
  Set<Object> owners,
) sync* {
  final layout = slice.block.layout;
  final style = slice.block.style;
  var lineTop = top;
  for (final line in slice.lines) {
    final edges = style == null
        ? const PageTextEdges()
        : textLineEdges(layout, line, style);
    // 普通正文的缓冲限于行框内留白，避免中文字体因留白较少重新合并成段。
    // 注音、着重号和边框的真实外溢仍保留，交由条带合并保护。
    final topPadding = overhang <= 2 ? math.min(overhang, edges.top) : overhang;
    final bottomPadding = overhang <= 2
        ? math.min(overhang, edges.bottom)
        : overhang;
    yield _Band(
      lineTop + edges.top - topPadding,
      lineTop +
          line.height -
          edges.bottom +
          edges.bottomOverflow +
          bottomPadding,
      Set.of(owners),
    );
    lineTop += line.height;
  }
}

bool _hasUnboundedEffects(ComputedStyle? style) =>
    style != null &&
    (style.boxShadow != null ||
        style.textShadow.isNotEmpty ||
        style.outline.isVisible ||
        style.filters.isNotEmpty ||
        style.backdropFilters.isNotEmpty ||
        style.transforms.isNotEmpty ||
        style.clipPath != null);

bool _hasSharedDecoration(ComputedStyle? style, {bool pageRoot = false}) =>
    style != null &&
    (style.borders.hasBorder ||
        style.borderImage != null ||
        (!pageRoot &&
            (style.backgroundColor.a > 0 ||
                style.backgroundLayers.isNotEmpty ||
                style.opacity < 1)));

class _Band {
  _Band(this.start, this.end, this.owners);

  double start;
  double end;
  final Set<Object> owners;

  bool joins(_Band other) =>
      (start < other.end && other.start < end) ||
      owners.any(other.owners.contains);

  void include(_Band other) {
    start = math.min(start, other.start);
    end = math.max(end, other.end);
    owners.addAll(other.owners);
  }
}

void _mergeBands(List<_Band> bands) {
  var merged = true;
  while (merged) {
    merged = false;
    for (var index = 0; index < bands.length; index++) {
      for (var next = index + 1; next < bands.length; next++) {
        if (!bands[index].joins(bands[next])) continue;
        bands[index].include(bands.removeAt(next));
        merged = true;
        next--;
      }
    }
  }
}
