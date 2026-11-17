import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'package:reader_mobile/rea_micro/rea_micro_lan.dart';
import 'package:reader_mobile/rea_micro/rea_micro_lan_rsa.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';

void main() {
  test('组播接口筛选跳过无法加入的网卡', () async {
    final probed = <String>[];
    final selected = await selectReachableMulticastInterfaces(
      <String>['以太网', '虚拟网卡', 'WLAN'],
      (name) async {
        probed.add(name);
        return name != '虚拟网卡';
      },
    );

    expect(probed, <String>['以太网', '虚拟网卡', 'WLAN']);
    expect(selected, <String>['以太网', 'WLAN']);
  });

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
            'author': '测试作者',
            'cloudId': 42,
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
    expect(book.title, '本地书');
    expect(book.author, '测试作者');
    expect(book.cloudId, 42);
    expect(book.cfi, 'epubcfi(/6/8!/4/2/1)');
    expect(book.chapterName, '第三章');
    expect(book.progress, closeTo(0.375, 0.0001));
    expect(book.updatedAt, 1763380700000);
    expect(book.finished, isFalse);
  });

  test('局域网同步清单按长度帧读取 CBOR', () async {
    final payload = _cborEncode(_manifestJson());
    final manifest = await _fetchFakeManifest(payload);

    expect(manifest.userId, 7);
    expect(manifest.books, hasLength(1));
    expect(manifest.books.single.cfi, 'epubcfi(/6/8!/4/2/1)');
    expect(manifest.books.single.progress, closeTo(0.375, 0.0001));
    expect(manifest.books.single.finished, isFalse);
  });

  test('局域网同步清单按长度帧读取 JSON 并解析数字读完状态', () async {
    final payload = utf8.encode(jsonEncode(_manifestJson(finished: 1)));
    final manifest = await _fetchFakeManifest(payload);

    expect(manifest.userId, 7);
    expect(manifest.deviceId, 'device-b');
    expect(manifest.books, hasLength(1));
    expect(manifest.books.single.chapterName, '第三章');
    expect(manifest.books.single.updatedAt, 1763380700000);
    expect(manifest.books.single.finished, isTrue);
  });
}

Map<String, Object?> _manifestJson({Object? finished = false}) {
  return <String, Object?>{
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
          'author': '作者',
          'cloudId': 42,
          'epubcfi': 'epubcfi(/6/8!/4/2/1)',
          'chapter': '第三章',
          'progress': 37.5,
          'finished': finished,
        },
        'marks': <Object?>[],
        'files': <Object?>[],
      },
    ],
  };
}

Future<ReaMicroLanManifest> _fetchFakeManifest(List<int> payload) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(server.close);
  final request = Completer<String>();
  final bye = Completer<String>();
  server.listen((socket) async {
    final iterator = StreamIterator<String>(
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter()),
    );
    try {
      if (await iterator.moveNext()) request.complete(iterator.current);
      socket.write('MANIFEST ${payload.length}\n');
      socket.add(payload);
      await socket.flush();
      if (await iterator.moveNext()) bye.complete(iterator.current);
    } finally {
      await iterator.cancel();
      socket.destroy();
    }
  });

  final client = ReaMicroLanClient(socketTimeout: const Duration(seconds: 2));
  final manifest = await client.fetchManifest(
    ReaMicroLanSyncPeer(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      userId: 7,
      deviceId: 'device-b',
      nickname: '同账号用户',
      deviceName: '测试设备',
    ),
  );

  expect(await request.future.timeout(const Duration(seconds: 2)), 'MANIFEST');
  expect(await bye.future.timeout(const Duration(seconds: 2)), 'BYE');
  return manifest;
}

List<int> _cborEncode(Object? value) {
  final output = <int>[];
  void write(Object? item) {
    if (item == null) {
      output.add(0xf6);
    } else if (item is bool) {
      output.add(item ? 0xf5 : 0xf4);
    } else if (item is int) {
      if (item >= 0) {
        _writeHeader(output, 0, item);
      } else {
        _writeHeader(output, 1, -1 - item);
      }
    } else if (item is num) {
      output.add(0xfb);
      final data = ByteData(8)..setFloat64(0, item.toDouble(), Endian.big);
      output.addAll(data.buffer.asUint8List());
    } else if (item is String) {
      final bytes = utf8.encode(item);
      _writeHeader(output, 3, bytes.length);
      output.addAll(bytes);
    } else if (item is List<Object?>) {
      _writeHeader(output, 4, item.length);
      for (final element in item) {
        write(element);
      }
    } else if (item is Map<String, Object?>) {
      _writeHeader(output, 5, item.length);
      for (final entry in item.entries) {
        write(entry.key);
        write(entry.value);
      }
    } else {
      throw ArgumentError.value(item, 'item', '测试编码器不支持该类型');
    }
  }

  write(value);
  return output;
}

void _writeHeader(List<int> output, int major, int length) {
  final prefix = major << 5;
  if (length < 24) {
    output.add(prefix | length);
  } else if (length <= 0xff) {
    output.addAll(<int>[prefix | 24, length]);
  } else if (length <= 0xffff) {
    output.addAll(<int>[prefix | 25, length >> 8, length & 0xff]);
  } else if (length <= 0xffffffff) {
    output.addAll(<int>[
      prefix | 26,
      length >> 24,
      (length >> 16) & 0xff,
      (length >> 8) & 0xff,
      length & 0xff,
    ]);
  } else {
    output.add(prefix | 27);
    for (var shift = 56; shift >= 0; shift -= 8) {
      output.add((length >> shift) & 0xff);
    }
  }
}
