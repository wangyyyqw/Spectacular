import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import 'sync_models.dart';
import 'sync_storage.dart';

/// 标准 SigV4；签名包含条件头、完整对象路径及排序后的查询参数。
class SyncS3Signer {
  static Map<String, String> sign(
    String method,
    Uri uri,
    String payloadHash,
    SyncProfile profile,
    SyncCredentials credentials, {
    Map<String, String> extra = const {},
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now())
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[-:]'), '')
        .split('.')
        .first;
    final date = timestamp.substring(0, 8);
    final amzDate = '${timestamp}Z';
    final headers = <String, String>{
      ...extra,
      'host': uri.hasPort ? '${uri.host}:${uri.port}' : uri.host,
      'x-amz-date': amzDate,
      'x-amz-content-sha256': payloadHash,
    };
    final keys = headers.keys.toList()..sort();
    final query = <String>[
      for (final entry in uri.queryParametersAll.entries)
        for (final value in entry.value)
          '${_encode(entry.key)}=${_encode(value)}',
    ]..sort();
    final canonical = [
      method,
      uri.path.isEmpty ? '/' : uri.path,
      query.join('&'),
      '${keys.map((key) => '$key:${headers[key]!.trim()}').join('\n')}\n',
      keys.join(';'),
      payloadHash,
    ].join('\n');
    final scope = '$date/${profile.region.trim()}/s3/aws4_request';
    final toSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      scope,
      sha256.convert(utf8.encode(canonical)).toString(),
    ].join('\n');
    List<int> signingKey = utf8.encode('AWS4${credentials.secret}');
    for (final component in [
      date,
      profile.region.trim(),
      's3',
      'aws4_request',
    ]) {
      signingKey = Hmac(
        sha256,
        signingKey,
      ).convert(utf8.encode(component)).bytes;
    }
    final signature = Hmac(sha256, signingKey).convert(utf8.encode(toSign));
    return {
      ...headers,
      'authorization':
          'AWS4-HMAC-SHA256 '
          'Credential=${credentials.access.trim()}/$scope, '
          'SignedHeaders=${keys.join(';')}, Signature=$signature',
    };
  }

  static String _encode(String value) => utf8.encode(value).map((byte) {
    if ((byte >= 65 && byte <= 90) ||
        (byte >= 97 && byte <= 122) ||
        (byte >= 48 && byte <= 57) ||
        const [45, 46, 95, 126].contains(byte)) {
      return String.fromCharCode(byte);
    }
    return '%${byte.toRadixString(16).padLeft(2, '0').toUpperCase()}';
  }).join();
}

class SyncS3Storage extends SyncHttpStorage {
  SyncS3Storage(super.profile, this.credentials, {super.client});
  final SyncCredentials credentials;

  @override
  Map<String, String> headers(
    String method,
    Uri uri,
    String digest,
    Map<String, String> extra,
  ) => SyncS3Signer.sign(
    method,
    uri,
    digest,
    profile,
    credentials,
    extra: extra,
  );

  @override
  Future<List<String>> list(String directory) async {
    final root = '${profile.directory}/';
    final prefix = '$root${directory.isEmpty ? '' : '$directory/'}';
    final result = <String>{};
    String? token;
    do {
      final uri = address('').replace(
        queryParameters: {
          'list-type': '2',
          'prefix': prefix,
          'delimiter': '/',
          'continuation-token': ?token,
        },
      );
      // 列举请求必须发送到桶根，而不是同步目录对象。
      final bucket = uri.replace(
        pathSegments: [
          ...profile.uri.pathSegments.where((part) => part.isNotEmpty),
          profile.bucket.trim(),
        ],
      );
      final response = await request('GET', bucket);
      check(response, '列出 S3 同步数据');
      final document = XmlDocument.parse(
        utf8.decode(await responseBytes(response)),
      );
      for (final node in document.descendants.whereType<XmlElement>()) {
        if (node.name.local != 'Key' && node.name.local != 'Prefix') continue;
        var key = node.innerText;
        if (key == prefix || !key.startsWith(root)) continue;
        key = key.substring(root.length).replaceAll(RegExp(r'/+$'), '');
        validateSyncPath(key);
        result.add(key);
      }
      final truncated = xmlText(document, 'IsTruncated') == 'true';
      token = truncated ? xmlText(document, 'NextContinuationToken') : null;
      if (truncated && (token == null || token.isEmpty)) {
        throw const FormatException('S3 列表未完整返回');
      }
    } while (token != null);
    return result.toList()..sort();
  }
}

String? xmlText(XmlNode node, String name) => node.descendants
    .whereType<XmlElement>()
    .where((child) => child.name.local == name)
    .firstOrNull
    ?.innerText;
