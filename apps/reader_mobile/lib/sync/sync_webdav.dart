import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

import 'sync_models.dart';
import 'sync_s3.dart' show xmlText;
import 'sync_storage.dart';

class SyncWebDavStorage extends SyncHttpStorage {
  SyncWebDavStorage(super.profile, this.credentials, {super.client});
  final SyncCredentials credentials;

  @override
  Map<String, String> headers(
    String method,
    Uri uri,
    String digest,
    Map<String, String> extra,
  ) => {
    ...extra,
    if (credentials.access.isNotEmpty || credentials.secret.isNotEmpty)
      'authorization':
          'Basic ${base64Encode(utf8.encode('${credentials.access}:${credentials.secret}'))}',
  };

  Future<void> _parents(String key) async {
    final segments = [
      ...profile.uri.pathSegments.where((part) => part.isNotEmpty),
    ];
    final parts = [...profile.directory.split('/'), ...key.split('/')]
      ..removeLast();
    for (final part in parts) {
      segments.add(part);
      final uri = profile.uri.replace(pathSegments: [...segments, '']);
      final response = await request('MKCOL', uri);
      if (response.statusCode != 405) check(response, '创建 WebDAV 同步目录');
      await response.stream.timeout(SyncHttpStorage.timeout).drain<void>();
    }
  }

  @override
  Future<void> upload(String key, File file, {bool createOnly = false}) async {
    await _parents(key);
    await super.upload(key, file, createOnly: createOnly);
  }

  @override
  Future<List<String>> list(String directory) async {
    final uri = address(directory, directory: true);
    final response = await request(
      'PROPFIND',
      uri,
      extra: {'depth': '1', 'content-type': 'application/xml; charset=utf-8'},
      bytes: utf8.encode(
        '<d:propfind xmlns:d="DAV:"><d:prop>'
        '<d:resourcetype/></d:prop></d:propfind>',
      ),
    );
    if (response.statusCode == 404) {
      await response.stream.drain<void>();
      return [];
    }
    if (response.statusCode != 207) check(response, '列出 WebDAV 同步数据');
    final document = XmlDocument.parse(
      utf8.decode(await responseBytes(response)),
    );
    final root = address('', directory: true).path;
    final result = <String>{};
    for (final item in document.descendants.whereType<XmlElement>()) {
      if (item.name.local != 'response') continue;
      final href = xmlText(item, 'href');
      if (href == null) throw const FormatException('WebDAV 列表缺少资源路径');
      final path = Uri.parse(href).path;
      if (path == uri.path || !path.startsWith(root)) continue;
      final status = xmlText(item, 'status') ?? '';
      if (!status.contains(' 200 ')) {
        throw const FormatException('WebDAV 列表包含无法读取的资源');
      }
      final key = Uri.decodeComponent(path.substring(root.length))
          .replaceAll(RegExp(r'/+$'), '');
      if (key.isEmpty || key == directory) continue;
      validateSyncPath(key);
      result.add(key);
    }
    return result.toList()..sort();
  }
}
