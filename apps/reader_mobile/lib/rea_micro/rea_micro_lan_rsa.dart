import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

/// 局域网授权握手使用的临时 RSA 密钥。
///
/// 阅微服务端用请求中携带的 X.509 公钥加密访问令牌，客户端再用本地私钥
/// 解密。密钥只在一次握手内有效，不落盘，也不写入日志。
class ReaMicroLanRsa {
  /// 生成 2048 位 RSA 密钥对。
  static AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> generate() {
    final secure = Random.secure();
    final seed = Uint8List(32);
    for (var index = 0; index < seed.length; index++) {
      seed[index] = secure.nextInt(256);
    }
    final random = FortunaRandom()..seed(KeyParameter(seed));
    final generator = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
          random,
        ),
      );
    final pair = generator.generateKeyPair();
    return AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>(
      pair.publicKey,
      pair.privateKey,
    );
  }

  /// 编码为 SubjectPublicKeyInfo（X.509）后做 Base64。
  static String encodePublicKey(RSAPublicKey key) {
    final rsaPublicKey = ASN1Sequence()
      ..add(ASN1Integer(key.modulus))
      ..add(ASN1Integer(key.exponent));
    final algorithm = ASN1Sequence()
      ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.113549.1.1.1'))
      ..add(ASN1Null());
    final subjectPublicKeyInfo = ASN1Sequence()
      ..add(algorithm)
      ..add(ASN1BitString(stringValues: rsaPublicKey.encode()));
    return base64Encode(subjectPublicKeyInfo.encode());
  }

  /// 解析请求方提交的 X.509 RSA 公钥。
  static RSAPublicKey decodePublicKey(String encoded) {
    final decoded = base64Decode(encoded.trim());
    final subjectPublicKeyInfo = ASN1Sequence.fromBytes(decoded);
    final elements = subjectPublicKeyInfo.elements;
    if (elements == null ||
        elements.length < 2 ||
        elements[1] is! ASN1BitString) {
      throw const FormatException('RSA 公钥格式不正确');
    }
    final bitString = elements[1] as ASN1BitString;
    final values = bitString.stringValues;
    if (values is! List<int> || values.isEmpty) {
      throw const FormatException('RSA 公钥内容为空');
    }
    final rsa = ASN1Sequence.fromBytes(Uint8List.fromList(values));
    final parameters = rsa.elements;
    if (parameters == null ||
        parameters.length < 2 ||
        parameters[0] is! ASN1Integer ||
        parameters[1] is! ASN1Integer) {
      throw const FormatException('RSA 公钥参数不完整');
    }
    final modulus = (parameters[0] as ASN1Integer).integer;
    final exponent = (parameters[1] as ASN1Integer).integer;
    if (modulus == null || exponent == null) {
      throw const FormatException('RSA 公钥参数为空');
    }
    return RSAPublicKey(modulus, exponent);
  }

  /// 使用 RSA/ECB/PKCS1Padding 解密服务端返回的令牌。
  static String decryptToken(String encrypted, RSAPrivateKey key) {
    final engine = PKCS1Encoding(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(key));
    final clear = engine.process(base64Decode(encrypted.trim()));
    return utf8.decode(clear, allowMalformed: true).trim();
  }

  /// 使用请求方公钥加密访问令牌，返回 Base64 密文。
  static String encryptToken(String token, RSAPublicKey key) {
    final engine = PKCS1Encoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(key));
    final encrypted = engine.process(Uint8List.fromList(utf8.encode(token)));
    return base64Encode(encrypted);
  }
}
