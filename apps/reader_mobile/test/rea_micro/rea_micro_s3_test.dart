import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/rea_micro/rea_micro_cbor.dart';
import 'package:reader_mobile/rea_micro/rea_micro_s3.dart';

import '../support/test_epub.dart';

void main() {
  test('CBOR 编码与解码保持类型和字段', () {
    final source = <String, Object?>{
      'v': 1,
      's': <Object?>['甲'],
      'bytes': Uint8List.fromList(<int>[1, 2, 3, 255]),
      'flag': true,
      'none': null,
      'nested': <String, Object?>{'number': -12, 'text': '阅微'},
    };

    final decoded = ReaMicroCborDecoder.decode(
      ReaMicroCborEncoder.encode(source),
    );

    expect(decoded, isA<Map<String, Object?>>());
    final map = decoded! as Map<String, Object?>;
    expect(map['v'], 1);
    expect(map['s'], <Object?>['甲']);
    expect(map['bytes'], <int>[1, 2, 3, 255]);
    expect(map['flag'], isTrue);
    expect(map['none'], isNull);
    expect((map['nested']! as Map<String, Object?>)['number'], -12);
  });

  test('S3 对象路径只追加一次同步目录前缀', () async {
    Uri? requested;
    final client = ReaMicroS3HttpClient(
      const ReaMicroS3Config(
        endpoint: 'https://s3.example.com/base',
        bucket: 'reamicro',
        region: 'us-east-1',
        accessKey: 'access',
        secretKey: 'secret',
        prefix: 'team/read',
      ),
      httpClient: MockClient((request) async {
        requested = request.url;
        return http.Response(
          '',
          200,
          headers: <String, String>{'etag': '"strong-etag"'},
        );
      }),
    );

    await client.get('team/read/manifest.cbor');

    expect(requested!.path, '/base/reamicro/team/read/manifest.cbor');
    expect(requested!.path, isNot(contains('team/read/team/read')));
  });

  test('S3 书籍元数据保留阅微扩展字段', () {
    final source = <String, Object?>{
      'b': <String, Object?>{
        'u': 'uuid-1',
        's': 1024,
        'c': '分类',
        't': '书名',
        'st': '系列',
        'a': '作者',
        'g': '标签',
        'cr': 100,
        'v': 3,
        'e': 4,
        'x': 5,
        'i': 88,
        'bt': 6,
        'bi': 'banner-id',
        'bc': 'banner-color',
        'p': 'publisher',
      },
      'r': <String, Object?>{'t': 200, 'c': 1, 'd': 'device-a'},
      'm': 210,
      'e': <String, Object?>{
        'h': Uint8List(32),
        's': Uint8List(32),
        'o': 'object-1',
      },
    };

    final book = ReaMicroS3Book.fromCbor(source)!;
    final encoded = book.toCbor();
    final metadata = encoded['b']! as Map<String, Object?>;

    expect(metadata['t'], '书名');
    expect(metadata['st'], '系列');
    expect(metadata['g'], '标签');
    expect(metadata['v'], 3);
    expect(metadata['e'], 4);
    expect(metadata['bi'], 'banner-id');
    expect(metadata['p'], 'publisher');
  });

  test('两台设备通过 S3 同步图书并建立云端关联', () async {
    final root = await Directory.systemTemp.createTemp('reamicro-s3-test-');
    addTearDown(() => root.delete(recursive: true));
    final store = _MemoryS3();
    final libraryA = _TestLibrary(root, 'a');
    final libraryB = _TestLibrary(root, 'b');
    final bookA = await libraryA.add(
      buildTestEpub(title: '共享书', author: '作者', identifier: 's3-share'),
    );

    final resultA = await _engine(
      libraryA,
      store,
      userId: '7',
      deviceId: 'device-a',
      cloudIds: <String, int>{bookA.id: 88},
    ).sync();

    expect(resultA.uploaded, 1);
    expect(resultA.failed, 0);
    expect(store.keys, contains('team/read/manifest.cbor'));
    expect(
      store.keys.any(
        (key) => key.startsWith('team/read/manifests/spectacular/'),
      ),
      isTrue,
    );
    expect(
      store.keys.any((key) => key.startsWith('team/read/${bookA.id}/')),
      isTrue,
    );

    final resultB = await _engine(
      libraryB,
      store,
      userId: '7',
      deviceId: 'device-b',
    ).sync();

    expect(resultB.downloaded, 1);
    expect(resultB.failed, 0);
    expect(resultB.links, hasLength(1));
    expect(resultB.links.values.single, 88);
    expect((await libraryB.list()).single.title, '共享书');

    final resultAgain = await _engine(
      libraryB,
      store,
      userId: '7',
      deviceId: 'device-b',
    ).sync();
    expect(resultAgain.downloaded, 0);
    expect((await libraryB.list()), hasLength(1));
  });

  test('清单提交冲突后重新读取并重试', () async {
    final root = await Directory.systemTemp.createTemp('reamicro-s3-retry-');
    addTearDown(() => root.delete(recursive: true));
    final store = _MemoryS3()..manifestConflicts = 1;
    final library = _TestLibrary(root, 'retry');
    await library.add(
      buildTestEpub(title: '重试书', author: '作者', identifier: 's3-retry'),
    );

    final result = await _engine(
      library,
      store,
      userId: '9',
      deviceId: 'device-retry',
    ).sync();

    expect(result.failed, 0);
    expect(store.manifestPuts, 2);
    expect(store.object('team/read/manifest.cbor'), isNotNull);
  });

  test('删除墓碑阻止已删除图书重新下载', () async {
    final root = await Directory.systemTemp.createTemp('reamicro-s3-tomb-');
    addTearDown(() => root.delete(recursive: true));
    final store = _MemoryS3();
    final future = DateTime.now()
        .add(const Duration(days: 7))
        .millisecondsSinceEpoch;
    final deletedUuid = 'deleted-book';
    final epubBytes = buildTestEpub(title: '已删除', identifier: 's3-deleted');
    final sha = sha256Hex(epubBytes);
    store.putBytes(
      'team/read/other/shard-1.cbor',
      ReaMicroCborEncoder.encode(<String, Object?>{
        'b': <Object?>[
          <String, Object?>{
            'b': <String, Object?>{
              'u': deletedUuid,
              's': epubBytes.length,
              't': '已删除',
              'a': '作者',
              'cr': 1,
              'i': 66,
            },
            'r': <String, Object?>{'t': 1, 'c': 0, 'd': 'device-a'},
            'm': 1,
            'e': <String, Object?>{
              'h': _hexBytes(sha),
              's': _hexBytes(sha),
              'o': 'book-object',
            },
          },
        ],
      }),
    );
    store.putBytes(
      'team/read/deletions/other/delete-1.cbor',
      ReaMicroCborEncoder.encode(<String, Object?>{
        'a': <Object?>[
          <String, Object?>{
            'u': deletedUuid,
            'r': <String, Object?>{'t': 2, 'c': 0, 'd': 'device-a'},
            't': 2,
            'd': 'device-a',
            'x': future,
          },
        ],
      }),
    );
    store.putBytes(
      'team/read/manifest.cbor',
      ReaMicroCborEncoder.encode(<String, Object?>{
        'v': 1,
        's': <Object?>['other'],
        'd': <Object?>['other'],
        'r': 2,
        'sr': <String, Object?>{'other': 1},
        'dr': <String, Object?>{'other': 2},
        'de': <String, Object?>{},
        'sp': <String, Object?>{'other': 'shard-1'},
        'dp': <String, Object?>{'other': 'delete-1'},
        'gc': <String, Object?>{},
        'tx': <String, Object?>{},
      }),
    );
    final library = _TestLibrary(root, 'tomb');

    final result = await _engine(
      library,
      store,
      userId: '9',
      deviceId: 'device-b',
    ).sync();

    expect(result.downloaded, 0);
    expect(await library.list(), isEmpty);
    final manifest =
        ReaMicroCborDecoder.decode(
              store.object('team/read/manifest.cbor')!.bytes,
            )!
            as Map<String, Object?>;
    expect(manifest['d'], <Object?>['other']);
    expect((manifest['dp']! as Map<String, Object?>)['other'], 'delete-1');
  });
}

ReaMicroS3SyncEngine _engine(
  _TestLibrary library,
  _MemoryS3 store, {
  required String userId,
  required String deviceId,
  Map<String, int> cloudIds = const <String, int>{},
}) => ReaMicroS3SyncEngine(
  library: library,
  config: const ReaMicroS3Config(
    endpoint: 'https://s3.example.com',
    bucket: 'reamicro',
    region: 'us-east-1',
    accessKey: 'access',
    secretKey: 'secret',
    prefix: 'team/read',
  ),
  client: store,
  userId: userId,
  deviceId: deviceId,
  cloudIds: cloudIds,
);

class _MemoryS3 implements ReaMicroS3Client {
  final Map<String, ReaMicroS3Object> objects = <String, ReaMicroS3Object>{};
  var _etag = 0;
  var manifestConflicts = 0;
  var manifestPuts = 0;

  Iterable<String> get keys => objects.keys;

  ReaMicroS3Object? object(String key) => objects[key];

  void putBytes(String key, Uint8List bytes) {
    objects[key] = ReaMicroS3Object(bytes: bytes, etag: '"${++_etag}"');
  }

  @override
  Future<ReaMicroS3Object?> get(String key) async => objects[key];

  @override
  Future<String> put(
    String key,
    Uint8List bytes, {
    String contentType = 'application/octet-stream',
    String? ifMatch,
    String? ifNoneMatch,
  }) async {
    if (key.endsWith('manifest.cbor')) {
      manifestPuts += 1;
      if (manifestConflicts > 0) {
        manifestConflicts -= 1;
        throw const ReaMicroS3ConflictException('模拟冲突');
      }
    }
    final existing = objects[key];
    if (ifNoneMatch == '*' && existing != null) {
      throw const ReaMicroS3ConflictException('对象已存在');
    }
    if (ifMatch != null && existing?.etag != ifMatch) {
      throw const ReaMicroS3ConflictException('ETag 不匹配');
    }
    putBytes(key, bytes);
    return objects[key]!.etag;
  }

  @override
  Future<void> delete(String key) async {
    objects.remove(key);
  }
}

class _TestLibrary extends LibraryStore {
  _TestLibrary(this.root, this.name) : super.memory();

  final Directory root;
  final String name;
  final List<BookEntry> books = <BookEntry>[];

  Future<BookEntry> add(Uint8List bytes) async {
    final id = 'book-$name-${books.length + 1}';
    final file = File('${root.path}/$name-$id.epub');
    await file.writeAsBytes(bytes, flush: true);
    final parsed = await LibraryStore.memory().importBytes(bytes);
    final book = BookEntry(
      id: id,
      title: parsed.title,
      author: parsed.author,
      filePath: file.path,
      addedAt: DateTime.now(),
      contentRevision: sha256Hex(bytes),
    );
    books.add(book);
    return book;
  }

  @override
  Future<List<BookEntry>> list() async => List<BookEntry>.of(books);

  @override
  Future<BookEntry?> bookById(String id) async {
    for (final book in books) {
      if (book.id == id) return book;
    }
    return null;
  }

  @override
  Future<BookEntry> importBytes(
    Uint8List bytes, {
    String? fallbackTitle,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final parsed = await LibraryStore.memory().importBytes(
      bytes,
      fallbackTitle: fallbackTitle,
    );
    final id = 'book-$name-${books.length + 1}';
    final file = File('${root.path}/$name-$id.epub');
    await file.writeAsBytes(bytes, flush: true);
    final book = BookEntry(
      id: id,
      title: parsed.title,
      author: parsed.author,
      filePath: file.path,
      addedAt: DateTime.now(),
      contentRevision: sha256Hex(bytes),
    );
    books.add(book);
    return book;
  }
}

String sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

Uint8List _hexBytes(String value) {
  final bytes = Uint8List(value.length ~/ 2);
  for (var index = 0; index < bytes.length; index++) {
    bytes[index] = int.parse(
      value.substring(index * 2, index * 2 + 2),
      radix: 16,
    );
  }
  return bytes;
}
