import 'dart:math' as math;

import 'paginator.dart';

/// 连续滚动中的一页切片。
///
/// 保留原分页的换行结果，只压缩分页器为页首/页尾留下的空白，因此滚动时
/// 行不会重新断行，也不会因模式切换改变正文排版指纹。
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

  /// 只压缩页间留白，不合并或重排块切片。
  factory ScrollChapterLayout.fromPages(
    int spineIndex,
    List<PageContent> pages,
  ) {
    final segments = <ScrollPageSegment>[];
    var firstSegment = true;
    for (final page in pages) {
      if (page.isEmpty) continue;
      segments.add(
        _compact(page, topPadding: firstSegment ? page.topPadding : 0),
      );
      firstSegment = false;
    }
    return ScrollChapterLayout(
      spineIndex: spineIndex,
      segments: List<ScrollPageSegment>.unmodifiable(segments),
    );
  }

  static ScrollPageSegment _compact(
    PageContent page, {
    required double topPadding,
  }) {
    var flowY = topPadding;
    var bottom = flowY;
    for (final slice in page.slices) {
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
    bottom = math.max(bottom, topPadding + page.usedHeight);
    final extent = math.max(0.0, bottom);
    return ScrollPageSegment(
      pageIndex: page.pageIndex,
      extent: extent,
      content: PageContent(
        spineIndex: page.spineIndex,
        pageIndex: page.pageIndex,
        slices: page.slices,
        usedHeight: math.max(0, extent - topPadding),
        pageHeight: extent,
        topPadding: topPadding,
        background: page.background,
      ),
    );
  }
}
