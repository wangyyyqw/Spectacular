import 'dart:ui' as ui;

import 'package:reader_core/layout/paginator.dart';

/// 单个阅读视口拥有的位图缓存；绘制版本变化时整体失效。
class PageSnapshotCache {
  PageSnapshotCache({this.maxBytes = 16 * 1024 * 1024});

  final int maxBytes;
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
    while (bytes > maxBytes || _images.length > 3) {
      final candidates = _images.keys.where((key) => !protected.contains(key));
      if (candidates.isEmpty) break;
      _release(_images.remove(candidates.first)!);
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
