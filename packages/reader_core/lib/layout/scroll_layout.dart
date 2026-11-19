import 'dart:math' as math;

import 'paginator.dart';

/// 连续滚动中的一页切片。
///
/// 保留原分页的换行结果，压缩页间空白并补回接缝处被裁掉的行高留白，
/// 因此滚动时不会重新断行，段内行距也不受分页边界影响。
class ScrollPageSegment {
  const ScrollPageSegment({
    required this.pageIndex,
    required this.content,
    required this.extent,
  });

  final int pageIndex;
  final PageContent content;
  final double extent;
}

/// 一章可直接供懒构建列表使用的连续滚动布局。
class ScrollChapterLayout {
  const ScrollChapterLayout({required this.spineIndex, required this.segments});

  final int spineIndex;
  final List<ScrollPageSegment> segments;

  double get extent {
    var total = 0.0;
    for (final segment in segments) {
      total += segment.extent;
    }
    return total;
  }

  bool get isEmpty => segments.isEmpty;

  double offsetOfPage(int pageIndex) {
    var offset = 0.0;
    for (final segment in segments) {
      if (segment.pageIndex >= pageIndex) break;
      offset += segment.extent;
    }
    return offset;
  }

  int pageAtOffset(double offset) {
    if (segments.isEmpty) return 0;
    var top = 0.0;
    for (final segment in segments) {
      final bottom = top + segment.extent;
      if (offset < bottom) return segment.pageIndex;
      top = bottom;
    }
    return segments.last.pageIndex;
  }

  /// 适配页间留白与文字裁边，不合并或重新断行。
  factory ScrollChapterLayout.fromPages(
    int spineIndex,
    List<PageContent> pages,
  ) {
    final segments = <ScrollPageSegment>[];
    final visible = pages.where((page) => !page.isEmpty).toList();
    for (var index = 0; index < visible.length; index++) {
      segments.add(
        _compact(
          visible[index],
          first: index == 0,
          last: index == visible.length - 1,
        ),
      );
    }
    return ScrollChapterLayout(
      spineIndex: spineIndex,
      segments: List<ScrollPageSegment>.unmodifiable(segments),
    );
  }

  static ScrollPageSegment _compact(
    PageContent page, {
    required bool first,
    required bool last,
  }) {
    final topPadding = first ? page.topPadding : 0.0;
    var flowY = topPadding;
    var bottom = flowY;
    var restored = 0.0;
    final slices = <PageBlockSlice>[];
    for (final original in page.slices) {
      final slice = _restoreTextEdges(original, top: !first, bottom: !last);
      slices.add(slice);
      restored += slice.height - original.height;
      if (slice.overlay) {
        bottom = math.max(
          bottom,
          topPadding + (slice.absoluteTop ?? 0) + slice.height,
        );
      } else {
        flowY += slice.height;
        bottom = math.max(bottom, flowY);
      }
    }
    bottom = math.max(bottom, topPadding + page.usedHeight + restored);
    final extent = math.max(0.0, bottom);
    return ScrollPageSegment(
      pageIndex: page.pageIndex,
      extent: extent,
      content: PageContent(
        spineIndex: page.spineIndex,
        pageIndex: page.pageIndex,
        slices: restored == 0 ? page.slices : List.unmodifiable(slices),
        usedHeight: math.max(0, extent - topPadding),
        pageHeight: extent,
        topPadding: topPadding,
        background: page.background,
      ),
    );
  }

  static PageBlockSlice _restoreTextEdges(
    PageBlockSlice slice, {
    required bool top,
    required bool bottom,
  }) {
    final before = top && !slice.overlay ? slice.textTopTrim : 0.0;
    final after = bottom && !slice.overlay ? slice.textBottomTrim : 0.0;
    if (before == 0 && after == 0) return slice;
    return PageBlockSlice(
      block: slice.block,
      startLine: slice.startLine,
      endLine: slice.endLine,
      height: slice.height + before + after,
      leadingExtent: slice.leadingExtent + before,
      trailingExtent: slice.trailingExtent + after,
      leftInset: slice.leftInset,
      overlay: slice.overlay,
      absoluteTop: slice.absoluteTop,
      textTopTrim: slice.textTopTrim - before,
      textBottomTrim: slice.textBottomTrim - after,
    );
  }
}
