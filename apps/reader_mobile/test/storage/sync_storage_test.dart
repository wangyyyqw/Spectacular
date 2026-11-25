import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/sync/sync_engine.dart';
import 'package:reader_mobile/sync/sync_models.dart';
import 'package:reader_mobile/sync/sync_s3.dart';
import 'package:reader_mobile/sync/sync_storage.dart';
import 'package:reader_mobile/sync/sync_webdav.dart';
import 'package:xml/xml.dart';

import '../support/test_epub.dart';

class _SyncHttpBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _SyncHttpBinding();
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  test('SigV4 与 AWS 公开 GET Object 示例签名一致', () {
    // AWS 公开示例凭证，仅用于回归；同一向量亦由 TensorStore 的 S3 测试覆盖。
    final headers = SyncS3Signer.sign(
      'GET',
      Uri.parse('https://examplebucket.s3.amazonaws.com/test.txt'),
      sha256.convert([]).toString(),
      const SyncProfile(
        provider: SyncProvider.s3,
        endpoint: 'https://s3.amazonaws.com',
      ),
      const SyncCredentials(
        access:
            'AKIA'
            'IOSFODNN7EXAMPLE',
        secret:
            'wJalrXUtnFEMI/'
            'K7MDENG/bPxRfiCYEXAMPLEKEY',
      ),
      extra: {'range': 'bytes=0-9'},
      now: DateTime.utc(2013, 5, 24),
    );
    expect(headers['x-amz-date'], '20130524T000000Z');
    expect(
      headers['authorization'],
      endsWith(
        'Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41',
      ),
    );
  });

  for (final provider in SyncProvider.values) {
    test('${provider.name} 正式引擎从分类目录恢复加密书籍、书签和统计', () async {
      final server = await _ObjectServer.start(provider);
      addTearDown(() => server.server.close(force: true));
      final libraries = <LibraryStore>[];
      for (var index = 0; index < 2; index++) {
        final root = await Directory.systemTemp.createTemp('sync-http-engine-');
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(() async {
          await db.close();
          await root.delete(recursive: true);
        });
        libraries.add(
          LibraryStore(database: db, directoryProvider: () async => root),
        );
      }
      final profile = SyncProfile(
        provider: provider,
        endpoint: 'http://127.0.0.1:${server.server.port}',
        bucket: 'bucket',
        prefix: '团队/spectacular-sync',
        automatic: false,
      );
      const credentials = SyncCredentials(
        access: 'test-access',
        secret: 'test-secret',
      );
      final SyncStorage storage = provider == SyncProvider.s3
          ? SyncS3Storage(profile, credentials)
          : SyncWebDavStorage(profile, credentials);
      addTearDown(storage.close);
      SyncEngine engine(LibraryStore library, [String recovery = '']) =>
          SyncEngine(
            repository: library.syncRepository(),
            storage: storage,
            profile: profile,
            credentials: SyncCredentials(recovery: recovery),
          );
      final a = libraries.first;
      final b = libraries.last;
      final book = await a.importBytes(buildTestEpub(title: '加密同步书'));
      await a
          .bookmarkStore(book.id)!
          .add(cfi: 'epubcfi(/6/2!/4/4/1:0)', spineIndex: 0, label: '同步书签');
      await a.readingSessionStore()!.add(
        bookId: book.id,
        startedAt: DateTime(2026),
        endedAt: DateTime(2026).add(const Duration(minutes: 5)),
      );
      final recovery = await engine(a).create(encrypted: true);
      expect((await engine(a, recovery).sync()).uploaded, 1);
      expect((await engine(b, recovery).sync()).downloaded, 1);
      final restored = (await b.list()).single;
      expect(restored.title, book.title);
      expect((await b.bookmarkStore(restored.id)!.list()).single.label, '同步书签');
      expect(
        (await b.readingSessionStore()!.list()).single.duration,
        const Duration(minutes: 5),
      );
      expect((await engine(b, recovery).sync()).uploaded, 0);
      expect(
        server.files.keys.any(
          (key) => key.contains('/book/') && key.endsWith('.epub.enc'),
        ),
        isTrue,
      );
      expect(
        server.files.keys.any(
          (key) => key.contains('/personal/statistics/changes/'),
        ),
        isTrue,
      );
    });

    test('${provider.name} 正式 HTTP 客户端完成 Unicode 路径、流式文件与设备目录列举', () async {
      final server = await _ObjectServer.start(provider);
      addTearDown(() => server.server.close(force: true));
      final root = await Directory.systemTemp.createTemp('sync-http-');
      addTearDown(() => root.delete(recursive: true));
      final profile = SyncProfile(
        provider: provider,
        endpoint: 'http://127.0.0.1:${server.server.port}',
        bucket: 'bucket',
        prefix: '团队/阅读',
      );
      const credentials = SyncCredentials(
        access: 'test-access',
        secret: 'test-secret',
      );
      final SyncStorage client = provider == SyncProvider.s3
          ? SyncS3Storage(profile, credentials)
          : SyncWebDavStorage(profile, credentials);
      addTearDown(client.close);
      final bytes = Uint8List.fromList(
        List.generate(256 * 1024 + 19, (i) => i % 251),
      );
      final source = await File('${root.path}/source').writeAsBytes(bytes);
      const directory = 'book/book-id/annotations/changes';
      const key = '$directory/node/batch.json';
      await client.upload(key, source, createOnly: true);
      expect(await client.read(key), bytes);
      expect(await client.list(directory), ['$directory/node']);
      expect(await client.list('$directory/node'), [key]);
      final restored = File('${root.path}/restored');
      await client.download(key, restored);
      expect(await restored.readAsBytes(), bytes);
      await expectLater(
        client.upload(key, source, createOnly: true),
        throwsA(isA<HttpException>()),
      );
      await client.delete(key);
      expect(await client.read(key), isNull);
      expect(server.authenticated, isTrue);
    });
  }
}

class _ObjectServer {
  _ObjectServer(this.server, this.provider);
  final HttpServer server;
  final SyncProvider provider;
  final files = <String, Uint8List>{};
  bool authenticated = false;

  static Future<_ObjectServer> start(SyncProvider provider) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = _ObjectServer(server, provider);
    server.listen(fixture.handle);
    return fixture;
  }

  String _xml(String value) => XmlText(value).toXmlString();

  Future<void> handle(HttpRequest request) async {
    final data = BytesBuilder(copy: false);
    await for (final chunk in request) {
      data.add(chunk);
    }
    final bytes = data.takeBytes();
    final auth = request.headers.value('authorization') ?? '';
    authenticated = provider == SyncProvider.s3
        ? auth.startsWith('AWS4-HMAC-SHA256 ')
        : auth ==
              'Basic ${base64Encode(utf8.encode('test-access:test-secret'))}';
    if (!authenticated) {
      request.response.statusCode = 401;
      await request.response.close();
      return;
    }
    if (provider == SyncProvider.s3 &&
        request.headers.value('x-amz-content-sha256') !=
            sha256.convert(bytes).toString()) {
      request.response.statusCode = 400;
      await request.response.close();
      return;
    }
    final path = request.uri.pathSegments
        .where((part) => part.isNotEmpty)
        .join('/');
    if (request.method == 'MKCOL') {
      request.response.statusCode = 201;
    } else if (request.method == 'PUT') {
      if (request.headers.value('if-none-match') == '*' &&
          files.containsKey(path)) {
        request.response.statusCode = 412;
      } else {
        files[path] = bytes;
        request.response.statusCode = 201;
      }
    } else if (request.method == 'PROPFIND') {
      request.response.statusCode = 207;
      request.response.write(_dav(path));
    } else if (request.uri.queryParameters['list-type'] == '2') {
      request.response.write(_s3(request.uri.queryParameters['prefix']!));
    } else if (request.method == 'DELETE') {
      files.remove(path);
      request.response.statusCode = 204;
    } else if (!files.containsKey(path)) {
      request.response.statusCode = 404;
    } else {
      request.response.add(files[path]!);
    }
    await request.response.close();
  }

  Set<String> _children(
    String prefix,
  ) => files.keys.where((key) => key.startsWith(prefix)).map((key) {
    final rest = key.substring(prefix.length);
    return '$prefix${rest.split('/').first}${rest.contains('/') ? '/' : ''}';
  }).toSet();

  String _dav(String path) {
    final prefix = '$path/';
    return '<d:multistatus xmlns:d="DAV:">${{prefix, ..._children(prefix)}.map((key) => '<d:response><d:href>${_xml('/${key.split('/').map(Uri.encodeComponent).join('/')}')}</d:href>'
        '<d:propstat><d:prop><d:resourcetype>${key.endsWith('/') ? '<d:collection/>' : ''}'
        '</d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status>'
        '</d:propstat></d:response>').join()}</d:multistatus>';
  }

  String _s3(String prefix) {
    final keys = _children('bucket/$prefix').map((key) => key.substring(7));
    return '<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">'
        '<Prefix>${_xml(prefix)}</Prefix><IsTruncated>false</IsTruncated>'
        '${keys.map((key) => key.endsWith('/') ? '<CommonPrefixes><Prefix>${_xml(key)}</Prefix></CommonPrefixes>' : '<Contents><Key>${_xml(key)}</Key></Contents>').join()}</ListBucketResult>';
  }
}
