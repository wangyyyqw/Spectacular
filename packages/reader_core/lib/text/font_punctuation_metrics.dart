import 'dart:typed_data';

import '../layout/punct_trim.dart' show punctUniformCompressionSet;

/// 默认标点轮廓相对 em 的占宽与侧留白，不持有字体字节。
class FontPunctuationMetrics {
  const FontPunctuationMetrics._(
    this.advanceRatio,
    this.leftBearingRatio,
    this.rightBearingRatio,
  );

  final double advanceRatio;
  final double leftBearingRatio;
  final double rightBearingRatio;

  bool _same(FontPunctuationMetrics other) =>
      advanceRatio == other.advanceRatio &&
      leftBearingRatio == other.leftBearingRatio &&
      rightBearingRatio == other.rightBearingRatio;
}

/// 只登记能确定默认轮廓的静态 TrueType 字面；未知字面仍参与族歧义判定。
abstract final class FontPunctuationRegistry {
  static final _families = <String, Map<(int, bool), _PunctuationFace?>>{};
  static int _revision = 0;

  static int get revision => _revision;

  /// 登记字面；[weight] 是排版样式匹配键，[declaredWeight] 可覆盖字库
  /// 内部 OS/2 字重（例如 Medium 500 作为正文 400 使用）。内部字重仍用于
  /// 拒绝合成粗体。
  static void register(
    String family,
    Uint8List bytes, {
    required int weight,
    required bool italic,
    int? declaredWeight,
  }) {
    final name = family.trim().toLowerCase();
    if (name.isEmpty) return;
    final faces = _families.putIfAbsent(name, () => {});
    final key = (weight, italic);
    final face = _PunctuationFace.parse(
      bytes,
      matchWeight: declaredWeight ?? weight,
    );
    final previous = faces[key];
    if (faces.containsKey(key) &&
        (face == null ? previous == null : face.same(previous))) {
      return;
    }
    faces[key] = face;
    _revision++;
  }

  /// 调用方仍须确认原生 advance、默认特性与本字面的实际轮廓一致。
  static FontPunctuationMetrics? lookup(
    String? family,
    int codePoint, {
    required int weight,
    required bool italic,
  }) {
    final faces = _families[family?.trim().toLowerCase()];
    if (faces == null || faces.isEmpty) return null;
    var face = faces[(weight, italic)];
    if (faces.length == 1) {
      final entry = faces.entries.single;
      if (entry.key.$2 != italic) return null;
      face ??= entry.value;
    } else if (face == null ||
        face.matchWeight != weight ||
        faces.values.any((candidate) => candidate == null) ||
        faces.values
                .where(
                  (candidate) =>
                      candidate!.matchWeight == weight &&
                      candidate.italic == italic,
                )
                .length !=
            1) {
      return null;
    }
    if (face == null ||
        face.italic != italic ||
        (weight >= 600 && face.os2Weight < 600)) {
      return null;
    }
    return face.glyphs[codePoint];
  }
}

class _PunctuationFace {
  _PunctuationFace(
    this.os2Weight,
    this.italic,
    this.glyphs, {
    required this.matchWeight,
  });

  final int os2Weight;
  final bool italic;
  final int matchWeight;
  final Map<int, FontPunctuationMetrics> glyphs;

  static _PunctuationFace? parse(Uint8List bytes, {required int matchWeight}) {
    try {
      final font = _TrueTypeFont(_readTables(bytes));
      final glyphs = <int, FontPunctuationMetrics>{};
      for (final char in punctUniformCompressionSet) {
        final code = char.codeUnitAt(0);
        final metrics = font.metrics(code);
        if (metrics != null) glyphs[code] = metrics;
      }
      if (glyphs.isEmpty) return null;
      final style = font.style;
      return _PunctuationFace(
        style.$1,
        style.$2,
        Map.unmodifiable(glyphs),
        matchWeight: matchWeight,
      );
    } catch (_) {
      return null;
    }
  }

  bool same(_PunctuationFace? other) {
    if (other == null ||
        os2Weight != other.os2Weight ||
        matchWeight != other.matchWeight ||
        italic != other.italic ||
        glyphs.length != other.glyphs.length) {
      return false;
    }
    return glyphs.entries.every((entry) {
      final previous = other.glyphs[entry.key];
      return previous != null && entry.value._same(previous);
    });
  }
}

void _require(bool valid) {
  if (!valid) throw const FormatException('字体标点度量不可确定');
}

ByteData _slice(ByteData data, int start, int length) {
  _require(start >= 0 && length >= 0 && start + length <= data.lengthInBytes);
  return ByteData.sublistView(data, start, start + length);
}

Map<int, ByteData> _readTables(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final version = data.getUint32(0);
  _require(version == 0x00010000 || version == 0x74727565);
  final count = data.getUint16(4);
  final directoryEnd = 12 + count * 16;
  _require(count > 0 && directoryEnd <= bytes.length);
  final tables = <int, ByteData>{};
  final ranges = <(int, int)>[];
  for (var index = 0; index < count; index++) {
    final record = 12 + index * 16;
    final tag = data.getUint32(record);
    final offset = data.getUint32(record + 8);
    final length = data.getUint32(record + 12);
    _require(!tables.containsKey(tag) && offset >= directoryEnd);
    tables[tag] = _slice(data, offset, length);
    ranges.add((offset, offset + length));
  }
  ranges.sort((a, b) => a.$1.compareTo(b.$1));
  for (var index = 1; index < ranges.length; index++) {
    _require(ranges[index - 1].$2 <= ranges[index].$1);
  }
  // 不用默认轮廓猜测替换、定位、变体或 CFF 字面的实际墨迹。
  const excluded = {
    0x47535542, 0x47504F53, 0x6B65726E, // GSUB、GPOS、kern
    0x66766172, 0x67766172, 0x61766172, // fvar、gvar、avar
    0x48564152, 0x4D564152, 0x63564152, // HVAR、MVAR、cvar
    0x43464620, 0x43464632, // CFF、CFF2
  };
  _require(!tables.keys.any(excluded.contains));
  return tables;
}

class _TrueTypeFont {
  _TrueTypeFont(Map<int, ByteData> tables)
    : head = tables[0x68656164]!,
      hhea = tables[0x68686561]!,
      hmtx = tables[0x686D7478]!,
      maxp = tables[0x6D617870]!,
      loca = tables[0x6C6F6361]!,
      glyf = tables[0x676C7966]!,
      os2 = tables[0x4F532F32],
      cmap = _FontCmap(tables[0x636D6170]!) {
    _require(head.lengthInBytes >= 54 && hhea.lengthInBytes >= 36);
    _require(head.getUint32(12) == 0x5F0F3CF5);
    _require(units >= 16 && units <= 16384 && glyphCount > 0);
    _require(metricCount > 0 && metricCount <= glyphCount);
    _require(locaFormat == 0 || locaFormat == 1);
    _slice(loca, 0, (glyphCount + 1) * (locaFormat == 0 ? 2 : 4));
    _slice(hmtx, 0, metricCount * 4 + (glyphCount - metricCount) * 2);
  }

  final ByteData head, hhea, hmtx, maxp, loca, glyf;
  final ByteData? os2;
  final _FontCmap cmap;
  int get units => head.getUint16(18);
  int get glyphCount => maxp.getUint16(4);
  int get metricCount => hhea.getUint16(34);
  int get locaFormat => head.getInt16(50);

  (int, bool) get style {
    final table = os2;
    if (table == null) {
      final flags = head.getUint16(44);
      return ((flags & 1) != 0 ? 700 : 400, (flags & 2) != 0);
    }
    final weight = table.getUint16(4);
    final selection = table.getUint16(62);
    _require(weight >= 1 && weight <= 1000 && (selection & 0x200) == 0);
    return (weight, (selection & 1) != 0);
  }

  FontPunctuationMetrics? metrics(int code) {
    final id = cmap.glyphId(code);
    if (id == 0 || id >= glyphCount) return null;
    final start = _glyphOffset(id);
    final end = _glyphOffset(id + 1);
    _require(end >= start);
    if (start == end) return null;
    final glyph = _slice(glyf, start, end - start);
    final contours = glyph.getInt16(0);
    // 复合字形可用组件替换度量；这里只采用可独立核实的简单轮廓。
    if (contours <= 0) return null;
    _validateSimpleGlyph(glyph, contours);
    final width = glyph.getInt16(6) - glyph.getInt16(2);
    _require(width > 0 && glyph.getInt16(8) > glyph.getInt16(4));
    final metric = id < metricCount ? id : metricCount - 1;
    final advance = hmtx.getUint16(metric * 4);
    final bearingOffset = id < metricCount
        ? id * 4 + 2
        : metricCount * 4 + (id - metricCount) * 2;
    final left = hmtx.getInt16(bearingOffset);
    if (advance == 0) return null;
    return FontPunctuationMetrics._(
      advance / units,
      left / units,
      (advance - left - width) / units,
    );
  }

  int _glyphOffset(int id) =>
      locaFormat == 0 ? loca.getUint16(id * 2) * 2 : loca.getUint32(id * 4);
}

void _validateSimpleGlyph(ByteData glyph, int contours) {
  var previous = -1;
  for (var index = 0; index < contours; index++) {
    final end = glyph.getUint16(10 + index * 2);
    _require(end > previous);
    previous = end;
  }
  var cursor = 10 + contours * 2;
  final instructions = glyph.getUint16(cursor);
  cursor += 2 + instructions;
  _slice(glyph, cursor, 0);
  var points = 0, coordinateBytes = 0;
  while (points <= previous) {
    final flag = glyph.getUint8(cursor++);
    final repeat = (flag & 8) == 0 ? 1 : 1 + glyph.getUint8(cursor++);
    points += repeat;
    _require(points <= previous + 1);
    coordinateBytes +=
        repeat *
        (_coordinateBytes(flag, 2, 16) + _coordinateBytes(flag, 4, 32));
  }
  _slice(glyph, cursor, coordinateBytes);
}

int _coordinateBytes(int flag, int short, int same) =>
    (flag & short) != 0 ? 1 : ((flag & same) != 0 ? 0 : 2);

class _FontCmap {
  _FontCmap(ByteData table) {
    final count = table.getUint16(2);
    _slice(table, 4, count * 8);
    for (var index = 0; index < count; index++) {
      final record = 4 + index * 8;
      final platform = table.getUint16(record);
      final encoding = table.getUint16(record + 2);
      if (platform != 0 &&
          !(platform == 3 && (encoding == 1 || encoding == 10))) {
        continue;
      }
      final offset = table.getUint32(record + 4);
      _require(offset >= 4 + count * 8);
      final format = table.getUint16(offset);
      if (format == 4) {
        final data = _slice(table, offset, table.getUint16(offset + 2));
        _validateFormat4(data);
        _subtables.add(data);
      } else if (format == 12) {
        final data = _slice(table, offset, table.getUint32(offset + 4));
        _validateFormat12(data);
        _subtables.add(data);
      }
    }
    _require(_subtables.isNotEmpty);
  }

  final _subtables = <ByteData>[];

  int glyphId(int code) {
    int? glyph;
    for (final table in _subtables) {
      final current = table.getUint16(0) == 12
          ? _format12Glyph(table, code)
          : _format4Glyph(table, code);
      _require(glyph == null || glyph == current);
      glyph = current;
    }
    return glyph ?? 0;
  }
}

void _validateFormat4(ByteData data) {
  final doubled = data.getUint16(6);
  _require(doubled > 0 && doubled.isEven);
  final count = doubled ~/ 2;
  _slice(data, 14, count * 8 + 2);
  var previous = -1;
  for (var index = 0; index < count; index++) {
    final end = data.getUint16(14 + index * 2);
    final start = data.getUint16(16 + count * 2 + index * 2);
    _require(start <= end && start > previous);
    final position = 16 + count * 6 + index * 2;
    final range = data.getUint16(position);
    if (range != 0) _slice(data, position + range, (end - start + 1) * 2);
    previous = end;
  }
  _require(previous == 0xFFFF);
}

int _format4Glyph(ByteData data, int code) {
  final count = data.getUint16(6) ~/ 2;
  var low = 0, high = count;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    if (data.getUint16(14 + middle * 2) < code) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  if (low == count) return 0;
  final start = data.getUint16(16 + count * 2 + low * 2);
  if (code < start) return 0;
  final delta = data.getUint16(16 + count * 4 + low * 2);
  final position = 16 + count * 6 + low * 2;
  final range = data.getUint16(position);
  if (range == 0) return (code + delta) & 0xFFFF;
  final glyph = data.getUint16(position + range + (code - start) * 2);
  return glyph == 0 ? 0 : (glyph + delta) & 0xFFFF;
}

void _validateFormat12(ByteData data) {
  final count = data.getUint32(12);
  _slice(data, 16, count * 12);
  var previous = -1;
  for (var index = 0; index < count; index++) {
    final start = data.getUint32(16 + index * 12);
    final end = data.getUint32(20 + index * 12);
    _require(start <= end && start > previous && end <= 0x10FFFF);
    previous = end;
  }
}

int _format12Glyph(ByteData data, int code) {
  var low = 0, high = data.getUint32(12);
  while (low < high) {
    final middle = (low + high) ~/ 2;
    final start = data.getUint32(16 + middle * 12);
    final end = data.getUint32(20 + middle * 12);
    if (code < start) {
      high = middle;
    } else if (code > end) {
      low = middle + 1;
    } else {
      return data.getUint32(24 + middle * 12) + code - start;
    }
  }
  return 0;
}
