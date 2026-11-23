import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/rea_micro/rea_micro_api_client.dart';
import 'package:reader_mobile/rea_micro/rea_micro_cbor.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';
import 'package:reader_mobile/rea_micro/rea_micro_s3.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final databases = <LibraryStore, AppDatabase>{};
  Future<LibraryStore> openLibrary(Directory root) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => root,
    );
    databases[library] = db;
    return library;
  }

  test('账号 S3 配置加密与阅微使用的 AES-128-CBC 格式一致', () {
    const encrypted =
        'AAECAwQFBgcICQoLDA0OD5p8bTcR0DDhb+8tWXAtCLpdEXIYtpGeZD4cKGjGIOFc'
        'JMNdjKgdWFvbZtFUiCQ1Oe6BeRYzE+ljqM9hnoymn8pltSlNr6aS7x+JkYzR2fb7'
        'tCBqfMz7MDS6ihDthNl2vzHDZXcPNUtl3j42N8fJZtUL9ai7X+dHHGvXj3U8ba'
        '+ZbTMusL1POUHjA+kBO0SEJ9tJ8fHgfJRoPhfL0QfPjoM=';

    final config = ReaMicroS3ConfigCrypto.decrypt(encrypted, 3);

    expect(config, isNotNull);
    expect(config!.provider, 'S3');
    expect(config.endpoint, 'https://s3.example.com');
    expect(config.bucket, 'bucket');
    expect(config.secretKey, 'secret');

    final roundTrip = ReaMicroS3ConfigCrypto.decrypt(
      ReaMicroS3ConfigCrypto.encrypt(config, 3),
      3,
    );
    expect(roundTrip?.toJson(), config.toJson());
  });

  test('阅微内置存储无需 S3 密钥即可判定可用，且缓存指纹按提供方区分', () {
    const mote = ReaMicroS3Config(
      endpoint: '',
      bucket: '',
      region: '',
      accessKey: '',
      secretKey: '',
      prefix: 'reamicro',
      provider: 'MOTE',
    );
    const s3 = ReaMicroS3Config(
      endpoint: '',
      bucket: '',
      region: '',
      accessKey: '',
      secretKey: '',
      prefix: 'reamicro',
      provider: 'S3',
    );
    expect(mote.isMote, isTrue);
    expect(mote.usable, isTrue);
    expect(s3.usable, isFalse);
    expect(mote.fingerprint('1'), isNot(s3.fingerprint('1')));
    expect(mote.copyWith(provider: 'S3').usable, isFalse);
  });

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

  test('恢复图书后改变标题和文件大小，下一轮用保存UUID匹配而不重下', () async {
    final root = await Directory.systemTemp.createTemp('s3-identity-');
    addTearDown(() => root.delete(recursive: true));
    final remote = _TestLibrary(root, 'remote');
    final local = _TestLibrary(root, 'local');
    final store = _MemoryS3();
    await remote.add(buildTestEpub(title: '云端书', identifier: 'source'));
    await _engine(remote, store, userId: '7', deviceId: 'remote').sync();
    final restored = await _engine(
      local,
      store,
      userId: '7',
      deviceId: 'local',
    ).sync();
    expect(restored.downloaded, 1);
    final old = local.books.single;
    final bytes = buildTestEpub(
      title: '改名后',
      identifier: 'changed',
      paragraphs: ['修改后的内容' * 30],
    );
    await File(old.filePath).writeAsBytes(bytes);
    local.books[0] = old.copyWith(
      title: '改名后',
      contentRevision: sha256Hex(bytes),
    );
    final again = await _engine(
      local,
      store,
      userId: '7',
      deviceId: 'local',
      localBookUuids: restored.localBookUuids,
    ).sync();
    expect(again.downloaded, 0);
    expect(again.uploaded, 1);
    expect(local.books, hasLength(1));
    expect(again.localBookUuids, restored.localBookUuids);
  });

  test('云同步补回缺失文件沿用原记录，保留书评和读完状态', () async {
    final root = await Directory.systemTemp.createTemp('s3-missing-source-');
    addTearDown(() => root.delete(recursive: true));
    final local = await openLibrary(root);
    final remote = _TestLibrary(root, 'remote');
    final store = _MemoryS3();
    final remoteBook = await remote.add(
      buildTestEpub(title: '云端版本', identifier: 'remote-version'),
    );
    await _engine(remote, store, userId: '7', deviceId: 'remote').sync();
    final original = await local.importBytes(
      buildTestEpub(title: '本地书名', identifier: 'local-version'),
    );
    final progress = DriftProgressStore(databases[local]!);
    await progress.save(
      original.id,
      const ReaderProgress(spineIndex: 0, pageIndex: 0, finished: true),
    );
    await local.reviewStore()!.save(original.id, rating: 4, content: '保留的书评');
    await File(original.filePath).delete();
    final result = await _engine(
      local,
      store,
      userId: '7',
      deviceId: 'local',
      localBookUuids: {original.id: remoteBook.id},
    ).sync();
    expect(result.failed, 0);
    expect(result.downloaded, 1);
    final restored = (await local.list()).single;
    expect(restored.id, original.id);
    expect(await File(restored.filePath).exists(), isTrue);
    expect(
      (await local.reviewStore()!.snapshot())[restored.id]!.content,
      '保留的书评',
    );
    expect((await progress.load(restored.id))!.finished, isTrue);
    final again = await _engine(
      local,
      store,
      userId: '7',
      deviceId: 'local',
      localBookUuids: result.localBookUuids,
    ).sync();
    expect(again.failed, 0);
    expect(again.downloaded, 0);
    expect(await local.list(), hasLength(1));
  });

  test('清单提交连续失败时已导入身份先保存，重试与下次同步均不重下', () async {
    final root = await Directory.systemTemp.createTemp('s3-import-retry-');
    addTearDown(() => root.delete(recursive: true));
    final local = await openLibrary(root);
    final remote = _TestLibrary(root, 'remote');
    final store = _MemoryS3();
    await remote.add(buildTestEpub(title: '失败重试书', identifier: 'retry-source'));
    await _engine(remote, store, userId: '7', deviceId: 'remote').sync();
    store.manifestConflicts = 3;
    final saved = <String, String>{};
    await expectLater(
      _engine(
        local,
        store,
        userId: '7',
        deviceId: 'local',
        onBookIdentified: (id, uuid) async => saved[id] = uuid,
      ).sync(),
      throwsA(isA<ReaMicroS3ConflictException>()),
    );
    expect(saved, hasLength(1));
    expect(await local.list(), hasLength(1));
    expect(store.bookDownloads, 1);
    final again = await _engine(
      local,
      store,
      userId: '7',
      deviceId: 'local',
      localBookUuids: saved,
    ).sync();
    expect(again.downloaded, 0);
    expect(store.bookDownloads, 1);
    expect(await local.list(), hasLength(1));
  });

  test('S3 双向同步书签并保留摘要备注', () async {
    final root = await Directory.systemTemp.createTemp('reamicro-s3-marks-');
    addTearDown(() => root.delete(recursive: true));
    final store = _MemoryS3();
    final libraryA = _TestLibrary(root, 'marks-a');
    final libraryB = _TestLibrary(root, 'marks-b');
    final bookA = await libraryA.add(
      buildTestEpub(title: '书签书', author: '作者', identifier: 's3-marks'),
    );
    libraryA.setBookmarks(bookA.id, <BookBookmarkRecord>[
      const BookBookmarkRecord(
        cfi: 'epubcfi(/6/8!/4/2/1)',
        spineIndex: 3,
        title: '第三章',
        summary: '章节摘要',
        remark: '第一条备注',
        createdAt: 1000,
        updatedAt: 1000,
      ),
    ]);

    final resultA = await _engine(
      libraryA,
      store,
      userId: '7',
      deviceId: 'device-a',
    ).sync();
    expect(resultA.syncedBookmarks, 1);
    final bookmarkKey = store.keys.firstWhere(
      (key) => key.endsWith('/bookmarks'),
    );
    final firstFile = jsonDecode(
      utf8.decode(store.object(bookmarkKey)!.bytes),
    ) as List<Object?>;
    expect(firstFile, hasLength(1));
    expect((firstFile.single! as Map<String, Object?>)['remark'], '第一条备注');

    final resultB = await _engine(
      libraryB,
      store,
      userId: '7',
      deviceId: 'device-b',
    ).sync();
    final bookB = (await libraryB.list()).single;
    expect(libraryB.bookmarksOf(bookB.id), hasLength(1));
    expect(libraryB.bookmarksOf(bookB.id).single.summary, '章节摘要');

    libraryB.setBookmarks(bookB.id, <BookBookmarkRecord>[
      ...libraryB.bookmarksOf(bookB.id),
      const BookBookmarkRecord(
        cfi: 'epubcfi(/6/10!/4/2/1)',
        spineIndex: 4,
        title: '第四章',
        summary: '',
        remark: 'B 端新增',
        createdAt: 2000,
        updatedAt: 2000,
      ),
    ]);
    await _engine(
      libraryB,
      store,
      userId: '7',
      deviceId: 'device-b',
      bookmarkBases: resultB.bookmarkBases,
    ).sync();

    await _engine(
      libraryA,
      store,
      userId: '7',
      deviceId: 'device-a',
      bookmarkBases: resultA.bookmarkBases,
    ).sync();
    expect(libraryA.bookmarksOf(bookA.id), hasLength(2));
    expect(
      libraryA.bookmarksOf(bookA.id).map((item) => item.remark),
      contains('B 端新增'),
    );
  });

  test('本地删除生成删除分片并阻止其他设备恢复', () async {
    final root = await Directory.systemTemp.createTemp('reamicro-s3-delete-');
    addTearDown(() => root.delete(recursive: true));
    final store = _MemoryS3();
    final libraryA = _TestLibrary(root, 'delete-a');
    final libraryB = _TestLibrary(root, 'delete-b');
    final bookA = await libraryA.add(
      buildTestEpub(title: '待删除', author: '作者', identifier: 's3-delete'),
    );

    final resultA = await _engine(
      libraryA,
      store,
      userId: '7',
      deviceId: 'device-a',
    ).sync();
    final uuid = resultA.localBookUuids[bookA.id];
    expect(uuid, bookA.id);

    libraryA.books.remove(bookA);
    final deleted = await _engine(
      libraryA,
      store,
      userId: '7',
      deviceId: 'device-a',
      localBookUuids: resultA.localBookUuids,
    ).sync();

    expect(deleted.deleted, 1);
    expect(deleted.pendingDeletions, isEmpty);
    expect(deleted.localBookUuids, isEmpty);
    final manifest =
        ReaMicroCborDecoder.decode(
              store.object('team/read/manifest.cbor')!.bytes,
            )!
            as Map<String, Object?>;
    expect(manifest['d'], contains('spectacular'));
    final deletionPointer =
        (manifest['dp']! as Map<String, Object?>)['spectacular'];
    expect(deletionPointer, isA<String>());
    final deletionShard =
        ReaMicroCborDecoder.decode(
              store
                  .object(
                    'team/read/deletions/spectacular/$deletionPointer.cbor',
                  )!
                  .bytes,
            )!
            as Map<String, Object?>;
    final tombstone =
        (deletionShard['e']! as List<Object?>).single as Map<String, Object?>;
    expect(tombstone['u'], uuid);
    expect(tombstone['r'], isA<Map<String, Object?>>());
    expect(tombstone['t'], isA<Map<String, Object?>>());
    expect(
      (manifest['de']! as Map<String, Object?>)['spectacular'],
      isA<int>(),
    );

    final resultB = await _engine(
      libraryB,
      store,
      userId: '7',
      deviceId: 'device-b',
    ).sync();
    expect(resultB.downloaded, 0);
    expect(await libraryB.list(), isEmpty);
  });

  test('新安装的空基线不会删除云端现有图书', () async {
    final root = await Directory.systemTemp.createTemp('reamicro-s3-empty-');
    addTearDown(() => root.delete(recursive: true));
    final store = _MemoryS3();
    final libraryA = _TestLibrary(root, 'empty-a');
    final libraryB = _TestLibrary(root, 'empty-b');
    await libraryA.add(
      buildTestEpub(title: '保留书', author: '作者', identifier: 's3-empty'),
    );
    await _engine(libraryA, store, userId: '7', deviceId: 'device-a').sync();

    final resultB = await _engine(
      libraryB,
      store,
      userId: '7',
      deviceId: 'device-b',
      localBookUuids: const <String, String>{},
    ).sync();

    expect(resultB.downloaded, 1);
    expect(resultB.deleted, 0);
    expect(resultB.localBookUuids, hasLength(1));
    expect((await libraryB.list()).single.title, '保留书');
  });

  test('删除分片提交失败时保留待删除状态', () async {
    final root = await Directory.systemTemp.createTemp('reamicro-s3-delretry-');
    addTearDown(() => root.delete(recursive: true));
    final store = _MemoryS3()..manifestConflicts = 3;
    final library = _TestLibrary(root, 'delete-retry');
    final pending = <String>{'deleted-book'};

    await expectLater(
      _engine(
        library,
        store,
        userId: '7',
        deviceId: 'device-a',
        localBookUuids: const <String, String>{'gone': 'deleted-book'},
        pendingDeletions: pending,
      ).sync(),
      throwsA(isA<ReaMicroS3ConflictException>()),
    );

    expect(
      store.keys.where(
        (key) => key.startsWith('team/read/deletions/spectacular/'),
      ),
      isNotEmpty,
    );
    expect(store.object('team/read/manifest.cbor'), isNull);
    expect(pending, <String>{'deleted-book'});
  });

  test('删除墓碑旧 a 字段仍可读取', () async {
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

  test('Mote 客户端通过阅微签发地址上传、读取并删除对象', () async {
    final transport = _FakeMoteApi();
    final client = ReaMicroMoteS3Client(
      api: transport,
      token: 'token',
      httpClient: MockClient((request) async {
        if (request.method == 'PUT') {
          transport.uploadedBytes = request.bodyBytes;
          transport.exists = true;
          return http.Response(
            '',
            200,
            headers: <String, String>{'etag': '"uploaded-etag"'},
          );
        }
        return http.Response.bytes(
          transport.uploadedBytes ?? <int>[],
          200,
          headers: <String, String>{'etag': '"download-etag"'},
        );
      }),
    );
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

    final etag = await client.put(
      'sync/book.epub',
      bytes,
      contentType: 'application/epub+zip',
      ifNoneMatch: '*',
    );
    final object = await client.get('sync/book.epub');
    await client.delete('sync/book.epub');

    expect(etag, '"uploaded-etag"');
    expect(transport.uploadKey, 'sync/book.epub');
    expect(transport.uploadLength, bytes.length);
    expect(transport.uploadIfNoneMatch, isTrue);
    expect(transport.confirmKey, 'sync/book.epub');
    expect(transport.uploadedBytes, bytes);
    expect(object?.bytes, bytes);
    expect(object?.etag, '"uploaded-etag"');
    expect(transport.deletedKey, 'sync/book.epub');
  });
}

class _FakeMoteApi implements ReaMicroMoteSyncApi {
  bool exists = false;
  Uint8List? uploadedBytes;
  String? uploadKey;
  int uploadLength = 0;
  bool uploadIfNoneMatch = false;
  String? confirmKey;
  String? deletedKey;

  @override
  Future<ReaMicroS3ObjectHead> fetchMoteHead(
    String token, {
    required String objectKey,
  }) async => ReaMicroS3ObjectHead(
    exists: exists,
    contentLength: uploadedBytes?.length ?? 0,
    etag: exists ? '"uploaded-etag"' : '',
  );

  @override
  Future<ReaMicroS3SignedUrl> fetchMoteUploadUrl(
    String token, {
    required String objectKey,
    required int contentLength,
    String ifMatch = '',
    bool ifNoneMatch = false,
  }) async {
    uploadKey = objectKey;
    uploadLength = contentLength;
    uploadIfNoneMatch = ifNoneMatch;
    return const ReaMicroS3SignedUrl(url: 'https://storage.test/upload');
  }

  @override
  Future<void> confirmMoteUpload(
    String token, {
    required String objectKey,
    required int contentLength,
  }) async {
    confirmKey = objectKey;
  }

  @override
  Future<ReaMicroS3SignedUrl> fetchMoteDownloadUrl(
    String token, {
    required String objectKey,
  }) async => const ReaMicroS3SignedUrl(url: 'https://storage.test/download');

  @override
  Future<void> deleteMoteObject(
    String token, {
    required String objectKey,
  }) async {
    deletedKey = objectKey;
    exists = false;
  }
}

ReaMicroS3SyncEngine _engine(
  LibraryStore library,
  _MemoryS3 store, {
  required String userId,
  required String deviceId,
  Map<String, int> cloudIds = const <String, int>{},
  Map<String, String> bookmarkBases = const <String, String>{},
  Map<String, String> localBookUuids = const <String, String>{},
  Set<String> pendingDeletions = const <String>{},
  Future<void> Function(String, String)? onBookIdentified,
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
  bookmarkBases: bookmarkBases,
  localBookUuids: localBookUuids,
  pendingDeletions: pendingDeletions,
  onBookIdentified: onBookIdentified,
);

class _MemoryS3 implements ReaMicroS3Client {
  final Map<String, ReaMicroS3Object> objects = <String, ReaMicroS3Object>{};
  var _etag = 0;
  var manifestConflicts = 0;
  var manifestPuts = 0;
  var bookDownloads = 0;

  Iterable<String> get keys => objects.keys;

  ReaMicroS3Object? object(String key) => objects[key];

  void putBytes(String key, Uint8List bytes) {
    objects[key] = ReaMicroS3Object(bytes: bytes, etag: '"${++_etag}"');
  }

  @override
  Future<ReaMicroS3Object?> get(String key) async {
    if (key.endsWith('/book.epub')) bookDownloads += 1;
    return objects[key];
  }

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
  final Map<String, List<BookBookmarkRecord>> _bookmarks =
      <String, List<BookBookmarkRecord>>{};

  List<BookBookmarkRecord> bookmarksOf(String bookId) =>
      List<BookBookmarkRecord>.of(_bookmarks[bookId] ?? const []);

  void setBookmarks(String bookId, List<BookBookmarkRecord> records) {
    _bookmarks[bookId] = List<BookBookmarkRecord>.of(records);
  }

  @override
  Future<List<BookBookmarkRecord>> listBookBookmarks(String bookId) async =>
      bookmarksOf(bookId);

  @override
  Future<void> applyBookBookmarkSnapshot(
    String bookId,
    Iterable<BookBookmarkRecord> bookmarks, {
    required bool removeMissing,
  }) async {
    final current = <String, BookBookmarkRecord>{
      for (final record in bookmarksOf(bookId)) record.cfi: record,
    };
    if (removeMissing) {
      final incoming = <String>{
        for (final record in bookmarks)
          if (record.cfi.trim().isNotEmpty) record.cfi.trim(),
      };
      current.removeWhere((cfi, _) => !incoming.contains(cfi));
    }
    for (final record in bookmarks) {
      final cfi = record.cfi.trim();
      if (cfi.isEmpty) continue;
      final existing = current[cfi];
      current[cfi] = BookBookmarkRecord(
        cfi: cfi,
        spineIndex: record.spineIndex != 0
            ? record.spineIndex
            : existing?.spineIndex ?? 0,
        title: record.title.isNotEmpty ? record.title : existing?.title ?? '',
        summary: record.summary,
        remark: record.remark,
        createdAt: record.createdAt > 0
            ? record.createdAt
            : existing?.createdAt ?? 0,
        updatedAt: record.updatedAt > 0
            ? record.updatedAt
            : existing?.updatedAt ?? 0,
      );
    }
    _bookmarks[bookId] = current.values.toList(growable: false);
  }

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
    BookImportConflictHandler? onConflict,
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
