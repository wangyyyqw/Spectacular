import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'image_size.dart';

/// 图片字节加载器（宿主负责从 EPUB 归档/文件系统读取，失败返回 null）。
typedef ImageBytesLoader = Future<Uint8List?> Function(String url);

/// 图片解码缓存（P3 图片管线，§50.2 六环节）。
///
/// - 键为 `url`，同一 URL 的解码结果复用；按 LRU 淘汰，受条数与字节上限约束；
/// - 解码时按 `显示宽 × DPR` 调用 `instantiateImageCodec(targetWidth:)` 降采样，
///   并**封顶原图宽**（不放大，§50.2 目标像素尺寸口径）；原始尺寸单独缓存，
///   排版算占位不等解码（§50.3 优化 3，P3-07）；
/// - 并发去重：同一 URL 的在途解码复用同一 Future（§50.3 优化 2）；
/// - 绘制路径用同步的 [lookup] 取已解码图片，未解码时由调用方画占位。
class DecodedImageCache {
  /// 创建缓存。
  DecodedImageCache({
    required this.loadBytes,
    this.maxEntries = 16,
    this.maxBytes = 48 << 20,
  });

  /// 字节加载器。
  final ImageBytesLoader loadBytes;

  /// 条数上限。
  final int maxEntries;

  /// 当前缓存条目数（P4-32 缓存报告用）。
  int get entryCount => _entries.length;

  /// 解码后字节上限（按 `宽 × 高 × 4` 估算）。
  final int maxBytes;

  final LinkedHashMap<String, _CacheEntry> _entries =
      LinkedHashMap<String, _CacheEntry>();
  final Map<String, Future<ui.Image?>> _pending = <String, Future<ui.Image?>>{};
  /// 原始尺寸缓存（P3-07）：键 url；读过头后不再重复解析。
  final Map<String, ImageIntrinsicSize?> _intrinsic =
      <String, ImageIntrinsicSize?>{};
  int _bytes = 0;
  int _revision = 0;

  /// 当前缓存条数。
  int get length => _entries.length;

  /// 当前估算字节数。
  int get byteCount => _bytes;

  /// 缓存版本号（每解码成功一次 +1，宿主可用它触发重绘）。
  int get revision => _revision;

  /// 原始尺寸（已读过头则直接返回）；未读过且字节在途时返回 null。
  ImageIntrinsicSize? intrinsicOf(String url) => _intrinsic[url];

  /// 同步取已解码图片；未命中返回 null（并提升 LRU 顺序）。
  ui.Image? lookup(String url) {
    final entry = _entries.remove(url);
    if (entry == null) {
      return null;
    }
    _entries[url] = entry;
    return entry.image;
  }

  /// 解码并缓存一张图片。
  ///
  /// [displayWidth] 是布局宽（逻辑像素），[devicePixelRatio] 用于换算物理像素，
  /// 封顶原图宽（P3-08）；[fullResolution] 为 true 时跳过降采样按原图宽解码
  /// （P3-11 原图预览专用，调用方应使用独立缓存实例避免挤占阅读缓存）；
  /// 字节缺失或解码失败返回 null，不抛异常（容错：§12）。
  Future<ui.Image?> load(
    String url, {
    required double displayWidth,
    double devicePixelRatio = 1,
    bool fullResolution = false,
  }) {
    final cached = lookup(url);
    if (cached != null) {
      return Future<ui.Image?>.value(cached);
    }
    final pending = _pending[url];
    if (pending != null) {
      return pending;
    }
    final future = _decodeAndStore(
      url,
      fullResolution ? double.infinity : displayWidth * devicePixelRatio,
    );
    _pending[url] = future;
    return future.whenComplete(() => _pending.remove(url));
  }

  /// 批量预取；返回本次新解码成功的张数。
  Future<int> prefetch(
    Iterable<String> urls, {
    required double displayWidth,
    double devicePixelRatio = 1,
  }) async {
    var decoded = 0;
    for (final url in urls.toSet()) {
      final had = lookup(url) != null;
      final image = await load(
        url,
        displayWidth: displayWidth,
        devicePixelRatio: devicePixelRatio,
      );
      if (!had && image != null) {
        decoded += 1;
      }
    }
    return decoded;
  }

  /// 清空并释放全部解码图片。
  void clear() {
    for (final entry in _entries.values) {
      entry.image.dispose();
    }
    _entries.clear();
    _bytes = 0;
  }

  Future<ui.Image?> _decodeAndStore(String url, double target) async {
    try {
      final bytes = await loadBytes(url);
      if (bytes == null || bytes.isEmpty) {
        return null;
      }
      // 封顶原图宽（P3-08，§50.2）：显示宽×DPR 超过原图时不放大解码；
      // 原始尺寸顺手缓存（§50.3 优化 3）。
      var intrinsic = _intrinsic[url];
      if (!_intrinsic.containsKey(url)) {
        intrinsic = ImageSizeParser.readImageSize(bytes);
        _intrinsic[url] = intrinsic;
      }
      var targetWidth = target.isFinite ? math.max(1, target.ceil()) : 0;
      if (intrinsic != null && (targetWidth == 0 || targetWidth > intrinsic.width)) {
        targetWidth = intrinsic.width;
      }
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth > 0 ? targetWidth : null,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      final image = frame.image;
      _store(url, image);
      _revision += 1;
      return image;
    } catch (_) {
      // 损坏图片/不支持格式：降级为无图，不阻断阅读。
      return null;
    }
  }

  void _store(String url, ui.Image image) {
    final old = _entries.remove(url);
    if (old != null) {
      _bytes -= old.byteSize;
      old.image.dispose();
    }
    final byteSize = image.width * image.height * 4;
    _entries[url] = _CacheEntry(image, byteSize);
    _bytes += byteSize;
    _evictIfNeeded();
  }

  void _evictIfNeeded() {
    while (_entries.length > maxEntries ||
        (_bytes > maxBytes && _entries.isNotEmpty)) {
      final oldest = _entries.keys.first;
      final entry = _entries.remove(oldest);
      if (entry != null) {
        _bytes -= entry.byteSize;
        entry.image.dispose();
      }
    }
  }
}

class _CacheEntry {
  const _CacheEntry(this.image, this.byteSize);

  final ui.Image image;
  final int byteSize;
}
