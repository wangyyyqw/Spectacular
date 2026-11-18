import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:reader_mobile/rea_micro/rea_micro_github.dart';
import 'package:reader_mobile/rea_micro/rea_micro_s3.dart';

void main() {
  test('GitHub 读取固定提交下的二进制对象并返回对象 ETag', () async {
    final remote = _FakeGitHub();
    remote.write('reamicro/manifest.cbor', <int>[0, 1, 2, 255]);
    final object = await remote.client().get('reamicro/manifest.cbor');
    expect(object, isNotNull);
    expect(object!.bytes, <int>[0, 1, 2, 255]);
    expect(object.etag, '"${remote.objectSha('reamicro/manifest.cbor')}"');
    expect(
      remote.calls,
      contains('GET /repos/user/backup/contents/reamicro/manifest.cbor'),
    );
  });

  test('GitHub 已有对象拒绝创建且不产生任何写入', () async {
    final remote = _FakeGitHub();
    remote.write('reamicro/manifest.cbor', <int>[1]);
    await expectLater(
      remote.client().put(
        'reamicro/manifest.cbor',
        Uint8List.fromList(<int>[2]),
        ifNoneMatch: '*',
      ),
      throwsA(isA<ReaMicroS3ConflictException>()),
    );
    expect(remote.calls.every((call) => call.startsWith('GET ')), isTrue);
  });

  test('GitHub 过期版本拒绝覆盖并原子校验分支头', () async {
    final remote = _FakeGitHub();
    remote.write('reamicro/manifest.cbor', <int>[1]);
    await expectLater(
      remote.client().put(
        'reamicro/manifest.cbor',
        Uint8List.fromList(<int>[2]),
        ifMatch: '"${'9' * 40}"',
      ),
      throwsA(isA<ReaMicroS3ConflictException>()),
    );
    expect(remote.calls.every((call) => call.startsWith('GET ')), isTrue);

    final etag = '"${remote.objectSha('reamicro/manifest.cbor')}"';
    await remote.client().put(
      'reamicro/manifest.cbor',
      Uint8List.fromList(<int>[3, 4]),
      ifMatch: etag,
    );
    final publication = remote.publication!;
    final update = (publication['refUpdates']! as List<Object?>).single!
        as Map<String, Object?>;
    expect(update['name'], 'refs/heads/main');
    expect(update['beforeOid'], _head);
    expect(update['afterOid'], _commit);
    expect(update['force'], isFalse);
    expect(publication['repositoryId'], 'repo-node');
    expect(remote.objectBytes('reamicro/manifest.cbor'), <int>[3, 4]);
  });

  test('GitHub 分支被其他设备更新时按冲突重试', () async {
    final remote = _FakeGitHub()..stale = true;
    remote.write('reamicro/manifest.cbor', <int>[1]);
    await expectLater(
      remote.client().put(
        'reamicro/manifest.cbor',
        Uint8List.fromList(<int>[2]),
        ifMatch: '"${remote.objectSha('reamicro/manifest.cbor')}"',
      ),
      throwsA(isA<ReaMicroS3ConflictException>()),
    );
    expect(remote.publication, isNotNull);
    expect(remote.objectBytes('reamicro/manifest.cbor'), <int>[1]);
  });

  test('GitHub 删除只发布目标路径且缺失对象不写入', () async {
    final remote = _FakeGitHub();
    await remote.client().delete('reamicro/missing.epub');
    expect(remote.publication, isNull);

    remote.write('reamicro/old.epub', <int>[1]);
    await remote.client().delete('reamicro/old.epub');
    final entry = (remote.treeEntry! as Map<String, Object?>);
    expect(entry['path'], 'reamicro/old.epub');
    expect(entry['sha'], isNull);
    expect(remote.objectBytes('reamicro/old.epub'), isNull);
  });

  test('GitHub 仅允许私有仓库且必须具有写入权限', () async {
    final remote = _FakeGitHub()..privateRepo = false;
    await expectLater(
      remote.client().get('reamicro/manifest.cbor'),
      throwsA(isA<ReaMicroS3Exception>()),
    );
    expect(remote.calls, hasLength(1));

    final readOnly = _FakeGitHub()..pushPermission = false;
    await expectLater(
      readOnly.client().get('reamicro/manifest.cbor'),
      throwsA(isA<ReaMicroS3Exception>()),
    );
  });

  test('GitHub 仓库、分支与对象路径拒绝不安全取值', () {
    expect(
      ReaMicroGitHubProtocol.repository('https://github.com/user/backup.git'),
      'user/backup',
    );
    for (final value in <String>[
      'https://github.com.evil/user/backup',
      'https://github.com/user/backup?token=secret',
      'user/../backup',
    ]) {
      expect(
        () => ReaMicroGitHubProtocol.repository(value),
        throwsFormatException,
      );
    }
    expect(
      () => ReaMicroGitHubProtocol.branch('bad branch'),
      throwsFormatException,
    );
    expect(
      () => ReaMicroGitHubProtocol.key('../manifest'),
      throwsFormatException,
    );

    const config = ReaMicroS3Config(
      provider: 'GITHUB',
      endpoint: '',
      bucket: 'user/backup',
      region: '',
      accessKey: 'ghp_token',
      secretKey: '',
      prefix: 'reamicro',
      branch: 'main',
    );
    expect(config.usable, isTrue);
    expect(config.displayName, 'GitHub');
    expect(config.copyWith(bucket: '../backup').usable, isFalse);
    expect(config.copyWith(accessKey: '').usable, isFalse);
  });
}

const String _head = '1111111111111111111111111111111111111111';
const String _tree = '2222222222222222222222222222222222222222';
const String _nextTree = '5555555555555555555555555555555555555555';
const String _commit = '6666666666666666666666666666666666666666';

class _FakeGitHub extends http.BaseClient {
  final List<String> calls = <String>[];
  final Map<String, Uint8List> _objects = <String, Uint8List>{};
  final Map<String, Uint8List> _blobs = <String, Uint8List>{};
  bool privateRepo = true;
  bool pushPermission = true;
  bool stale = false;
  Map<String, Object?>? publication;
  Object? treeEntry;

  ReaMicroGitHubClient client() => ReaMicroGitHubClient(
    const ReaMicroS3Config(
      provider: 'GITHUB',
      endpoint: '',
      bucket: 'user/backup',
      region: '',
      accessKey: 'ghp_token',
      secretKey: '',
      prefix: 'reamicro',
    ),
    httpClient: this,
  );

  void write(String key, List<int> bytes) {
    final data = Uint8List.fromList(bytes);
    _objects[key] = data;
    _blobs[_sha(data)] = data;
  }

  String objectSha(String key) => _sha(_objects[key]!);

  List<int>? objectBytes(String key) => _objects[key];

  static String _sha(List<int> bytes) => sha1.convert(bytes).toString();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final method = request.method;
    calls.add('$method $path');
    final body = request is http.Request && request.body.isNotEmpty
        ? _decode(request.body)
        : null;
    final root = '/repos/user/backup';
    if (path == root && method == 'GET') {
      return _json(<String, Object?>{
        'private': privateRepo,
        'node_id': 'repo-node',
        'default_branch': 'main',
        'permissions': <String, Object?>{'push': pushPermission},
      });
    }
    if (path == '$root/git/ref/heads/main' && method == 'GET') {
      return _json(<String, Object?>{
        'object': <String, Object?>{'sha': _head},
      });
    }
    if (path == '$root/git/commits/$_head' && method == 'GET') {
      return _json(<String, Object?>{
        'tree': <String, Object?>{'sha': _tree},
      });
    }
    if (path.startsWith('$root/contents/') && method == 'GET') {
      final key = _decodeKey(path.substring('$root/contents/'.length));
      final data = _objects[key];
      if (data == null || request.url.queryParameters['ref'] != _head) {
        return _json(<String, Object?>{}, status: 404);
      }
      return _json(<String, Object?>{
        'type': 'file',
        'sha': _sha(data),
        'size': data.length,
      });
    }
    if (path.startsWith('$root/git/blobs/') && method == 'GET') {
      final sha = path.substring('$root/git/blobs/'.length);
      final data = _blobs[sha];
      if (data == null) return _json(<String, Object?>{}, status: 404);
      return _json(<String, Object?>{
        'sha': sha,
        'size': data.length,
        'encoding': 'base64',
        'content': base64Encode(data),
      });
    }
    if (path == '$root/git/blobs' && method == 'POST') {
      final data = base64Decode(body!['content']! as String);
      final sha = _sha(data);
      _blobs[sha] = Uint8List.fromList(data);
      return _json(<String, Object?>{'sha': sha});
    }
    if (path == '$root/git/trees' && method == 'POST') {
      expect(body!['base_tree'], _tree);
      treeEntry = (body['tree']! as List<Object?>).single;
      return _json(<String, Object?>{'sha': _nextTree});
    }
    if (path == '$root/git/commits' && method == 'POST') {
      expect((body!['parents']! as List<Object?>).single, _head);
      return _json(<String, Object?>{'sha': _commit});
    }
    if (path == '/graphql' && method == 'POST') {
      final variables = body!['variables']! as Map<String, Object?>;
      publication = variables['input']! as Map<String, Object?>;
      final entry = treeEntry! as Map<String, Object?>;
      final key = entry['path']! as String;
      if (stale) {
        return _json(<String, Object?>{
          'errors': <Object?>[
            <String, Object?>{'type': 'STALE_DATA', 'message': 'changed'},
          ],
        });
      }
      if (entry['sha'] == null) {
        _objects.remove(key);
      } else {
        final sha = entry['sha']! as String;
        _objects[key] = _blobs[sha]!;
      }
      return _json(<String, Object?>{
        'data': <String, Object?>{
          'updateRefs': <String, Object?>{'clientMutationId': _commit},
        },
      });
    }
    return _json(<String, Object?>{'message': 'unexpected'}, status: 500);
  }

  Map<String, Object?> _decode(String text) =>
      jsonDecode(text) as Map<String, Object?>;

  String _decodeKey(String encoded) => encoded
      .split('/')
      .map(Uri.decodeComponent)
      .join('/');

  http.StreamedResponse _json(Object? value, {int status = 200}) =>
      http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode(jsonEncode(value))),
        status,
        headers: <String, String>{'content-type': 'application/json'},
      );
}
