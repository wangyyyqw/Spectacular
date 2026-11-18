import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'rea_micro_s3.dart';

/// GitHub 私有仓库同步的地址与版本约束。
class ReaMicroGitHubProtocol {
  ReaMicroGitHubProtocol._();

  /// 固定官方 API，避免 Token 被发送到其他主机。
  static const String api = 'https://api.github.com';

  /// 单个同步对象上限；GitHub 正文接口按 Base64 传输。
  static const int maxFileBytes = 40 * 1024 * 1024;

  static final RegExp _oid = RegExp(r'^[0-9a-f]{40}$');
  static final RegExp _owner = RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$');
  static final RegExp _repository = RegExp(r'^[A-Za-z0-9_.-]+$');

  /// 规范化仓库地址，支持 `所有者/仓库` 与 GitHub HTTPS 地址。
  static String repository(String value) {
    final text = value.trim();
    var path = text;
    if (text.startsWith('https://')) {
      final uri = Uri.tryParse(text);
      if (uri == null ||
          uri.host != 'github.com' ||
          uri.hasPort ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) {
        throw const FormatException('请输入 GitHub 私有仓库地址或 所有者/仓库');
      }
      path = uri.path;
    } else if (text.contains('://')) {
      throw const FormatException('请输入 GitHub 私有仓库地址或 所有者/仓库');
    }
    path = path.replaceAll(RegExp(r'^/+|/+$'), '').replaceFirst(
      RegExp(r'\.git$'),
      '',
    );
    final parts = path.split('/');
    if (parts.length != 2 ||
        !_owner.hasMatch(parts[0]) ||
        !_repository.hasMatch(parts[1]) ||
        parts[1] == '.' ||
        parts[1] == '..') {
      throw const FormatException(
        '仓库格式应为 所有者/仓库，例如 username/reamicro-backup',
      );
    }
    return parts.join('/');
  }

  /// 校验分支名；空值表示使用仓库默认分支。
  static String branch(String value) {
    final text = value.trim();
    if (text.isEmpty) return '';
    final valid =
        !text.runes.any((char) => char <= 0x20 || char == 0x7f) &&
        !text.contains('~') &&
        !text.contains('^') &&
        !text.contains(':') &&
        !text.contains('?') &&
        !text.contains('*') &&
        !text.contains('[') &&
        !text.contains('\\') &&
        !text.contains('..') &&
        !text.contains('@{') &&
        text != '@' &&
        !text.endsWith('.') &&
        !text.split('/').any(
          (part) =>
              part.isEmpty || part.startsWith('.') || part.endsWith('.lock'),
        );
    if (!valid) {
      throw const FormatException('请输入有效的 Git 分支名；留空使用仓库默认分支');
    }
    return text;
  }

  /// 校验访问令牌。
  static String token(String value) {
    final text = value.trim();
    if (text.isEmpty || text.runes.any((char) => char < 0x21 || char > 0x7e)) {
      throw const FormatException('请输入有效的 GitHub Token');
    }
    return text;
  }

  /// 校验同步对象路径，禁止空段与目录穿越。
  static String key(String value) {
    final text = value;
    final valid =
        text.isNotEmpty &&
        !text.startsWith('/') &&
        !text.contains('\\') &&
        !text.runes.any((char) => char < 0x20 || char == 0x7f) &&
        !text
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..');
    if (!valid) throw const FormatException('无效的 GitHub 同步对象路径');
    return text;
  }

  /// 对路径段进行 URL 编码。
  static String encode(String value) => Uri.encodeComponent(value);

  /// 校验 Git 对象 SHA。
  static String oid(String value) {
    if (!_oid.hasMatch(value)) {
      throw const FormatException('GitHub 返回了无效的 Git 对象版本');
    }
    return value;
  }

  /// Git 对象 SHA 对应的强 ETag。
  static String etag(String sha) => '"$sha"';

  /// 从条件头中取出期望的对象 SHA。
  static String expectedSha(String condition) {
    final text = condition.trim();
    if (text.length != 42 || !text.startsWith('"') || !text.endsWith('"')) {
      throw const FormatException('GitHub 同步版本条件无效');
    }
    return oid(text.substring(1, 41));
  }
}

/// 用 GitHub Git 数据接口模拟读写对象，作为阅微同步存储。
///
/// 每次写入通过 GraphQL `updateRefs` 的 `beforeOid` 原子校验分支头，
/// 失败时按 412 冲突交给上层重新读取清单。
class ReaMicroGitHubClient implements ReaMicroS3Client {
  /// 创建客户端。
  ReaMicroGitHubClient(this.config, {http.Client? httpClient})
    : _http = httpClient ?? http.Client() {
    repository = ReaMicroGitHubProtocol.repository(config.bucket);
    branch = config.branch.isEmpty
        ? ''
        : ReaMicroGitHubProtocol.branch(config.branch);
    token = ReaMicroGitHubProtocol.token(config.accessKey);
  }

  /// 同步配置。
  final ReaMicroS3Config config;
  final http.Client _http;

  /// 规范化后的 `所有者/仓库`。
  late final String repository;

  /// 配置的分支；空值使用默认分支。
  late final String branch;

  /// GitHub 访问令牌。
  late final String token;

  static const Duration _timeout = Duration(seconds: 120);

  @override
  Future<ReaMicroS3Object?> get(String key) async {
    final path = ReaMicroGitHubProtocol.key(key);
    final head = await _head();
    final info = await _info(path, head);
    if (info == null) return null;
    final bytes = await _content(info);
    return ReaMicroS3Object(bytes: bytes, etag: ReaMicroGitHubProtocol.etag(info.sha));
  }

  @override
  Future<String> put(
    String key,
    Uint8List bytes, {
    String contentType = 'application/octet-stream',
    String? ifMatch,
    String? ifNoneMatch,
  }) async {
    final path = ReaMicroGitHubProtocol.key(key);
    if (bytes.length > ReaMicroGitHubProtocol.maxFileBytes) {
      throw const ReaMicroS3Exception('GitHub 单个同步文件不能超过 40 MiB，请改用 WebDAV');
    }
    final head = await _head();
    final existing = await _info(path, head);
    if (ifNoneMatch == '*') {
      if (existing != null) {
        throw const ReaMicroS3ConflictException('云端对象已存在，请重新读取清单');
      }
    } else if (ifMatch != null && ifMatch.isNotEmpty) {
      if (ifMatch == '*') {
        if (existing == null) {
          throw const ReaMicroS3ConflictException('云端对象已被移除，请重新读取清单');
        }
      } else if (existing?.sha != ReaMicroGitHubProtocol.expectedSha(ifMatch)) {
        throw const ReaMicroS3ConflictException('云端对象已被其他设备修改');
      }
    }
    final sha = await _createBlob(bytes);
    if (existing?.sha == sha) {
      return ReaMicroGitHubProtocol.etag(sha);
    }
    await _publish(path, sha, head);
    return ReaMicroGitHubProtocol.etag(sha);
  }

  @override
  Future<void> delete(String key) async {
    final path = ReaMicroGitHubProtocol.key(key);
    final head = await _head();
    final existing = await _info(path, head);
    if (existing == null) return;
    await _publish(path, null, head);
  }

  Future<_GitHubHead> _head() async {
    final repositoryInfo = await _readRepository();
    final branchName = branch.isEmpty
        ? ReaMicroGitHubProtocol.branch(
            repositoryInfo['default_branch']?.toString() ?? '',
          )
        : branch;
    if (branchName.isEmpty) {
      throw const ReaMicroS3Exception('GitHub 仓库没有默认分支，请先创建一次提交');
    }
    final ref = await _send(
      'GET',
      '/repos/$repository/git/ref/heads/${ReaMicroGitHubProtocol.encode(branchName)}',
    );
    if (ref.statusCode == 404 || ref.statusCode == 409) {
      throw const ReaMicroS3Exception('GitHub 分支不存在或仓库为空，请先创建一次提交');
    }
    final commit = ReaMicroGitHubProtocol.oid(
      _asMap(_json(ref)['object'])['sha']?.toString() ?? '',
    );
    final commitData = _json(
      await _send('GET', '/repos/$repository/git/commits/$commit'),
    );
    final tree = ReaMicroGitHubProtocol.oid(
      _asMap(commitData['tree'])['sha']?.toString() ?? '',
    );
    return _GitHubHead(
      nodeId: repositoryInfo['node_id']?.toString() ?? '',
      branch: branchName,
      commit: commit,
      tree: tree,
    );
  }

  Future<Map<String, Object?>> _readRepository() async {
    final value = _json(await _send('GET', '/repos/$repository'));
    if (value['private'] != true) {
      throw const ReaMicroS3Exception('GitHub 同步仅支持私有仓库，请先把仓库设为私有');
    }
    if (_asMap(value['permissions'])['push'] != true) {
      throw const ReaMicroS3Exception(
        'Token 没有仓库写入权限，请授权 Contents 读写或 repo 权限',
      );
    }
    return value;
  }

  Future<_GitHubObjectInfo?> _info(String path, _GitHubHead head) async {
    final encoded = path
        .split('/')
        .map(ReaMicroGitHubProtocol.encode)
        .join('/');
    final response = await _send(
      'GET',
      '/repos/$repository/contents/$encoded?ref=${head.commit}',
    );
    if (response.statusCode == 404) return null;
    final value = _json(response);
    if (value['type']?.toString() != 'file') {
      throw const ReaMicroS3Exception('GitHub 同步路径被目录或符号链接占用');
    }
    return _GitHubObjectInfo(
      sha: ReaMicroGitHubProtocol.oid(value['sha']?.toString() ?? ''),
      size: _asInt(value['size']),
    );
  }

  Future<Uint8List> _content(_GitHubObjectInfo info) async {
    if (info.size < 0 || info.size > ReaMicroGitHubProtocol.maxFileBytes) {
      throw const ReaMicroS3Exception('GitHub 单个同步文件不能超过 40 MiB，请改用 WebDAV');
    }
    final value = _json(
      await _send('GET', '/repos/$repository/git/blobs/${info.sha}'),
    );
    if (value['encoding']?.toString() != 'base64') {
      throw const ReaMicroS3Exception('GitHub 返回了不支持的正文编码');
    }
    final content = (value['content']?.toString() ?? '')
        .replaceAll('\n', '')
        .replaceAll('\r', '');
    final bytes = Uint8List.fromList(base64Decode(content));
    if (bytes.length != info.size || _asInt(value['size']) != info.size) {
      throw const ReaMicroS3Exception('GitHub 正文大小不一致');
    }
    return bytes;
  }

  Future<String> _createBlob(Uint8List bytes) async {
    final value = _json(
      await _send(
        'POST',
        '/repos/$repository/git/blobs',
        body: <String, Object?>{
          'content': base64Encode(bytes),
          'encoding': 'base64',
        },
      ),
    );
    return ReaMicroGitHubProtocol.oid(value['sha']?.toString() ?? '');
  }

  Future<void> _publish(String path, String? sha, _GitHubHead head) async {
    final tree = _json(
      await _send(
        'POST',
        '/repos/$repository/git/trees',
        body: <String, Object?>{
          'base_tree': head.tree,
          'tree': <Object?>[
            <String, Object?>{
              'path': path,
              'mode': '100644',
              'type': 'blob',
              'sha': sha,
            },
          ],
        },
      ),
    );
    final newTree = ReaMicroGitHubProtocol.oid(tree['sha']?.toString() ?? '');
    final commit = _json(
      await _send(
        'POST',
        '/repos/$repository/git/commits',
        body: <String, Object?>{
          'message': 'ReaMicro sync',
          'tree': newTree,
          'parents': <String>[head.commit],
        },
      ),
    );
    final after = ReaMicroGitHubProtocol.oid(commit['sha']?.toString() ?? '');
    final response = await _send(
      'POST',
      '/graphql',
      body: <String, Object?>{
        'query':
            'mutation ReaMicroSyncPublish(\$input: UpdateRefsInput!) '
            '{ updateRefs(input: \$input) { clientMutationId } }',
        'variables': <String, Object?>{
          'input': <String, Object?>{
            'repositoryId': head.nodeId,
            'refUpdates': <Object?>[
              <String, Object?>{
                'name': 'refs/heads/${head.branch}',
                'beforeOid': head.commit,
                'afterOid': after,
                'force': false,
              },
            ],
            'clientMutationId': after,
          },
        },
      },
    );
    final result = _json(response);
    final errors = result['errors'];
    if (errors is List<Object?> && errors.isNotEmpty) {
      final messages = <String>[
        for (final item in errors)
          if (item is Map<Object?, Object?>)
            '${item['type'] ?? ''} ${item['message'] ?? ''}',
      ].join(' ');
      if (messages.contains('STALE_DATA')) {
        throw const ReaMicroS3ConflictException('云端分支已被其他设备更新');
      }
      if (messages.toLowerCase().contains('rate limit')) {
        throw const ReaMicroS3Exception('GitHub 请求频率受限，请稍后再同步');
      }
      final latest = await _head();
      if (latest.commit != head.commit) {
        throw const ReaMicroS3ConflictException('云端分支已被其他设备更新');
      }
      throw const ReaMicroS3Exception(
        'GitHub 无法更新同步分支，请检查 Token 写入权限与分支保护规则',
      );
    }
    final data = _asMap(result['data']);
    final update = _asMap(data['updateRefs']);
    if (update['clientMutationId']?.toString() != after) {
      throw const ReaMicroS3Exception('GitHub 同步提交确认不一致');
    }
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
  }) async {
    final request = http.Request(
      method,
      Uri.parse('${ReaMicroGitHubProtocol.api}$path'),
    )..headers.addAll(<String, String>{
      'authorization': 'Bearer $token',
      'accept': 'application/vnd.github+json',
      'x-github-api-version': '2022-11-28',
      'user-agent': 'spectacular-reader',
    });
    if (body != null) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }
    try {
      final streamed = await _http.send(request).timeout(_timeout);
      return await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ReaMicroS3Exception('连接 GitHub 超时，请检查网络');
    } on SocketException catch (error) {
      throw ReaMicroS3Exception('连接 GitHub 失败：${error.message}');
    } on http.ClientException catch (error) {
      throw ReaMicroS3Exception('连接 GitHub 失败：${error.message}');
    }
  }

  Map<String, Object?> _json(http.Response response) {
    if (response.statusCode == 412 || response.statusCode == 409) {
      throw const ReaMicroS3ConflictException('云端对象已被其他设备修改');
    }
    if (response.statusCode == 429) {
      throw const ReaMicroS3Exception('GitHub 请求频率受限，请稍后再同步');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final text = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
      final suffix = text.isEmpty
          ? ''
          : '：${text.length > 200 ? '${text.substring(0, 200)}…' : text}';
      throw ReaMicroS3Exception('GitHub 请求失败：HTTP ${response.statusCode}$suffix');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
    if (decoded is! Map<String, Object?>) {
      throw const ReaMicroS3Exception('GitHub 返回了无法识别的响应');
    }
    return decoded;
  }

  static Map<String, Object?> _asMap(Object? value) =>
      value is Map<String, Object?> ? value : const <String, Object?>{};

  static int _asInt(Object? value) => switch (value) {
    final int number => number,
    final num number => number.toInt(),
    final String text => int.tryParse(text) ?? 0,
    _ => 0,
  };
}

class _GitHubHead {
  const _GitHubHead({
    required this.nodeId,
    required this.branch,
    required this.commit,
    required this.tree,
  });

  final String nodeId;
  final String branch;
  final String commit;
  final String tree;
}

class _GitHubObjectInfo {
  const _GitHubObjectInfo({required this.sha, required this.size});

  final String sha;
  final int size;
}
