import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 图片字节加载器（宿主负责从 EPUB 归档/文件系统读取，失败返回 null）。
typedef ImageBytesLoader = Future<Uint8List?> Function(String url);

/// 图片解码缓存（P3 图片管线的最小实现）。
///
/// - 键为 `url`，同一 URL 的解码结果复用；按 LRU 淘汰，受条数与字节上限约束；
/// - 解码时按 `显示宽 × DPR` 调用 `instantiateImageCodec(targetWidth:)` 降采样，
///   避免大图整张进内存（技术方案 §50.3）；
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

  /// 解码后字节上限（按 `宽 × 高 × 4` 估算）。
  final int maxBytes;

  final LinkedHashMap<String, _CacheEntry> _entries =
      LinkedHashMap<String, _CacheEntry>();
  final Map<String, Future<ui.Image?>> _pending = <String, Future<ui.Image?>>{};
  int _bytes = 0;
  int _revision = 0;

  /// 当前缓存条数。
  int get length => _entries.length;

  /// 当前估算字节数。
  int get byteCount => _bytes;

  /// 缓存版本号（每解码成功一次 +1，宿主可用它触发重绘）。
  int get revision => _revision;

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
  /// [displayWidth] 是布局宽（逻辑像素），[devicePixelRatio] 用于换算物理像素；
  /// 字节缺失或解码失败返回 null，不抛异常（容错：§12）。
  Future<ui.Image?> load(
    String url, {
    required double displayWidth,
    double devicePixelRatio = 1,
  }) {
    final cached = lookup(url);
    if (cached != null) {
      return Future<ui.Image?>.value(cached);
    }
    final pending = _pending[url];
    if (pending != null) {
      return pending;
    }
    final targetWidth = math.max(1, (displayWidth * devicePixelRatio).ceil());
    final future = _decodeAndStore(url, targetWidth);
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

  Future<ui.Image?> _decodeAndStore(String url, int targetWidth) async {
    try {
      final bytes = await loadBytes(url);
      if (bytes == null || bytes.isEmpty) {
        return null;
      }
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
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
