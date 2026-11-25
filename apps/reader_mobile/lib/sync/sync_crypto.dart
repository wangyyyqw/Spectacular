import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';

/// 元数据与文件分块均使用认证加密；块顺序、对象身份和文件长度参与认证。
class SyncCrypto {
  SyncCrypto(this.collection, String recovery)
    : _bytes = recovery.isEmpty ? null : base64Decode(recovery.trim()) {
    if (_bytes != null && _bytes.length != 32) {
      throw const FormatException('恢复密钥必须是 32 字节的 Base64');
    }
  }

  final String collection;
  final Uint8List? _bytes;
  final _aes = AesGcm.with256bits();
  bool get encrypted => _bytes != null;
  static const chunkSize = 256 * 1024;

  static Future<String> generateKey() async => base64Encode(
    await AesGcm.with256bits().newSecretKey().then((key) => key.extractBytes()),
  );

  String objectId(String digest) => _bytes == null
      ? digest
      : hashes.Hmac(
          hashes.sha256,
          _bytes,
        ).convert(utf8.encode(digest)).toString();

  Future<Uint8List> encode(List<int> data, String context) async {
    if (_bytes == null) return Uint8List.fromList(data);
    final box = await _aes.encrypt(
      data,
      secretKey: SecretKey(_bytes),
      aad: utf8.encode('$collection/$context'),
    );
    return Uint8List.fromList([
      ...box.nonce,
      ...box.mac.bytes,
      ...box.cipherText,
    ]);
  }

  Future<Uint8List> decode(List<int> data, String context) async {
    if (_bytes == null) return Uint8List.fromList(data);
    if (data.length < 28) throw const FormatException('加密同步数据不完整');
    try {
      final plain = await _aes.decrypt(
        SecretBox(
          data.sublist(28),
          nonce: data.sublist(0, 12),
          mac: Mac(data.sublist(12, 28)),
        ),
        secretKey: SecretKey(_bytes),
        aad: utf8.encode('$collection/$context'),
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const FormatException('恢复密钥不正确，或同步数据已被篡改');
    }
  }

  Future<void> encodeFile(File input, File output, String digest) async {
    if (!encrypted) {
      await input.copy(output.path);
      return;
    }
    final size = await input.length();
    final source = await input.open();
    final sink = await output.open(mode: FileMode.write);
    try {
      for (var index = 0, offset = 0; offset < size; index++) {
        final chunk = await source.read(chunkSize);
        if (chunk.isEmpty) throw const FormatException('同步源文件已截断');
        final encoded = await encode(chunk, '$digest/$size/$index');
        await sink.writeFrom(
          (ByteData(4)..setUint32(0, encoded.length)).buffer.asUint8List(),
        );
        await sink.writeFrom(encoded);
        offset += chunk.length;
      }
    } finally {
      await source.close();
      await sink.close();
    }
  }

  Future<void> decodeFile(
    File input,
    File output,
    String digest,
    int size,
  ) async {
    if (!encrypted) {
      await input.copy(output.path);
      return;
    }
    final source = await input.open();
    final sink = await output.open(mode: FileMode.write);
    var written = 0;
    try {
      for (var index = 0; written < size; index++) {
        final header = await source.read(4);
        if (header.length != 4) throw const FormatException('同步文件不完整');
        final length = ByteData.sublistView(header).getUint32(0);
        if (length < 28 || length > chunkSize + 28) {
          throw const FormatException('同步文件块长度无效');
        }
        final block = await source.read(length);
        if (block.length != length) throw const FormatException('同步文件块不完整');
        final decoded = await decode(block, '$digest/$size/$index');
        written += decoded.length;
        await sink.writeFrom(decoded);
      }
      if (written != size || (await source.read(1)).isNotEmpty) {
        throw const FormatException('同步文件长度不一致');
      }
    } finally {
      await source.close();
      await sink.close();
    }
  }

  Future<void> verifyFile(File file, String digest) async {
    if ((await hashes.sha256.bind(file.openRead()).first).toString() !=
        digest) {
      throw const FormatException('同步文件 SHA-256 校验失败');
    }
  }
}
