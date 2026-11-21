import 'dart:ui' as ui;

import 'package:reader_core/layout/paginator.dart';

/// 单个阅读视口拥有的位图缓存；绘制版本变化时整体失效。
///
/// 默认保留当前页及前后各两页，不按字节数淘汰或降低快照分辨率。
/// bytes 仅统计页面 RGBA 位图，不含纸底、原图解码和 GPU 临时资源。
class PageSnapshotCache {
  PageSnapshotCache({this.maxEntries = 5});

  final int maxEntries;
  final _images = <PageContent, ui.Image>{};
  int bytes = 0;
  Set<PageContent> protected = {};

  int get length => _images.length;

  ui.Image? get(PageContent page) {
    final image = _images.remove(page);
    if (image != null) _images[page] = image;
    return image;
  }

  void put(PageContent page, ui.Image image) {
    final previous = _images.remove(page);
    if (previous != null) _release(previous);
    _images[page] = image;
    bytes += image.width * image.height * 4;
    _trim();
  }

  void _trim() {
    while (_images.length > maxEntries) {
      final candidates = _images.keys.where((key) => !protected.contains(key));
      if (candidates.isEmpty) break;
      _release(_images.remove(candidates.first)!);
    }
  }

  /// 保留窗口交集和活动翻页仍在引用的快照。
  void retainPages(Set<PageContent> pages) {
    for (final page in _images.keys.toList()) {
      if (!pages.contains(page) && !protected.contains(page)) {
        _release(_images.remove(page)!);
      }
    }
  }

  /// 静止时只刷新命中的纸面，例如总页数已确定的章节。
  void removeWhere(bool Function(PageContent) matches) {
    for (final page in _images.keys.toList()) {
      if (matches(page)) _release(_images.remove(page)!);
    }
  }

  void _release(ui.Image image) {
    bytes -= image.width * image.height * 4;
    image.dispose();
  }

  /// 调用前必须先撤下活动帧的图片引用。
  void clear() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    protected.clear();
    bytes = 0;
  }
}
