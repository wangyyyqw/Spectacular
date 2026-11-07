import 'dart:convert';
import 'dart:typed_data';

/// 按 EPUB 3 XML 规则解码 XML/XHTML 字节。
///
/// EPUB 允许 UTF-8 与 UTF-16；优先识别 BOM，其次按 XML 开头和零字节分布
/// 判断 UTF-16LE/BE，最后按 UTF-8 容错解码。所有容器、OPF、目录、章节与
/// 样式读取共用此入口，避免正文修好后样式仍按 UTF-8 乱码。
String decodeXmlBytes(Uint8List bytes) {
  if (bytes.isEmpty) return '';
  if (bytes.length >= 2) {
    if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _decodeUtf16(bytes, 2, Endian.little);
    }
    if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _decodeUtf16(bytes, 2, Endian.big);
    }
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (_looksLikeUtf16(bytes, Endian.little)) {
    return _decodeUtf16(bytes, 0, Endian.little);
  }
  if (_looksLikeUtf16(bytes, Endian.big)) {
    return _decodeUtf16(bytes, 0, Endian.big);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// 样式或普通文本资源的统一解码入口（同样支持 BOM/UTF-16）。
String decodeTextBytes(Uint8List bytes) => decodeXmlBytes(bytes);

String _decodeUtf16(Uint8List bytes, int offset, Endian endian) {
  final end = (bytes.length - offset).isOdd ? bytes.length - 1 : bytes.length;
  if (end <= offset) return '';
  final units = <int>[];
  for (var i = offset; i + 1 < end; i += 2) {
    units.add(
      endian == Endian.little
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1],
    );
  }
  return String.fromCharCodes(units);
}

bool _looksLikeUtf16(Uint8List bytes, Endian endian) {
  final take = bytes.length < 64 ? bytes.length : 64;
  if (take < 4) return false;
  var zeroEven = 0;
  var zeroOdd = 0;
  for (var i = 0; i < take; i++) {
    if (bytes[i] != 0) continue;
    if (i.isEven) {
      zeroEven += 1;
    } else {
      zeroOdd += 1;
    }
  }
  if (endian == Endian.little) return zeroOdd >= take ~/ 4;
  return zeroEven >= take ~/ 4;
}
