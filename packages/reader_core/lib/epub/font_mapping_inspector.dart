import 'dart:convert';
import 'dart:typed_data';

/// 字形映射的启发式检查结果；疑似混淆不等同于 DRM。
class FontMappingInspection {
  const FontMappingInspection({this.readable = true, this.reason});

  final bool readable;
  final String? reason;
}

/// 检查 Unicode cmap 与字形名、跨文字映射的矛盾。
///
/// 参考 ReaMicro 的 cmap/post 对照方法，但不以字形编号乱序、复用或
/// 缺字比例判定加密：这些现象在普通字体、子集字体中也合法。
/// 仅解析 SFNT 的 Unicode format 4/12 与 post 2；所有偏移限于所属表。
/// 规范：https://learn.microsoft.com/en-us/typography/opentype/spec/cmap
/// 参考：https://github.com/YGHFv/ReaMicro-Extend/commit/39a4ccf
abstract final class FontMappingInspector {
  /// 乱序仅用于筛出需要 OCR 复核的字体，不能单独作为加密结论。
  static String? visualProbe(Uint8List bytes) {
    try {
      final mappings = _mappings(_tables(bytes)['cmap']!);
      final entries =
          mappings.entries
              .where((e) => e.key >= 0x4e00 && e.key <= 0x9fff)
              .toList()
            ..sort((a, b) => a.key.compareTo(b.key));
      if (entries.length < 200) return null;
      var increasing = 0;
      for (var i = 1; i < entries.length; i++) {
        if (entries[i].value > entries[i - 1].value) increasing++;
      }
      if (increasing / (entries.length - 1) >= .7) return null;
      const common =
          '的一是不了在人有我他这中大来上国个到说们为子和你地出道也时年得就那要下以生会自着去之过家学对可里后小么心多天而能好都然没日于起还发成事只作当想看文无开手十用主行方又如前所本见经头面公同三已老从动两长知民样现分';
      final codes = common.runes.where(mappings.containsKey).take(32).toList();
      if (codes.length < 24) {
        return String.fromCharCodes([
          for (var i = 0; i < 32; i++) entries[i * entries.length ~/ 32].key,
        ]);
      }
      return String.fromCharCodes(codes);
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

  static FontMappingInspection inspect(Uint8List bytes) {
    try {
      final tables = _tables(bytes);
      final mappings = _mappings(tables['cmap']!);
      final names = _postNames(tables['post']);
      final mismatch = _nameMismatch(mappings, names);
      return FontMappingInspection(
        reason: mismatch ?? _shadowAliases(mappings),
      );
    } on FormatException {
      return const FontMappingInspection(readable: false);
    } on RangeError {
      return const FontMappingInspection(readable: false);
    }
  }

  static Map<String, ByteData> _tables(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final magic = data.getUint32(0);
    if (magic != 0x00010000 && magic != 0x4f54544f && magic != 0x74727565) {
      throw const FormatException('不支持的字体容器');
    }
    final count = data.getUint16(4);
    final result = <String, ByteData>{};
    for (var i = 0; i < count; i++) {
      final record = 12 + i * 16;
      final tag = String.fromCharCodes(bytes.sublist(record, record + 4));
      final start = data.getUint32(record + 8);
      final length = data.getUint32(record + 12);
      if (tag == 'cmap' || tag == 'post') {
        result[tag] = ByteData.sublistView(bytes, start, start + length);
      }
    }
    if (!result.containsKey('cmap')) throw const FormatException('缺少 cmap');
    return result;
  }

  static Map<int, int> _mappings(ByteData cmap) {
    var bestScore = 0;
    var bestOffset = 0;
    for (var i = 0; i < cmap.getUint16(2); i++) {
      final record = 4 + i * 8;
      final platform = cmap.getUint16(record);
      final encoding = cmap.getUint16(record + 2);
      if (platform != 0 &&
          !(platform == 3 && (encoding == 1 || encoding == 10))) {
        continue;
      }
      final offset = cmap.getUint32(record + 4);
      final format = cmap.getUint16(offset);
      final score = format == 12 ? 2 : (format == 4 ? 1 : 0);
      if (score > bestScore) {
        bestScore = score;
        bestOffset = offset;
      }
    }
    if (bestScore == 0) throw const FormatException('无可检查的 Unicode cmap');
    final length = bestScore == 2
        ? cmap.getUint32(bestOffset + 4)
        : cmap.getUint16(bestOffset + 2);
    final table = ByteData.sublistView(
      Uint8List.view(cmap.buffer, cmap.offsetInBytes, cmap.lengthInBytes),
      bestOffset,
      bestOffset + length,
    );
    return bestScore == 2 ? _format12(table) : _format4(table);
  }

  static Map<int, int> _format12(ByteData data) {
    final result = <int, int>{};
    if (16 + data.getUint32(12) * 12 > data.lengthInBytes) {
      throw const FormatException('cmap 分组被截断');
    }
    var previousEnd = -1;
    for (var i = 0; i < data.getUint32(12); i++) {
      final record = 16 + i * 12;
      final start = data.getUint32(record);
      final end = data.getUint32(record + 4);
      final glyph = data.getUint32(record + 8);
      if (start <= previousEnd || end < start || end > 0x10ffff) {
        throw const FormatException('cmap 分组无效');
      }
      previousEnd = end;
      for (final code in _relevantCodes(start, end)) {
        final mapped = glyph + code - start;
        if (mapped > 0 && mapped < 65536) result[code] = mapped;
      }
    }
    return result;
  }

  static Map<int, int> _format4(ByteData data) {
    final count = data.getUint16(6) ~/ 2;
    if (count == 0 ||
        data.getUint16(6).isOdd ||
        16 + count * 8 > data.lengthInBytes) {
      throw const FormatException('cmap 分段被截断');
    }
    final starts = 16 + count * 2;
    final deltas = starts + count * 2;
    final offsets = deltas + count * 2;
    final result = <int, int>{};
    var previousEnd = -1;
    for (var i = 0; i < count; i++) {
      final start = data.getUint16(starts + i * 2);
      final end = data.getUint16(14 + i * 2);
      if (start <= previousEnd || end < start) {
        throw const FormatException('cmap 分段无效');
      }
      previousEnd = end;
      final delta = data.getInt16(deltas + i * 2);
      final address = offsets + i * 2;
      final offset = data.getUint16(address);
      for (final code in _relevantCodes(start, end)) {
        var glyph = offset == 0
            ? code
            : data.getUint16(address + offset + (code - start) * 2);
        if (offset == 0 || glyph != 0) glyph = (glyph + delta) & 0xffff;
        if (glyph != 0) result[code] = glyph;
      }
    }
    return result;
  }

  static Iterable<int> _relevantCodes(int start, int end) sync* {
    for (final (low, high) in const [
      (0x3400, 0x4dbf),
      (0x4e00, 0x9fff),
      (0xac00, 0xd7af),
      (0xe000, 0xf8ff),
      (0x20000, 0x2fa1f),
      (0x30000, 0x323af),
    ]) {
      final first = start > low ? start : low;
      final last = end < high ? end : high;
      for (var code = first; code <= last; code++) {
        yield code;
      }
    }
  }

  static Map<int, int> _postNames(ByteData? post) {
    if (post == null || post.getUint32(0) != 0x00020000) return {};
    final count = post.getUint16(32);
    final indices = List.generate(count, (i) => post.getUint16(34 + i * 2));
    var maxIndex = 257;
    for (final index in indices) {
      if (index > maxIndex) maxIndex = index;
    }
    final names = <int?>[];
    var cursor = 34 + count * 2;
    final unicodeName = RegExp(
      r'^(?:uni([0-9A-Fa-f]{4})|u([0-9A-Fa-f]{4,6}))$',
    );
    for (var i = 258; i <= maxIndex; i++) {
      final length = post.getUint8(cursor++);
      final name = latin1.decode(
        List.generate(length, (_) => post.getUint8(cursor++)),
      );
      final match = unicodeName.firstMatch(name.split('.').first);
      names.add(
        match == null ? null : int.parse(match[1] ?? match[2]!, radix: 16),
      );
    }
    return {
      for (var glyph = 0; glyph < indices.length; glyph++)
        if (indices[glyph] >= 258 && names[indices[glyph] - 258] != null)
          glyph: names[indices[glyph] - 258]!,
    };
  }

  static String? _nameMismatch(Map<int, int> mappings, Map<int, int> names) {
    var checked = 0;
    var mismatches = 0;
    for (final entry in mappings.entries) {
      final expected = names[entry.value];
      if (expected == null) continue;
      checked++;
      if (entry.key != expected) mismatches++;
    }
    return checked >= 50 && mismatches / checked >= .05
        ? '$checked 个可核对字形中，$mismatches 个码点与字形名不一致'
        : null;
  }

  static String? _shadowAliases(Map<int, int> mappings) {
    final cjkGlyphs = {
      for (final entry in mappings.entries)
        if ((entry.key >= 0x3400 && entry.key <= 0x9fff) ||
            entry.key >= 0x20000)
          entry.value,
    };
    final aliases = mappings.entries.where(
      (entry) =>
          entry.key >= 0xac00 &&
          entry.key <= 0xf8ff &&
          cjkGlyphs.contains(entry.value),
    );
    return aliases.length >= 50 ? '${aliases.length} 个韩文或私用区码点复用了汉字字形' : null;
  }
}
