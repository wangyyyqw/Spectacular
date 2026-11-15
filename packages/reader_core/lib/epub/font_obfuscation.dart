/// EPUB 字体解混淆（IDPF 与 Adobe 两种算法）。
///
/// - IDPF（EPUB 3.2 OCF §4.2，`http://www.idpf.org/2008/embedding`）：
///   密钥 = SHA-1(去除空白的 unique identifier)，混淆前 1040 字节；
/// - Adobe（规范外遗留算法，通行实现同 Readium）：
///   密钥 = UUID 的 16 字节二进制值，混淆前 1024 字节；
/// - 两者都是密钥循环 XOR，解混淆与混淆互为逆操作。
/// 参考：https://www.w3.org/publishing/epub32/epub-ocf.html#sec-font-obfuscation
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

/// 字体混淆算法。
enum FontObfuscationAlgorithm {
  /// IDPF 标准算法（`http://www.idpf.org/2008/embedding`）。
  idpf,

  /// Adobe 算法（`http://ns.adobe.com/pdf/enc#RC`）。
  adobe;

  /// 从 encryption.xml 的 Algorithm URI 识别；未知返回 null。
  static FontObfuscationAlgorithm? fromUri(String uri) {
    switch (uri.trim()) {
      case 'http://www.idpf.org/2008/embedding':
        return FontObfuscationAlgorithm.idpf;
      case 'http://ns.adobe.com/pdf/enc#RC':
        return FontObfuscationAlgorithm.adobe;
      default:
        return null;
    }
  }
}

/// encryption.xml 解析结果：资源路径 → 算法。
class FontEncryptionMap {
  static const _xmlEncryptionNamespace = 'http://www.w3.org/2001/04/xmlenc#';

  /// 空表（无加密声明或解析失败）。
  const FontEncryptionMap.empty()
    : this._(const <String, FontObfuscationAlgorithm>{}, const <String>[]);

  const FontEncryptionMap._(this.entries, this.unknownAlgorithms);

  /// 已识别的混淆资源（ZIP 内路径，原样大小写）。
  final Map<String, FontObfuscationAlgorithm> entries;

  /// encryption.xml 里出现但本引擎不支持的算法 URI。
  final List<String> unknownAlgorithms;

  /// 是否为空（无任何加密声明）。
  bool get isEmpty => entries.isEmpty && unknownAlgorithms.isEmpty;

  /// 解析 `META-INF/encryption.xml`；[xml] 为空/解析失败返回空表。
  ///
  /// 只认 EncryptedData → CipherReference/@URI + EncryptionMethod/@Algorithm
  /// 的扁平结构；EncryptedKey 包裹的密文（真加密 DRM）不在此列，其
  /// EncryptionMethod 不带 CipherReference 子结构时自然跳过。
  /// [resolvePath] 由容器资源索引解析 URI，复用根相对及百分号解码规则。
  static FontEncryptionMap parse(
    String xml, {
    String? Function(String uri)? resolvePath,
  }) {
    try {
      final document = XmlDocument.parse(xml);
      final entries = <String, FontObfuscationAlgorithm>{};
      final unknown = <String>[];
      for (final data in document.findAllElements(
        'EncryptedData',
        namespaceUri: _xmlEncryptionNamespace,
      )) {
        final reference = _referencesOf(data);
        if (reference.isEmpty) {
          continue;
        }
        final algorithmUri = _algorithmUriOf(data);
        final algorithm = algorithmUri == null
            ? null
            : FontObfuscationAlgorithm.fromUri(algorithmUri);
        if (algorithm == null) {
          if (algorithmUri != null && algorithmUri.isNotEmpty) {
            unknown.add(algorithmUri);
          }
          continue;
        }
        for (final uri in reference) {
          final path = resolvePath == null
              ? (uri.startsWith('/') ? uri.substring(1) : uri)
              : resolvePath(uri);
          if (path != null) entries[path] = algorithm;
        }
      }
      return FontEncryptionMap._(
        Map.unmodifiable(entries),
        List.unmodifiable(unknown),
      );
    } catch (_) {
      return const FontEncryptionMap.empty();
    }
  }

  static String? _algorithmUriOf(XmlElement data) => data
      .findElements('EncryptionMethod', namespaceUri: _xmlEncryptionNamespace)
      .firstOrNull
      ?.getAttribute('Algorithm')
      ?.trim();

  static Iterable<String> _referencesOf(XmlElement data) => data
      .findAllElements('CipherReference', namespaceUri: _xmlEncryptionNamespace)
      .map((element) => element.getAttribute('URI')?.trim())
      .whereType<String>()
      .where((uri) => uri.isNotEmpty);
}

/// 解混淆产物磁盘缓存：按内容键落文件，命中不重复解密（P3-05）。
///
/// 缓存文件名 = sha1(原书路径 + 原始字节哈希前缀)，避免同路径不同
/// 书/换版互相污染。任何 IO 失败都退回直接计算，不阻断阅读。
class DirectoryFontCache {
  /// 创建缓存；[directory] 不存在时惰性创建。
  DirectoryFontCache(this.directory);

  /// 缓存目录。
  final Directory directory;

  /// 取缓存；未命中或 IO 失败时执行 [compute] 并尝试写入。
  Future<Uint8List> getOrCompute(
    String key,
    Future<Uint8List> Function() compute,
  ) async {
    final name = sha1.convert(utf8.encode(key)).toString();
    final file = File('${directory.path}/$name.font');
    try {
      if (file.existsSync()) {
        final cached = await file.readAsBytes();
        if (cached.isNotEmpty) {
          return cached;
        }
      }
    } catch (_) {
      // 读缓存失败按未命中处理。
    }
    final bytes = await compute();
    try {
      await directory.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      // 写缓存失败不影响本次结果。
    }
    return bytes;
  }
}

/// 字体混淆与解混淆工具。
abstract final class FontObfuscator {
  static final RegExp _whitespace = RegExp(r'[\u0020\u0009\u000d\u000a]');

  /// IDPF 密钥：SHA-1(去除空白的 identifier)，20 字节。
  static Uint8List idpfKey(String identifier) {
    final normalized = identifier.replaceAll(_whitespace, '');
    final digest = sha1.convert(utf8.encode(normalized));
    return Uint8List.fromList(digest.bytes);
  }

  /// Adobe 密钥：identifier 中 UUID 的 16 字节二进制值。
  ///
  /// 例：`urn:uuid:00112233-4455-6677-8899-aabbccddeeff`
  /// → `00 11 22 33 44 55 66 77 88 99 aa bb cc dd ee ff`。
  static Uint8List adobeKey(String identifier) {
    final raw = identifier
        .trim()
        .replaceFirst(RegExp(r'^urn:uuid:', caseSensitive: false), '')
        .replaceAll('-', '')
        .trim();
    if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(raw)) {
      throw FormatException('Adobe 字体解混淆需要合法 UUID：$identifier');
    }
    return Uint8List.fromList([
      for (var i = 0; i < 32; i += 2)
        int.parse(raw.substring(i, i + 2), radix: 16),
    ]);
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
