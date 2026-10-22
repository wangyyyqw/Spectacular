/// EPUB 字体解混淆（IDPF 与 Adobe 两种算法）。
///
/// 两种算法都是按密钥循环 XOR 前 N 字节，区别只在密钥来源与长度：
/// - IDPF：SHA-1（去除空白的 unique identifier），前 1040 字节；
/// - Adobe：UUID 去掉连字符后的 16 字节，前 1024 字节。
/// 参考：https://www.w3.org/publishing/epub32/epub-ocf.html#sec-resource-obfuscation
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 字体混淆算法。
enum FontObfuscationAlgorithm {
  /// IDPF 标准算法（`http://www.idpf.org/2008/embedding`）。
  idpf,

  /// Adobe 算法（`http://ns.adobe.com/pdf/enc#RC`）。
  adobe,
}

/// 字体混淆与解混淆工具。
abstract final class FontObfuscator {
  static final RegExp _whitespace = RegExp(r'[\u0020\u0009\u000d\u000a]');
  static final RegExp _uuid = RegExp(
    r'([0-9a-fA-F]{8})-([0-9a-fA-F]{4})-([0-9a-fA-F]{4})-'
    r'([0-9a-fA-F]{4})-([0-9a-fA-F]{12})',
  );

  /// IDPF 密钥：SHA-1(identifier)，20 字节。
  static Uint8List idpfKey(String identifier) {
    final normalized = identifier.replaceAll(_whitespace, '');
    final digest = sha1.convert(utf8.encode(normalized));
    return Uint8List.fromList(digest.bytes);
  }

  /// Adobe 密钥：UUID 去连字符后的 16 字节。
  static Uint8List adobeKey(String identifier) {
    final match = _uuid.firstMatch(identifier);
    if (match == null) {
      throw ArgumentError.value(identifier, 'identifier', '不含 UUID');
    }
    final hex = match.group(0)!.replaceAll('-', '');
    final key = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      key[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return key;
  }

  /// 解混淆；对同一算法而言，重复调用等价于混淆。
  static Uint8List deobfuscate(
    Uint8List bytes, {
    required String identifier,
    required FontObfuscationAlgorithm algorithm,
  }) {
    final (key, length) = switch (algorithm) {
      FontObfuscationAlgorithm.idpf => (idpfKey(identifier), 1040),
      FontObfuscationAlgorithm.adobe => (adobeKey(identifier), 1024),
    };
    return _xorPrefix(bytes, key, length);
  }

  /// 混淆；与 [deobfuscate] 互为逆操作。
  static Uint8List obfuscate(
    Uint8List bytes, {
    required String identifier,
    required FontObfuscationAlgorithm algorithm,
  }) => deobfuscate(bytes, identifier: identifier, algorithm: algorithm);

  static Uint8List _xorPrefix(Uint8List bytes, Uint8List key, int length) {
    final result = Uint8List.fromList(bytes);
    final limit = length < result.length ? length : result.length;
    for (var i = 0; i < limit; i++) {
      result[i] = result[i] ^ key[i % key.length];
    }
    return result;
  }
}
