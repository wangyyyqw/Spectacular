import 'dart:typed_data';

/// 字体字形覆盖检测（P3-04）。
///
/// 从字体字节解析 OpenType `cmap` 表（format 4 覆盖 BMP、format 12
/// 覆盖全平面），支持逐码点查询与缺失字符清单导出。定位是**诊断级
/// 工具**：运行期缺字仍由 `fontFamilyFallback` 兜底（技术方案 §28.4
/// 决策——不做逐字覆盖检测进排版热路径），本工具供缺失字符记录、
/// 书籍详情展示与清单导出使用。
///
/// 参考：OpenType OS/2 的 ulUnicodeRange 只给类级提示，逐字覆盖以
/// cmap 为准，故不解析 OS/2。
class FontCoverage {
  FontCoverage._(this._format12Groups, this._format4Segments);

  /// format 12 分组（升序，互不重叠）：[startCodePoint, endCodePoint]。
  final Uint32List _format12Groups;

  /// format 4 段（升序，互不重叠）：[startCode, endCode]（BMP）。
  final Uint32List _format4Segments;

  static const int _sfntTrue = 0x74727565; // 'true'
  static const int _otto = 0x4F54544F; // 'OTTO'
  static const int _ttcf = 0x74746366; // 'ttcf'（集合，不支持）

  /// 解析字体字节；格式不可读（magic 不符、缺 cmap、无可用子表、
  /// 字节截断）返回 null，不抛异常。
  static FontCoverage? parse(Uint8List bytes) {
    try {
      final data = ByteData.sublistView(bytes);
      if (bytes.length < 12) {
        return null;
      }
      final version = data.getUint32(0);
      if (version == _ttcf) {
        return null; // TTC 不支持（技术方案 §15 风险 4）。
      }
      if (version != 0x00010000 && version != _sfntTrue && version != _otto) {
        return null;
      }
      final numTables = data.getUint16(4);
      var cmapOffset = -1;
      for (var i = 0; i < numTables; i++) {
        final record = 12 + i * 16;
        if (record + 16 > bytes.length) {
          return null;
        }
        final tag = data.getUint32(record);
        // 'cmap'
        if (tag == 0x636D6170) {
          cmapOffset = data.getUint32(record + 8);
          break;
        }
      }
      if (cmapOffset < 0 || cmapOffset + 4 > bytes.length) {
        return null;
      }
      return _parseCmap(data, bytes.length, cmapOffset);
    } catch (_) {
      return null; // 字节损坏按不可检测处理（§28.4：只记格式校验）。
    }
  }

  static FontCoverage? _parseCmap(
    ByteData data,
    int length,
    int cmapOffset,
  ) {
    final numSubtables = data.getUint16(cmapOffset + 2);
    int? format4;
    int? format12;
    for (var i = 0; i < numSubtables; i++) {
      final record = cmapOffset + 4 + i * 8;
      if (record + 8 > length) {
        return null;
      }
      final platformId = data.getUint16(record);
      final offset = cmapOffset + data.getUint32(record + 4);
      if (offset + 2 > length) {
        continue;
      }
      final format = data.getUint16(offset);
      if (format == 12 &&
          format12 == null &&
          (platformId == 3 || platformId == 0)) {
        format12 = offset;
      } else if (format == 4 &&
          format4 == null &&
          (platformId == 3 || platformId == 0)) {
        format4 = offset;
      }
    }
    final groups =
        format12 == null ? Uint32List(0) : _parseFormat12(data, length, format12);
    final segments =
        format4 == null ? Uint32List(0) : _parseFormat4(data, length, format4);
    if (groups.isEmpty && segments.isEmpty) {
      return null;
    }
    return FontCoverage._(groups, segments);
  }

  static Uint32List _parseFormat12(
    ByteData data,
    int length,
    int offset,
  ) {
    if (offset + 16 > length) {
      return Uint32List(0);
    }
    final nGroups = data.getUint32(offset + 12);
    final groups = <int>[];
    for (var i = 0; i < nGroups; i++) {
      final record = offset + 16 + i * 12;
      if (record + 12 > length) {
        break; // 截断按已读部分计。
      }
      final startCode = data.getUint32(record);
      final endCode = data.getUint32(record + 4);
      final startGlyph = data.getUint32(record + 8);
      // `.notdef`（glyph 0）不是可用字形。部分书籍字体会把 ASCII 等
      // 声明在 cmap 中却映射到 0；若按码点区间误判为“已覆盖”，渲染器
      // 会画黑方块而不会回退。这里只保留真实非零字形的码点。
      final first = startGlyph == 0 ? startCode + 1 : startCode;
      if (first <= endCode) {
        groups
          ..add(first)
          ..add(endCode);
      }
    }
    return Uint32List.fromList(groups);
  }

  static Uint32List _parseFormat4(ByteData data, int length, int offset) {
    if (offset + 14 > length) {
      return Uint32List(0);
    }
    final segCount = data.getUint16(offset + 6) >> 1;
    final endCodesBase = offset + 14;
    final startCodesBase = endCodesBase + segCount * 2 + 2;
    final deltasBase = startCodesBase + segCount * 2;
    final rangeOffsetsBase = deltasBase + segCount * 2;
    // 末段 0xFFFF..0xFFFF 是规范哨兵，不代表真实覆盖，剔除。
    final segments = <int>[];
    for (var i = 0; i < segCount; i++) {
      final end = endCodesBase + i * 2;
      final start = startCodesBase + i * 2;
      final delta = deltasBase + i * 2;
      final rangeOffset = rangeOffsetsBase + i * 2;
      if (end + 2 > length ||
          start + 2 > length ||
          delta + 2 > length ||
          rangeOffset + 2 > length) {
        break; // 截断按已读部分计。
      }
      final startCode = data.getUint16(start);
      final endCode = data.getUint16(end);
      if (startCode == 0xFFFF && endCode == 0xFFFF) {
        continue;
      }
      final idDelta = data.getUint16(delta);
      final idRangeOffset = data.getUint16(rangeOffset);
      int? runStart;
      for (var code = startCode; code <= endCode; code++) {
        int glyphId;
        if (idRangeOffset == 0) {
          glyphId = (code + idDelta) & 0xFFFF;
        } else {
          final glyphOffset =
              rangeOffset + idRangeOffset + (code - startCode) * 2;
          if (glyphOffset + 2 > length) {
            break;
          }
          glyphId = data.getUint16(glyphOffset);
          if (glyphId != 0) {
            glyphId = (glyphId + idDelta) & 0xFFFF;
          }
        }
        if (glyphId == 0) {
          if (runStart != null) {
            segments
              ..add(runStart)
              ..add(code - 1);
            runStart = null;
          }
        } else {
          runStart ??= code;
        }
      }
      if (runStart != null) {
        segments
          ..add(runStart)
          ..add(endCode);
      }
    }
    return Uint32List.fromList(segments);
  }

  /// 是否覆盖 [codePoint]（Unicode 码点，非 UTF-16 码元）。
  bool covers(int codePoint) {
    if (_format12Groups.isNotEmpty &&
        _binarySearch(_format12Groups, codePoint)) {
      return true;
    }
    if (codePoint <= 0xFFFF &&
        _binarySearch(_format4Segments, codePoint)) {
      return true;
    }
    return false;
  }

  /// [text] 中未被覆盖的码点（去重、升序）。
  List<int> missingCodePoints(String text) {
    final missing = <int>{};
    for (final rune in text.runes) {
      if (!covers(rune)) {
        missing.add(rune);
      }
    }
    final result = missing.toList()..sort();
    return result;
  }

  /// 缺失字符清单的可导出文本：每行 `U+XXXX [字符]`，字符位置控制
  /// 等宽/不可打印字符显示。
  String exportMissingReport(String text) {
    return <String>[
      for (final codePoint in missingCodePoints(text))
        'U+${codePoint.toRadixString(16).toUpperCase().padLeft(4, '0')}'
        ' [${String.fromCharCode(codePoint)}]',
    ].join('\n');
  }

  static bool _binarySearch(Uint32List pairs, int value) {
    var low = 0;
    var high = pairs.length ~/ 2 - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final start = pairs[mid * 2];
      final end = pairs[mid * 2 + 1];
      if (value < start) {
        high = mid - 1;
      } else if (value > end) {
        low = mid + 1;
      } else {
        return true;
      }
    }
    return false;
  }
}
