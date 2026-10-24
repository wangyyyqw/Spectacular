import 'dart:typed_data';

/// 图片原始尺寸（像素）。
class ImageIntrinsicSize {
  const ImageIntrinsicSize({required this.width, required this.height});

  final int width;
  final int height;
}

/// 解析后的显示尺寸（逻辑像素）。
class ImageDisplaySize {
  const ImageDisplaySize({required this.width, required this.height});

  final double width;
  final double height;
}

/// 图片尺寸管线（P3-07，技术方案 §50.2）。
///
/// `readImageSize` 只读文件头拿原始尺寸，不解码像素——排版阶段只需要
/// 宽高比算占位（§50.3 优化 3：尺寸与位图分开缓存）。解码归 P3-08 的
/// `DecodedImageCache`。
abstract final class ImageSizeParser {
  /// 从图片字节读原始尺寸；格式不支持/头损坏返回 null，不抛异常。
  ///
  /// 支持 PNG / JPEG / GIF / BMP / WebP（VP8/VP8L/VP8X）。SVG 不支持
  /// 头解析（矢量无固定像素），返回 null 由调用方按占位处理。
  static ImageIntrinsicSize? readImageSize(Uint8List bytes) {
    if (bytes.length < 8) {
      return null;
    }
    if (_pngMagic(bytes)) {
      return _pngSize(bytes);
    }
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return _jpegSize(bytes);
    }
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return _littleEndianSize(bytes, 6, 8); // GIF 逻辑屏幕尺寸。
    }
    if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return _littleEndianSize(bytes, 18, 22); // BMP 信息头。
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return _webpSize(bytes);
    }
    return null;
  }

  static bool _pngMagic(Uint8List bytes) =>
      bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E;

  static ImageIntrinsicSize? _pngSize(Uint8List bytes) {
    // PNG 签名(8) + IHDR 长度(4) + 'IHDR'(4) + 宽(4 BE) + 高(4 BE)。
    if (bytes.length < 24) {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    final width = data.getUint32(16);
    final height = data.getUint32(20);
    return _valid(width, height);
  }

  static ImageIntrinsicSize? _jpegSize(Uint8List bytes) {
    // 扫段：找 SOF0~SOF15（跳过 DHT 0xC4 / DAC 0xCC / JPG 扩展段）。
    var i = 2;
    final data = ByteData.sublistView(bytes);
    while (i + 9 < bytes.length) {
      if (bytes[i] != 0xFF) {
        i += 1;
        continue;
      }
      final marker = bytes[i + 1];
      if (marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD9)) {
        i += 2;
        continue;
      }
      if (i + 4 > bytes.length) {
        return null;
      }
      final segmentLength = data.getUint16(i + 2);
      if ((marker >= 0xC0 && marker <= 0xCF) &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC) {
        if (i + 9 > bytes.length) {
          return null;
        }
        final height = data.getUint16(i + 5);
        final width = data.getUint16(i + 7);
        return _valid(width, height);
      }
      i += 2 + segmentLength;
    }
    return null;
  }

  static ImageIntrinsicSize? _webpSize(Uint8List bytes) {
    if (bytes.length < 30) {
      return null;
    }
    final chunk = String.fromCharCodes(bytes.sublist(12, 16));
    final data = ByteData.sublistView(bytes);
    switch (chunk) {
      case 'VP8X':
        // flags(1)+reserved(3)+canvasWidth-1(24 LE)+canvasHeight-1(24 LE)。
        final width = _readUint24(data, 24) + 1;
        final height = _readUint24(data, 27) + 1;
        return _valid(width, height);
      case 'VP8 ':
        // frame tag(3) + 起始码 9D 01 2A + 宽(2 LE) + 高(2 LE)。
        if (bytes[23] == 0x9D && bytes[24] == 0x01 && bytes[25] == 0x2A) {
          return _valid(
            data.getUint16(26, Endian.little) & 0x3FFF,
            data.getUint16(28, Endian.little) & 0x3FFF,
          );
        }
        return null;
      case 'VP8L':
        // 签名 0x2F + 14bit 宽-1 + 14bit 高-1 打包在 4 字节。
        if (bytes[20] != 0x2F) {
          return null;
        }
        final bits = data.getUint32(21, Endian.little);
        final width = (bits & 0x3FFF) + 1;
        final height = ((bits >> 14) & 0x3FFF) + 1;
        return _valid(width, height);
      default:
        return null;
    }
  }

  static int _readUint24(ByteData data, int offset) =>
      data.getUint8(offset) |
      (data.getUint8(offset + 1) << 8) |
      (data.getUint8(offset + 2) << 16);

  static ImageIntrinsicSize? _littleEndianSize(
    Uint8List bytes,
    int widthOffset,
    int heightOffset,
  ) {
    if (bytes.length < heightOffset + 2) {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    return _valid(
      data.getUint16(widthOffset, Endian.little),
      data.getUint16(heightOffset, Endian.little),
    );
  }

  static ImageIntrinsicSize? _valid(int width, int height) {
    if (width <= 0 || height <= 0) {
      return null;
    }
    return ImageIntrinsicSize(width: width, height: height);
  }
}

/// 显示尺寸计算（CSS Images 3 默认尺寸算法的阅读器口径，P3-07）。
abstract final class ImageDisplaySizing {
  /// 计算显示尺寸。
  ///
  /// [cssWidth]/[cssHeight] 为已解算的 CSS px（width/height 属性与
  /// 样式合并后），null 表示 auto。容器约束 [maxWidth]/[maxHeight]。
  ///
  /// 规则：
  /// - 两维都指定 → 直接使用（超容器按比例缩到贴边，阅读器显示优先）；
  /// - 指定一维 + 有原始宽高比 → 另一维按比例推出；
  /// - 指定一维 + 无原始尺寸 → 另一维取同值（正方形占位，确定性优先）；
  /// - 全 auto → 原始尺寸；超容器按比例缩到贴边；**不放大小图**。
  static ImageDisplaySize compute({
    required double maxWidth,
    double? maxHeight,
    int? intrinsicWidth,
    int? intrinsicHeight,
    double? cssWidth,
    double? cssHeight,
  }) {
    final hasRatio =
        intrinsicWidth != null && intrinsicHeight != null && intrinsicWidth > 0;
    final ratio = hasRatio ? intrinsicHeight / intrinsicWidth : null;
    double? width = cssWidth;
    double? height = cssHeight;

    if (width == null && height == null) {
      if (hasRatio) {
        width = intrinsicWidth.toDouble();
        height = intrinsicHeight.toDouble();
      } else {
        // 无任何尺寸信息：占位按容器宽 × 3:2 默认比例（CSS 替换元素
        // 300×150 默认比例的阅读器近似）。
        width = maxWidth;
        height = maxWidth / 2;
      }
    } else if (width != null && height == null) {
      height = ratio != null ? width * ratio : width;
    } else if (width == null && height != null) {
      width = ratio != null ? height / ratio : height;
    }

    // 超容器：按比例缩到贴边（两维都指定时同样缩，阅读器显示优先）。
    if (width! > maxWidth) {
      final scale = maxWidth / width;
      width = maxWidth;
      height = height! * scale;
    }
    if (maxHeight != null && height! > maxHeight) {
      final scale = maxHeight / height;
      height = maxHeight;
      width = width * scale;
    }
    return ImageDisplaySize(
      width: width < 1 ? 1 : width,
      height: height! < 1 ? 1 : height,
    );
  }
}
