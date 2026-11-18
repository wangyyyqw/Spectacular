import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/rea_micro/rea_micro_s3.dart';
import 'package:reader_mobile/rea_micro/rea_micro_webdav.dart';

void main() {
  test('WebDAV 使用强 ETag 完成创建、覆盖、读取与删除', () async {
    final dav = await _FakeWebDav.start();
    addTearDown(dav.close);
    final client = ReaMicroWebDavClient(
      ReaMicroS3Config(
        provider: 'WEBDAV',
        endpoint: dav.baseUrl,
        bucket: '',
        region: '',
        accessKey: 'user',
        secretKey: 'pass',
        prefix: 'reamicro',
      ),
    );

    await client.put(
      'reamicro/manifest.cbor',
      Uint8List.fromList(<int>[1, 2, 3]),
      ifNoneMatch: '*',
    );
    expect(dav.directories, contains('reamicro'));

    final first = await client.get('reamicro/manifest.cbor');
    expect(first, isNotNull);
    expect(first!.bytes, <int>[1, 2, 3]);
    expect(first.etag.startsWith('"'), isTrue);

    await expectLater(
      client.put(
        'reamicro/manifest.cbor',
        Uint8List.fromList(<int>[9]),
        ifNoneMatch: '*',
      ),
      throwsA(isA<ReaMicroS3ConflictException>()),
    );

    await client.put(
      'reamicro/manifest.cbor',
      Uint8List.fromList(<int>[4, 5]),
      ifMatch: first.etag,
    );
    final second = await client.get('reamicro/manifest.cbor');
    expect(second!.bytes, <int>[4, 5]);
    expect(second.etag, isNot(first.etag));

    await expectLater(
      client.put(
        'reamicro/manifest.cbor',
        Uint8List.fromList(<int>[6]),
        ifMatch: first.etag,
      ),
      throwsA(isA<ReaMicroS3ConflictException>()),
    );

    await client.delete('reamicro/manifest.cbor');
    expect(await client.get('reamicro/manifest.cbor'), isNull);
    expect(dav.authorization, 'Basic ${base64Encode(utf8.encode('user:pass'))}');
  });

  test('WebDAV 拒绝弱 ETag 服务', () async {
    final dav = await _FakeWebDav.start(weakEtag: true);
    addTearDown(dav.close);
    final client = ReaMicroWebDavClient(
      ReaMicroS3Config(
        provider: 'WEBDAV',
        endpoint: dav.baseUrl,
        bucket: '',
        region: '',
        accessKey: '',
        secretKey: '',
        prefix: 'reamicro',
      ),
    );
    await client.put(
      'reamicro/probe',
      Uint8List.fromList(<int>[1]),
      ifNoneMatch: '*',
    );
    await expectLater(
      client.get('reamicro/probe'),
      throwsA(
        isA<ReaMicroS3Exception>().having(
          (error) => error.message,
          'message',
          contains('强 ETag'),
        ),
      ),
    );
  });

  test('WebDAV 配置只接受 HTTP(S) 目录', () {
    const base = ReaMicroS3Config(
      provider: 'WEBDAV',
      endpoint: 'https://dav.example.com/files/me',
      bucket: '',
      region: '',
      accessKey: '',
      secretKey: '',
      prefix: 'reamicro',
    );
    expect(base.usable, isTrue);
    expect(base.displayName, 'WebDAV');
    expect(
      base.copyWith(endpoint: 'ftp://dav.example.com').usable,
      isFalse,
    );
    expect(
      base.copyWith(endpoint: 'https://user@dav.example.com').usable,
      isFalse,
    );
    expect(
      base.copyWith(endpoint: 'https://dav.example.com?token=1').usable,
      isFalse,
    );
  });
}

class _FakeWebDav {
  _FakeWebDav._(this._server, this.weakEtag);

  final HttpServer _server;
  final bool weakEtag;
  final Map<String, _StoredFile> files = <String, _StoredFile>{};
  final Set<String> directories = <String>{};
  String? authorization;
  int _version = 0;

  String get baseUrl => 'http://127.0.0.1:${_server.port}/dav';

  static Future<_FakeWebDav> start({bool weakEtag = false}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeWebDav._(server, weakEtag);
    unawaited(server.forEach(fake._handle));
    return fake;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final key = request.uri.pathSegments
        .skip(1)
        .where((segment) => segment.isNotEmpty)
        .join('/');
    authorization = request.headers.value('authorization');
    if (authorization != null &&
        authorization != 'Basic ${base64Encode(utf8.encode('user:pass'))}') {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }
    switch (request.method) {
      case 'MKCOL':
        if (directories.contains(key)) {
          request.response.statusCode = HttpStatus.methodNotAllowed;
        } else {
          directories.add(key);
          request.response.statusCode = HttpStatus.created;
        }
      case 'PUT':
        final existing = files[key];
        final ifNoneMatch = request.headers.value('if-none-match');
        final ifMatch = request.headers.value('if-match');
        if (ifNoneMatch == '*' && existing != null) {
          request.response.statusCode = HttpStatus.preconditionFailed;
        } else if (ifMatch != null && existing?.etag != ifMatch) {
          request.response.statusCode = HttpStatus.preconditionFailed;
        } else {
          final bytes = await _read(request);
          final etag = '"v${++_version}"';
          files[key] = _StoredFile(bytes, etag);
          request.response.headers.set('etag', etag);
          request.response.statusCode = existing == null
              ? HttpStatus.created
              : HttpStatus.ok;
        }
      case 'GET':
      case 'HEAD':
        final file = files[key];
        if (file == null && directories.contains(key)) {
          request.response.statusCode = HttpStatus.ok;
        } else if (file == null) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set(
            'etag',
            weakEtag ? 'W/${file.etag}' : file.etag,
          );
          if (request.method == 'GET') {
            request.response.add(file.bytes);
          }
        }
      case 'DELETE':
        request.response.statusCode = files.remove(key) == null
            ? HttpStatus.notFound
            : HttpStatus.noContent;
      default:
        request.response.statusCode = HttpStatus.methodNotAllowed;
    }
    await request.response.close();
  }

  Future<Uint8List> _read(HttpRequest request) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}

class _StoredFile {
  const _StoredFile(this.bytes, this.etag);

  final Uint8List bytes;
  final String etag;
}
