import 'dart:typed_data';

/// OpenType 字体中与 CSS 排版相关的度量。
class FontMetrics {
  const FontMetrics._({required this.xHeightRatio});

  /// x-height / em；用于 `font-size-adjust`。
  final double xHeightRatio;

  static const int _sfntTrue = 0x74727565; // 'true'
  static const int _otto = 0x4F54544F; // 'OTTO'
  static const int _ttcf = 0x74746366; // 'ttcf'

  /// 从 `head` 与 `OS/2` 表读取 x-height 比例。
  ///
  /// 字体集合、OS/2 版本过旧或 `sxHeight` 缺失时返回 null。
  static FontMetrics? parse(Uint8List bytes) {
    try {
      if (bytes.length < 12) {
        return null;
      }
      final data = ByteData.sublistView(bytes);
      final version = data.getUint32(0);
      if (version == _ttcf) {
        return null;
      }
      if (version != 0x00010000 && version != _sfntTrue && version != _otto) {
        return null;
      }

      int? headOffset;
      int? os2Offset;
      final numTables = data.getUint16(4);
      for (var i = 0; i < numTables; i++) {
        final record = 12 + i * 16;
        if (record + 16 > bytes.length) {
          return null;
        }
        final tag = data.getUint32(record);
        if (tag == 0x68656164) {
          headOffset = data.getUint32(record + 8);
        } else if (tag == 0x4F532F32) {
          os2Offset = data.getUint32(record + 8);
        }
      }
      if (headOffset == null ||
          os2Offset == null ||
          headOffset + 54 > bytes.length ||
          os2Offset + 88 > bytes.length) {
        return null;
      }

      final unitsPerEm = data.getUint16(headOffset + 18);
      final os2Version = data.getUint16(os2Offset);
      if (unitsPerEm == 0 || os2Version < 2) {
        return null;
      }
      final xHeight = data.getInt16(os2Offset + 86);
      if (xHeight <= 0 || xHeight > unitsPerEm) {
        return null;
      }
      return FontMetrics._(xHeightRatio: xHeight / unitsPerEm);
    } catch (_) {
      return null;
    }
  }
}

/// 引擎族名到字体度量的只读注册表。
///
/// `builtin_song` 的思源宋体 OS/2.sxHeight 为 514、unitsPerEm 为 1000；
/// 其余运行期加载的书内字体由 `BookFontLoader` 注册。
abstract final class FontMetricsRegistry {
  static final Map<String, double> _xHeightRatios = <String, double>{
    'builtin_song': 0.514,
  };

  /// 注册字体，键不区分大小写；非法比例忽略。
  static void register(String family, FontMetrics metrics) {
    final key = family.trim().toLowerCase();
    final ratio = metrics.xHeightRatio;
    if (key.isEmpty || !ratio.isFinite || ratio <= 0) {
      return;
    }
    _xHeightRatios[key] = ratio;
  }

  /// 查询 x-height 比例；未注册时返回 null。
  static double? xHeightRatio(String? family) {
    if (family == null) {
      return null;
    }
    return _xHeightRatios[family.trim().toLowerCase()];
  }
}
