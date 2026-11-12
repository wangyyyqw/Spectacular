import 'dart:convert';
import 'dart:typed_data';

import 'editable_document.dart';

/// 只接受可无损解码的 UTF-8/UTF-16，原资源的 BOM 与字节序在写回时保留。
class EditTextEncoding {
  const EditTextEncoding._(this.endian, this.bom);
  final Endian? endian;
  final bool bom;

  static EditTextEncoding detect(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 255 && bytes[1] == 254) {
      return const EditTextEncoding._(Endian.little, true);
    }
    if (bytes.length >= 2 && bytes[0] == 254 && bytes[1] == 255) {
      return const EditTextEncoding._(Endian.big, true);
    }
    if (bytes.length >= 4 && bytes[0] == 0 && bytes[1] == 60) {
      return const EditTextEncoding._(Endian.big, false);
    }
    if (bytes.length >= 4 && bytes[0] == 60 && bytes[1] == 0) {
      return const EditTextEncoding._(Endian.little, false);
    }
    return EditTextEncoding._(
      null,
      bytes.length >= 3 &&
          bytes[0] == 239 &&
          bytes[1] == 187 &&
          bytes[2] == 191,
    );
  }

  String decode(Uint8List bytes) {
    if (endian == null) return utf8.decode(bytes.sublist(bom ? 3 : 0));
    final offset = bom ? 2 : 0;
    if ((bytes.length - offset).isOdd) {
      throw const EpubEditException('UTF-16 字节不完整');
    }
    final data = ByteData.sublistView(bytes);
    final units = <int>[
      for (var i = offset; i < bytes.length; i += 2) data.getUint16(i, endian!),
    ];
    _validateUnits(units);
    return String.fromCharCodes(units);
  }

  Uint8List encode(String text) {
    _validateUnits(text.codeUnits);
    if (endian == null) {
      return Uint8List.fromList([
        if (bom) ...[239, 187, 191],
        ...utf8.encode(text),
      ]);
    }
    final data = ByteData((text.length + (bom ? 1 : 0)) * 2);
    var offset = 0;
    if (bom) {
      data.setUint16(0, 0xfeff, endian!);
      offset = 2;
    }
    for (final unit in text.codeUnits) {
      data.setUint16(offset, unit, endian!);
      offset += 2;
    }
    return data.buffer.asUint8List();
  }

  static void _validateUnits(List<int> units) {
    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw const EpubEditException('孤立的 UTF-16 代理字符');
      }
      if (unit < 0xd800 || unit > 0xdbff) continue;
      if (++i == units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
        throw const EpubEditException('孤立的 UTF-16 代理字符');
      }
    }
  }

  void validateDeclaration(String text) {
    final declaration = RegExp(
      r'''^\s*<\?xml\b[^>]*encoding\s*=\s*["']([^"']+)["']''',
    ).firstMatch(text);
    final name = declaration?.group(1)?.toLowerCase();
    if (name == null) return;
    final accepted = endian == null
        ? const {'utf-8'}
        : {'utf-16', endian == Endian.little ? 'utf-16le' : 'utf-16be'};
    if (!accepted.contains(name)) {
      throw const EpubEditException('XML 编码声明与实际字节不一致，请修正声明');
    }
  }
}
