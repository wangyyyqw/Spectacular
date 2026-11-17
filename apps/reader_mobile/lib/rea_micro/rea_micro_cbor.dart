import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// 阅微局域网清单使用的 CBOR 解码器。
///
/// 只覆盖 kotlinx.serialization 生成清单所需的确定性编码：整数、浮点数、
/// 文本、字节串、数组和映射。标签会跳过，未知的不定长形式直接拒绝，避免把
/// 截断或损坏的数据解释成可用清单。
class ReaMicroCborDecoder {
  ReaMicroCborDecoder._(Uint8List bytes) : _bytes = bytes;

  final Uint8List _bytes;
  int _offset = 0;

  /// 解码一份完整的 CBOR 数据。
  static Object? decode(List<int> bytes) {
    final decoder = ReaMicroCborDecoder._(Uint8List.fromList(bytes));
    final value = decoder._readValue();
    if (decoder._offset != decoder._bytes.length) {
      throw const FormatException('CBOR 数据末尾存在多余字节');
    }
    return value;
  }

  Object? _readValue() {
    final initial = _readByte();
    final major = initial >> 5;
    final additional = initial & 0x1f;
    switch (major) {
      case 0:
        return _readUnsigned(additional);
      case 1:
        return -1 - _readUnsigned(additional);
      case 2:
        return _readBytes(_readLength(additional));
      case 3:
        return utf8.decode(_readBytes(_readLength(additional)));
      case 4:
        final length = _readLength(additional);
        return <Object?>[
          for (var index = 0; index < length; index++) _readValue(),
        ];
      case 5:
        final length = _readLength(additional);
        final map = <String, Object?>{};
        for (var index = 0; index < length; index++) {
          final key = _readValue();
          if (key is! String) {
            throw const FormatException('CBOR 映射键必须是文本');
          }
          map[key] = _readValue();
        }
        return map;
      case 6:
        // 标签不改变当前清单的语义，读取标签号后继续读实际内容。
        _readUnsigned(additional);
        return _readValue();
      case 7:
        return _readSimple(additional);
      default:
        throw const FormatException('不支持的 CBOR 主类型');
    }
  }

  Object? _readSimple(int additional) {
    switch (additional) {
      case 20:
        return false;
      case 21:
        return true;
      case 22:
      case 23:
        return null;
      case 24:
        _readByte();
        return null;
      case 25:
        return _decodeHalf(_readUint(2));
      case 26:
        return _decodeFloat(_readUint(4).toSigned(32));
      case 27:
        return _decodeDouble(_readUint(8));
      default:
        throw FormatException('不支持的 CBOR 简单值：$additional');
    }
  }

  int _readLength(int additional) {
    if (additional < 24) return additional;
    if (additional == 24) return _readByte();
    if (additional == 25) return _readUint(2);
    if (additional == 26) return _readUint(4);
    if (additional == 27) return _readUint(8);
    throw const FormatException('不支持不定长 CBOR 数据');
  }

  int _readUnsigned(int additional) {
    if (additional < 24) return additional;
    if (additional == 24) return _readByte();
    if (additional == 25) return _readUint(2);
    if (additional == 26) return _readUint(4);
    if (additional == 27) return _readUint(8);
    throw const FormatException('不支持不定长 CBOR 整数');
  }

  int _readUint(int length) {
    _ensureAvailable(length);
    var value = 0;
    for (var index = 0; index < length; index++) {
      value = (value << 8) | _bytes[_offset++];
    }
    return value;
  }

  Uint8List _readBytes(int length) {
    _ensureAvailable(length);
    final value = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return value;
  }

  int _readByte() {
    _ensureAvailable(1);
    return _bytes[_offset++];
  }

  void _ensureAvailable(int length) {
    if (length < 0 || _offset + length > _bytes.length) {
      throw const FormatException('CBOR 数据不完整');
    }
  }

  double _decodeHalf(int value) {
    final sign = value >> 15;
    final exponent = (value >> 10) & 0x1f;
    final fraction = value & 0x3ff;
    final double result;
    if (exponent == 0) {
      result = (fraction * math.pow(2, -24)).toDouble();
    } else if (exponent == 31) {
      result = fraction == 0 ? double.infinity : double.nan;
    } else {
      result = ((1 + fraction / 1024) * math.pow(2, exponent - 15)).toDouble();
    }
    return sign == 0 ? result : -result;
  }

  double _decodeFloat(int value) {
    final data = ByteData(4)..setInt32(0, value, Endian.big);
    return data.getFloat32(0, Endian.big);
  }

  double _decodeDouble(int value) {
    final data = ByteData(8)..setUint64(0, value, Endian.big);
    return data.getFloat64(0, Endian.big);
  }
}
