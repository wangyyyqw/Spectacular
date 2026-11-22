import 'dart:math' as math;
import 'dart:ui';

import 'image_cache.dart';

/// 图片绘制埋点（P3-09）：解码不进入手势→帧路径，
/// 「占位帧数」与「替换耗时」分开记录。
class ImagePaintMetrics {
  int placeholderCount = 0;
  int drawnCount = 0;
  final List<int> _replaceStartMs = <int>[];

  /// 记录一次占位（含时间戳，替换成功时结算耗时）。
  void recordPlaceholder(String url, {int? nowMs}) {
    placeholderCount += 1;
    if (nowMs != null) {
      _replaceStartMs.add(nowMs);
    }
  }

  /// 记录一次成图；与最近一次占位结算替换耗时。
  int? recordDrawn({int? nowMs}) {
    drawnCount += 1;
    if (nowMs != null && _replaceStartMs.isNotEmpty) {
      return nowMs - _replaceStartMs.removeAt(0);
    }
    return null;
  }

  /// 清零（换书/换章）。
  void reset() {
    placeholderCount = 0;
    drawnCount = 0;
    _replaceStartMs.clear();
  }
}

/// 图片块绘制（P3-09）。
///
/// - 缓存命中：`drawImageRect` 直接画（显示尺寸在布局期已按 P3-07
///   算好，这里按目标矩形等比铺满）；
/// - 未命中：画占位块并 fire-and-forget 触发解码——**解码不阻塞分页
///   与绘制**（布局只用 P3-07 的尺寸缓存），解码完成后宿主监听
///   [DecodedImageCache.revision] 重绘替换；
/// - 字节缺失/解码失败：占位块长期保留（§50.2 失败降级：占位框）。
abstract final class ImageBlockPainter {
  /// 占位底色。
  static const Color placeholderFill = Color(0xFFE8E8E8);

  /// 占位描边。
  static const Color placeholderBorder = Color(0xFFBDBDBD);

  /// 绘制一帧：命中画图返回 true，未命中画占位返回 false。
  ///
  /// [rect] 为布局期算好的显示矩形（已含对齐与边距修正）。
  static bool paint(
    Canvas canvas,
    Rect rect, {
    required String url,
    required DecodedImageCache cache,
    ImagePaintMetrics? metrics,
    int? nowMs,
  }) {
    final image = cache.lookup(url);
    if (image == null) {
      _paintPlaceholder(canvas, rect);
      metrics?.recordPlaceholder(url, nowMs: nowMs);
      // fire-and-forget：解码完成后由宿主按 revision 触发重绘。
      cache.load(url, displayWidth: rect.width);
      return false;
    }
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.drawImageRect(image, src, rect, Paint());
    metrics?.recordDrawn(nowMs: nowMs);
    return true;
  }

  static void _paintPlaceholder(Canvas canvas, Rect rect) {
    final rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(2),
    );
    canvas.drawRRect(rrect, Paint()..color = placeholderFill);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = placeholderBorder,
    );
  }
}

/// 图页满屏判定（P3-10 的前置工具，放这里避免循环依赖）。
abstract final class ImagePageDetector {
  /// 章节是否为「仅含一张无宽高属性图片」的满屏页。
  ///
  /// [imageCount] 章节内 img 数量；[hasText] 章节是否含非空白正文；
  /// 双图及以上或含正文走普通路径（§8.6）。
  static bool isFullBleedPage({
    required int imageCount,
    required bool hasText,
  }) {
    if (imageCount != 1 || hasText) {
      return false;
    }
    return true;
  }
}

/// 等比适配工具（绘制期兜底，布局期结果异常时使用）。
abstract final class ImageFit {
  /// 在 [bounds] 内等比 contain 放置 [src]，返回目标矩形（居中）。
  static Rect contain(Rect bounds, Image image) {
    final scale = math.min(
      bounds.width / image.width,
      bounds.height / image.height,
    );
    final width = image.width * scale;
    final height = image.height * scale;
    return Rect.fromLTWH(
      bounds.left + (bounds.width - width) / 2,
      bounds.top + (bounds.height - height) / 2,
      width,
      height,
    );
  }
}
