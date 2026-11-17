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

/// 阅微 S3 清单使用的 CBOR 编码器。
///
/// 输出采用最短长度编码，映射按插入顺序写出，供与阅微一致的
/// kotlinx.serialization 清单和分片使用。
class ReaMicroCborEncoder {
  ReaMicroCborEncoder._();

  /// 编码一份完整的 CBOR 数据。
  static Uint8List encode(Object? value) {
    final builder = BytesBuilder(copy: false);
    _write(builder, value);
    return builder.takeBytes();
  }

  static void _write(BytesBuilder builder, Object? value) {
    if (value == null) {
      builder.addByte(0xf6);
      return;
    }
    if (value is bool) {
      builder.addByte(value ? 0xf5 : 0xf4);
      return;
    }
    if (value is int) {
      if (value >= 0) {
        _writeHead(builder, 0, value);
      } else {
        _writeHead(builder, 1, -1 - value);
      }
      return;
    }
    if (value is double) {
      final data = ByteData(8)..setFloat64(0, value, Endian.big);
      builder.addByte(0xfb);
      builder.add(data.buffer.asUint8List());
      return;
    }
    if (value is Uint8List) {
      _writeHead(builder, 2, value.length);
      builder.add(value);
      return;
    }
    if (value is String) {
      final bytes = utf8.encode(value);
      _writeHead(builder, 3, bytes.length);
      builder.add(bytes);
      return;
    }
    if (value is List<Object?>) {
      _writeHead(builder, 4, value.length);
      for (final item in value) {
        _write(builder, item);
      }
      return;
    }
    if (value is Map<String, Object?>) {
      _writeHead(builder, 5, value.length);
      for (final entry in value.entries) {
        _write(builder, entry.key);
        _write(builder, entry.value);
      }
      return;
    }
    throw ArgumentError('不支持的 CBOR 值类型：${value.runtimeType}');
  }

  static void _writeHead(BytesBuilder builder, int major, int length) {
    final prefix = major << 5;
    if (length < 24) {
      builder.addByte(prefix | length);
    } else if (length <= 0xff) {
      builder.addByte(prefix | 24);
      builder.addByte(length);
    } else if (length <= 0xffff) {
      builder.addByte(prefix | 25);
      builder.add(<int>[length >> 8, length & 0xff]);
    } else if (length <= 0xffffffff) {
      builder.addByte(prefix | 26);
      builder.add(<int>[
        (length >> 24) & 0xff,
        (length >> 16) & 0xff,
        (length >> 8) & 0xff,
        length & 0xff,
      ]);
    } else {
      builder.addByte(prefix | 27);
      for (var shift = 56; shift >= 0; shift -= 8) {
        builder.addByte((length >> shift) & 0xff);
      }
    }
  }
}
