import 'dart:ui' as ui;

import 'package:reader_core/layout/paginator.dart';

/// 单个阅读视口拥有的位图缓存；绘制版本变化时整体失效。
///
/// 预算按全页快照计算：64 MiB 可容纳六张 1080×2400 的 RGBA 快照。
/// 此预算不含原图解码缓存、光栅临时资源和 GPU 驱动开销。
/// Flutter 快照仍占 RGBA 空间；3D 着色器还原 RGB565 采样色阶，
/// 不改变这里的分辨率或实际内存计费。
class PageSnapshotCache {
  PageSnapshotCache({this.maxBytes = 64 * 1024 * 1024, this.maxEntries = 6});

  final int maxBytes;
  final int maxEntries;
  final _images = <PageContent, ui.Image>{};
  int bytes = 0;
  int _reservedBytes = 0;
  Set<PageContent> protected = {};

  /// 共用预算内的非页面纹理，例如 3D 卷页纸底。
  set reservedBytes(int value) {
    _reservedBytes = value;
    _trim();
  }

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
    while (bytes + _reservedBytes > maxBytes || _images.length > maxEntries) {
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
    _reservedBytes = 0;
  }
}
