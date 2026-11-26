import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' as pc;

import '../cloud_models.dart';

/// 为当前安装生成设备密钥，不使用其他客户端的私钥或服务端代理。
class AliyunDevice {
  static const appId = '5dde4e1bdf9e4966b387ba58f4b3fdc3';
  static final _parameters = pc.ECDomainParameters('secp256k1');

  static String randomHex(int length) {
    final random = Random.secure();
    return List.generate(
      length,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static String newKey() {
    while (true) {
      final key = randomHex(32);
      final value = BigInt.parse(key, radix: 16);
      if (value > BigInt.zero && value < _parameters.n) return key;
    }
  }

  static ({String publicKey, String signature}) sign(CloudAccount account) {
    final key = BigInt.tryParse(account.field('devicePrivateKey'), radix: 16);
    if (key == null || key <= BigInt.zero || key >= _parameters.n) {
      throw const CloudException('阿里设备凭据无效，请重新登录', loginRequired: true);
    }
    final message =
        '$appId:${account.field('deviceId')}:${account.field('userId')}:0';
    final hash = Uint8List.fromList(sha256.convert(utf8.encode(message)).bytes);
    final signer = pc.ECDSASigner(null, pc.HMac(pc.SHA256Digest(), 64));
    signer.init(
      true,
      pc.PrivateKeyParameter(pc.ECPrivateKey(key, _parameters)),
    );
    final signed = signer.generateSignature(hash) as pc.ECSignature;
    final order = _parameters.n;
    final s = signed.s <= order ~/ BigInt.two ? signed.s : order - signed.s;
    final publicKey = (_parameters.G * key)!;
    final z = BigInt.parse(_hex(hash), radix: 16);
    final inverse = s.modInverse(order);
    final point =
        (_parameters.G * (z * inverse % order))! +
        (publicKey * (signed.r * inverse % order));
    final recovery =
        (point!.y!.toBigInteger()!.isOdd ? 1 : 0) +
        (point.x!.toBigInteger()! >= order ? 2 : 0);
    return (
      publicKey: _hex(publicKey.getEncoded(false)),
      signature:
          '${signed.r.toRadixString(16).padLeft(64, '0')}'
          '${s.toRadixString(16).padLeft(64, '0')}'
          '${recovery.toRadixString(16).padLeft(2, '0')}',
    );
  }

  static String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
