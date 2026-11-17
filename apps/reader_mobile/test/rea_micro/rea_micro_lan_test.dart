import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'package:reader_mobile/rea_micro/rea_micro_lan_rsa.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';

void main() {
  test('RSA 公钥编码为 X.509 并可解密 PKCS#1 令牌', () async {
    final pair = await Isolate.run(ReaMicroLanRsa.generate);
    final encodedKey = ReaMicroLanRsa.encodePublicKey(pair.publicKey);
    final sequence = ASN1Sequence.fromBytes(
      Uint8List.fromList(base64Decode(encodedKey)),
    );
    expect(sequence.elements, hasLength(2));

    final encrypted = PKCS1Encoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(pair.publicKey));
    final ciphertext = encrypted.process(
      Uint8List.fromList(utf8.encode('access-token-123')),
    );
    final token = ReaMicroLanRsa.decryptToken(
      base64Encode(ciphertext),
      pair.privateKey,
    );

    expect(token, 'access-token-123');
  });

  test('局域网同步清单解析进度与时间戳', () {
    final manifest = ReaMicroLanManifest.fromJson(<String, Object?>{
      'userId': 7,
      'deviceId': 'device-b',
      'appVersion': 2330,
      'generatedAt': 1763380800000,
      'books': <Object?>[
        <String, Object?>{
          'uuid': 'book-a',
          'metaUpdatedAt': 1763380000000,
          'progressUpdatedAt': 1763380700000,
          'book': <String, Object?>{
            'uuid': 'book-a',
            'title': '本地书',
            'epubcfi': 'epubcfi(/6/8!/4/2/1)',
            'chapter': '第三章',
            'progress': 37.5,
            'finished': false,
          },
          'marks': null,
          'files': null,
        },
      ],
    });

    expect(manifest.userId, 7);
    expect(manifest.deviceId, 'device-b');
    expect(manifest.books, hasLength(1));
    final book = manifest.books.single;
    expect(book.uuid, 'book-a');
    expect(book.cfi, 'epubcfi(/6/8!/4/2/1)');
    expect(book.chapterName, '第三章');
    expect(book.progress, closeTo(0.375, 0.0001));
    expect(book.updatedAt, 1763380700000);
    expect(book.finished, isFalse);
  });
}
