import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import '../diagnostics/reader_log.dart';
import 'rea_micro_lan.dart';
import 'rea_micro_lan_rsa.dart';
import 'rea_micro_models.dart';

/// 一台正在申请局域网授权登录的设备。
class ReaMicroLanLoginRequest {
  /// 创建待授权请求。
  const ReaMicroLanLoginRequest({
    required this.id,
    required this.deviceModel,
    required this.receivedAt,
  });

  /// 本次请求的稳定标识。
  final String id;

  /// 请求方提交的设备型号。
  final String deviceModel;

  /// 收到请求的时间。
  final DateTime receivedAt;
}

/// 本机可向同账号设备提供的书籍快照。
class ReaMicroLanServedBook {
  /// 创建书籍快照。
  const ReaMicroLanServedBook({
    required this.uuid,
    required this.title,
    required this.author,
    required this.filePath,
    required this.cfi,
    required this.chapterName,
    required this.progress,
    required this.updatedAt,
    required this.finished,
    this.cloudId = 0,
    this.marks = const <ReaMicroLanMark>[],
  });

  /// 本地书库标识。
  final String uuid;

  /// 书名。
  final String title;

  /// 作者。
  final String author;

  /// 本地 EPUB 文件路径。
  final String filePath;

  /// 当前 EPUB CFI。
  final String cfi;

  /// 当前章节名。
  final String chapterName;

  /// 全书进度（0～1）。
  final double progress;

  /// 本机最后修改进度的时间（毫秒时间戳）。
  final int updatedAt;

  /// 是否已读完。
  final bool finished;

  /// 关联的阅微云端书籍标识；未关联为 0。
  final int cloudId;

  /// 本机已有的划线或想法。
  final List<ReaMicroLanMark> marks;
}

/// 局域网授权登录服务端。
///
/// 服务端注册 `_reamicro-login._tcp`，保留请求方连接，待用户批准后
/// 使用请求方提交的 X.509 公钥加密访问令牌，并以 `TOKEN|...` 回传。
/// 同一端口同时响应 `_reamicro-sync._tcp` 的清单与书籍文件请求。
class ReaMicroLanLoginServer {
  /// 创建服务端。
  ReaMicroLanLoginServer({
    this.requestTimeout = const Duration(minutes: 2),
    this.socketTimeout = const Duration(seconds: 15),
    this.discoveryEnabled = true,
  });

  /// 单次授权请求等待用户确认的最长时间。
  final Duration requestTimeout;

  /// 读取同步命令或文件数据的超时。
  final Duration socketTimeout;

  /// 是否发送 mDNS 广告；协议测试可关闭。
  final bool discoveryEnabled;

  ServerSocket? _server;
  _MdnsServiceAdvertiser? _advertiser;
  Future<List<ReaMicroLanServedBook>> Function()? _syncBooksProvider;
  Future<int> Function(String uuid, List<ReaMicroLanMark> marks)? _mergeMarks;
  final Map<String, _ServedArchive> _archiveCache = <String, _ServedArchive>{};
  final Map<String, _PendingLogin> _pending = <String, _PendingLogin>{};
  final List<ReaMicroLanLoginRequest> _requests = <ReaMicroLanLoginRequest>[];
  int? _userId;
  String _nickname = '';
  String _avatar = '';
  String _token = '';
  String _deviceId = '';
  String _deviceName = '';
  bool _running = false;
  String? _lastError;
  int _nextRequestId = 0;

  /// 当前待授权请求，按到达时间先后排列。
  List<ReaMicroLanLoginRequest> get requests =>
      List<ReaMicroLanLoginRequest>.unmodifiable(_requests);

  /// 服务端是否正在监听。
  bool get running => _running;

  /// 服务端监听端口；未启动时为空。
  int? get port => _server?.port;

  /// 最近一次启动或握手失败原因。
  String? get lastError => _lastError;

  /// 请求列表变化回调。
  ValueChanged<List<ReaMicroLanLoginRequest>>? onRequestsChanged;

  /// 启动授权服务；同一账号重复调用只更新令牌与资料。
  Future<void> start({
    required int userId,
    required String nickname,
    required String avatar,
    required String token,
    required String deviceId,
    String? deviceName,
    Future<List<ReaMicroLanServedBook>> Function()? syncBooks,
    Future<int> Function(String uuid, List<ReaMicroLanMark> marks)? mergeMarks,
  }) async {
    if (userId <= 0) {
      throw const FormatException('局域网授权服务需要有效的阅微账号');
    }
    if (token.trim().isEmpty) {
      throw const FormatException('局域网授权服务需要当前访问令牌');
    }
    if (_running && _userId == userId) {
      _token = token;
      _nickname = _clip(nickname.trim(), 48);
      _avatar = _clip(avatar.trim(), 200);
      return;
    }
    await stop();
    _userId = userId;
    _nickname = _clip(nickname.trim(), 48);
    _avatar = _clip(avatar.trim(), 200);
    _token = token;
    _deviceId = _safeLabel(deviceId, 'windows');
    _deviceName = _clip(
      (deviceName?.trim().isNotEmpty == true
              ? deviceName!.trim()
              : Platform.isWindows
              ? 'Windows 电脑'
              : 'Spectacular')
          .replaceAll(RegExp(r'[\r\n|]'), ' '),
      48,
    );
    _syncBooksProvider = syncBooks;
    _mergeMarks = mergeMarks;
    _lastError = null;
    try {
      final server = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        0,
        shared: false,
      );
      _server = server;
      _running = true;
      unawaited(_acceptLoop(server));
      if (discoveryEnabled) {
        await _startAdvertisement();
      }
      unawaited(
        ReaderLog.instance.log(
          'reamicro_lan_login_server',
          fields: <String, Object?>{
            'phase': 'started',
            'port': server.port,
            'userId': userId,
            'discovery': discoveryEnabled,
          },
        ),
      );
    } catch (error) {
      _lastError = '无法启动局域网授权服务：$error';
      await stop();
      rethrow;
    }
  }

  /// 更新当前令牌，不重建监听端口。
  void updateToken(String token) {
    if (token.trim().isNotEmpty) _token = token;
  }

  /// 更新同账号设备可读取的本地书籍快照。
  void updateSyncBooks(
    Future<List<ReaMicroLanServedBook>> Function()? provider,
  ) {
    _syncBooksProvider = provider;
  }

  /// 暂停 mDNS 广播，保留授权 TCP 监听。
  Future<void> pauseAdvertisement() async {
    final advertiser = _advertiser;
    _advertiser = null;
    if (advertiser != null) await advertiser.stop();
  }

  /// 恢复 mDNS 广播。
  Future<void> resumeAdvertisement() async {
    if (!_running || !discoveryEnabled) return;
    await _startAdvertisement();
  }

  /// 批准指定请求。
  Future<void> approve(String requestId) async {
    final pending = _pending.remove(requestId);
    if (pending == null) {
      throw const FormatException('该登录申请已失效');
    }
    _removeRequest(requestId);
    pending.timeout?.cancel();
    try {
      final encrypted = ReaMicroLanRsa.encryptToken(_token, pending.publicKey);
      pending.socket.write('TOKEN|$encrypted\n');
      await pending.socket.flush();
      unawaited(
        ReaderLog.instance.log(
          'reamicro_lan_login_server',
          fields: <String, Object?>{
            'phase': 'approved',
            'model': pending.deviceModel,
          },
        ),
      );
    } finally {
      await _closeSocket(pending.socket);
    }
  }

  /// 拒绝指定请求。
  Future<void> reject(String requestId) async {
    final pending = _pending.remove(requestId);
    if (pending == null) return;
    _removeRequest(requestId);
    pending.timeout?.cancel();
    try {
      pending.socket.write('REJECT\n');
      await pending.socket.flush();
      unawaited(
        ReaderLog.instance.log(
          'reamicro_lan_login_server',
          fields: <String, Object?>{
            'phase': 'rejected',
            'model': pending.deviceModel,
          },
        ),
      );
    } finally {
      await _closeSocket(pending.socket);
    }
  }

  /// 停止监听并关闭所有待授权连接。
  Future<void> stop() async {
    _running = false;
    await pauseAdvertisement();
    final server = _server;
    _server = null;
    if (server != null) await server.close();
    for (final pending in _pending.values) {
      pending.timeout?.cancel();
      await _closeSocket(pending.socket);
    }
    _pending.clear();
    final changed = _requests.isNotEmpty;
    _requests.clear();
    _userId = null;
    _token = '';
    _syncBooksProvider = null;
    _archiveCache.clear();
    if (changed) onRequestsChanged?.call(requests);
  }

  Future<void> _startAdvertisement() async {
    if (_advertiser != null) return;
    final userId = _userId;
    if (userId == null) return;
    final advertiser = _MdnsServiceAdvertiser(
      hostName: 'spectacular-$_deviceId.local',
      services: <_MdnsAdvertisedService>[
        _MdnsAdvertisedService(
          instanceName: 'ReaMicro-$userId',
          serviceType: '_reamicro-login._tcp.local',
          port: port!,
          txt: <String, String>{
            'userId': '$userId',
            'nickname': _nickname,
            'avatar': _avatar,
          },
        ),
        _MdnsAdvertisedService(
          instanceName: reaMicroSyncServiceName(userId, _deviceId, _deviceName),
          serviceType: '_reamicro-sync._tcp.local',
          port: port!,
          txt: <String, String>{
            'userId': '$userId',
            'deviceId': _deviceId,
            'nickname': reaMicroTxtName(_deviceName),
            'device': reaMicroTxtName(_deviceName),
          },
        ),
      ],
    );
    _advertiser = advertiser;
    try {
      await advertiser.start();
      _lastError = null;
    } catch (error) {
      _advertiser = null;
      await advertiser.stop();
      _lastError = '局域网授权服务已监听，但 mDNS 广播失败：$error';
    }
  }

  Future<void> _acceptLoop(ServerSocket server) async {
    try {
      await for (final socket in server) {
        if (!_running) {
          await _closeSocket(socket);
          break;
        }
        unawaited(_handleConnection(socket));
      }
    } catch (error) {
      if (!_running) return;
      _lastError = '局域网授权监听中断：$error';
      unawaited(
        ReaderLog.instance.log(
          'reamicro_lan_login_server',
          fields: <String, Object?>{'phase': 'accept_failed'},
        ),
      );
    }
  }

  Future<void> _handleConnection(Socket socket) async {
    final reader = _LanFrameReader(socket, timeout: socketTimeout);
    String? requestId;
    Timer? connectionTimeout;
    try {
      final line = await reader.readLine();
      if (line == null) return;
      final command = line.trim();
      if (command.isEmpty || command == 'BYE') return;
      if (command == 'PROFILE') {
        _sendProfile(socket);
        await socket.flush();
        return;
      }
      if (command == 'MANIFEST') {
        await _sendManifest(socket);
        return;
      }
      if (command.startsWith('GET_FILES ')) {
        await _handleFileRequest(socket, reader, command);
        return;
      }
      if (command.startsWith('PUSH_MARKS ')) {
        await _handlePushedMarks(socket, reader, command);
        return;
      }
      final request = _parseRequest(command);
      if (request == null) {
        socket.write('REJECT\n');
        await socket.flush();
        return;
      }
      requestId = _registerRequest(socket, request.$1, request.$2);
      connectionTimeout = Timer(requestTimeout, () {
        final pending = requestId == null ? null : _pending.remove(requestId);
        if (pending == null) return;
        _removeRequest(pending.requestId);
        unawaited(_closeSocket(pending.socket));
      });
      final pending = _pending[requestId];
      pending?.timeout = connectionTimeout;
      await reader.waitForClose(timeout: requestTimeout + socketTimeout);
    } on Object catch (error) {
      unawaited(
        ReaderLog.instance.log(
          'reamicro_lan_server',
          fields: <String, Object?>{
            'phase': 'connection_error',
            'error': error.toString(),
          },
        ),
      );
    } finally {
      if (requestId != null) {
        final pending = _pending.remove(requestId);
        if (pending != null) {
          _removeRequest(pending.requestId);
          pending.timeout?.cancel();
        }
      }
      connectionTimeout?.cancel();
      await reader.cancel();
      await _closeSocket(socket);
    }
  }

  Future<void> _handleFileRequest(
    Socket socket,
    _LanFrameReader reader,
    String command,
  ) async {
    final parts = command.split(RegExp(r'\s+'));
    final length = parts.length >= 2 ? int.tryParse(parts[1]) : null;
    if (length == null || length <= 0 || length > 2 * 1024 * 1024) {
      socket.write('ERR invalid request\n');
      await socket.flush();
      return;
    }
    final payload = await reader.readBytes(length);
    final request = jsonDecode(utf8.decode(payload, allowMalformed: true));
    if (request is! Map<String, Object?>) {
      socket.write('ERR invalid request\n');
      await socket.flush();
      return;
    }
    final uuid = request['uuid']?.toString() ?? '';
    final rawPaths = request['paths'];
    final paths = <String>[
      if (rawPaths is List<Object?>)
        for (final path in rawPaths)
          if (path is String) path,
    ];
    final provider = _syncBooksProvider;
    final books = provider == null
        ? const <ReaMicroLanServedBook>[]
        : await provider();
    ReaMicroLanServedBook? book;
    for (final item in books) {
      if (item.uuid == uuid) {
        book = item;
        break;
      }
    }
    if (book == null) {
      socket.write('ERR unknown book\n');
      await socket.flush();
      return;
    }
    final archive = await _archiveFor(book);
    if (archive == null) {
      socket.write('ERR book unavailable\n');
      await socket.flush();
      return;
    }
    final builder = BytesBuilder(copy: false);
    var count = 0;
    final contents = <List<int>>[];
    var totalBytes = 0;
    for (final path in paths) {
      if (!_isSafeServedPath(path)) continue;
      final data = archive.files[path];
      if (data == null) continue;
      final pathBytes = utf8.encode(path);
      contents.add(<int>[
        (pathBytes.length >> 24) & 0xff,
        (pathBytes.length >> 16) & 0xff,
        (pathBytes.length >> 8) & 0xff,
        pathBytes.length & 0xff,
        ...pathBytes,
        (data.length >> 24) & 0xff,
        (data.length >> 16) & 0xff,
        (data.length >> 8) & 0xff,
        data.length & 0xff,
        ...data,
      ]);
      totalBytes += data.length;
      count++;
      if (totalBytes > 512 * 1024 * 1024) {
        socket.write('ERR files too large\n');
        await socket.flush();
        return;
      }
    }
    builder.add(<int>[
      (count >> 24) & 0xff,
      (count >> 16) & 0xff,
      (count >> 8) & 0xff,
      count & 0xff,
    ]);
    for (final item in contents) {
      builder.add(item);
    }
    final filesPayload = builder.takeBytes();
    socket.write('FILES ${filesPayload.length}\n');
    socket.add(filesPayload);
    await socket.flush();
    unawaited(
      ReaderLog.instance.log(
        'reamicro_lan_server',
        fields: <String, Object?>{
          'phase': 'files',
          'uuid': uuid,
          'requested': paths.length,
          'served': count,
          'bytes': filesPayload.length,
        },
      ),
    );
  }

  /// 接收另一台设备回传的标注并合并到本机同一本书。
  Future<void> _handlePushedMarks(
    Socket socket,
    _LanFrameReader reader,
    String command,
  ) async {
    final parts = command.split(RegExp(r'\s+'));
    final length = parts.length >= 2 ? int.tryParse(parts[1]) : null;
    if (length == null || length <= 0 || length > 4 * 1024 * 1024) {
      socket.write('ERR invalid request\n');
      await socket.flush();
      return;
    }
    final payload = await reader.readBytes(length);
    final decoded = jsonDecode(utf8.decode(payload, allowMalformed: true));
    if (decoded is! Map<String, Object?>) {
      socket.write('ERR invalid request\n');
      await socket.flush();
      return;
    }
    final uuid = decoded['uuid']?.toString().trim() ?? '';
    final rawMarks = decoded['marks'];
    final marks = <ReaMicroLanMark>[
      if (rawMarks is List<Object?>)
        for (final item in rawMarks)
          if (item is Map<String, Object?>) ReaMicroLanMark.fromJson(item),
    ];
    final merger = _mergeMarks;
    if (uuid.isEmpty || merger == null) {
      socket.write('ERR unavailable\n');
      await socket.flush();
      return;
    }
    var merged = 0;
    try {
      merged = await merger(uuid, marks);
    } catch (error) {
      unawaited(
        ReaderLog.instance.log(
          'reamicro_lan_server',
          fields: <String, Object?>{
            'phase': 'marks_failed',
            'uuid': uuid,
            'error': error.toString(),
          },
        ),
      );
      socket.write('ERR marks failed\n');
      await socket.flush();
      return;
    }
    socket.write('OK $merged\n');
    await socket.flush();
    unawaited(
      ReaderLog.instance.log(
        'reamicro_lan_server',
        fields: <String, Object?>{
          'phase': 'marks',
          'uuid': uuid,
          'received': marks.length,
          'merged': merged,
        },
      ),
    );
  }

  Future<void> _sendManifest(Socket socket) async {
    final provider = _syncBooksProvider;
    final books = provider == null
        ? const <ReaMicroLanServedBook>[]
        : await provider();
    final entries = <Map<String, Object?>>[];
    for (final book in books) {
      if (book.uuid.trim().isEmpty) continue;
      final archive = await _archiveFor(book);
      entries.add(<String, Object?>{
        'uuid': book.uuid,
        'progressUpdatedAt': book.updatedAt,
        'book': <String, Object?>{
          'title': book.title,
          'author': book.author,
          'cloudId': book.cloudId,
          'epubcfi': book.cfi,
          'chapter': book.chapterName,
          'progress': book.progress,
          'finished': book.finished,
        },
        'files': <Map<String, Object?>>[
          if (archive != null)
            for (final file in archive.manifestFiles) file,
        ],
        'marks': <Map<String, Object?>>[
          for (final mark in book.marks)
            if (mark.usable) mark.toJson(),
        ],
      });
    }
    final payload = utf8.encode(
      jsonEncode(<String, Object?>{
        'userId': _userId,
        'deviceId': _deviceId,
        'generatedAt': DateTime.now().millisecondsSinceEpoch,
        'books': entries,
      }),
    );
    socket.write('MANIFEST ${payload.length}\n');
    socket.add(payload);
    await socket.flush();
    unawaited(
      ReaderLog.instance.log(
        'reamicro_lan_server',
        fields: <String, Object?>{
          'phase': 'manifest',
          'books': entries.length,
          'bytes': payload.length,
        },
      ),
    );
  }

  Future<_ServedArchive?> _archiveFor(ReaMicroLanServedBook book) async {
    final path = book.filePath.trim();
    if (path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final stat = await file.stat();
    final signature = '${stat.modified.millisecondsSinceEpoch}:${stat.size}';
    final cached = _archiveCache[path];
    if (cached != null && cached.signature == signature) return cached;
    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final files = <String, Uint8List>{};
      final manifestFiles = <Map<String, Object?>>[];
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        final name = entry.name.replaceAll('\\', '/');
        if (!_isSafeServedPath(name)) continue;
        final data = entry.content;
        files[name] = data;
        manifestFiles.add(<String, Object?>{
          'relativePath': name,
          'size': data.length,
          'md5': md5.convert(data).toString(),
          'mtime': stat.modified.millisecondsSinceEpoch,
        });
      }
      final result = _ServedArchive(
        signature: signature,
        files: files,
        manifestFiles: manifestFiles,
      );
      if (_archiveCache.length >= 12) _archiveCache.clear();
      _archiveCache[path] = result;
      return result;
    } on Object catch (error) {
      unawaited(
        ReaderLog.instance.log(
          'reamicro_lan_server',
          fields: <String, Object?>{
            'phase': 'archive_error',
            'error': error.toString(),
          },
        ),
      );
      return null;
    }
  }

  (String, RSAPublicKey)? _parseRequest(String line) {
    final parts = line.split('|');
    if (parts.length != 3 || parts.first != 'REQUEST') return null;
    final model = _clip(parts[1].trim(), 80);
    if (model.isEmpty) return null;
    try {
      final publicKey = ReaMicroLanRsa.decodePublicKey(parts[2].trim());
      return (model, publicKey);
    } on Object {
      return null;
    }
  }

  String _registerRequest(
    Socket socket,
    String deviceModel,
    RSAPublicKey publicKey,
  ) {
    _nextRequestId += 1;
    final id =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-'
        '$_nextRequestId';
    final request = ReaMicroLanLoginRequest(
      id: id,
      deviceModel: deviceModel,
      receivedAt: DateTime.now(),
    );
    final pending = _PendingLogin(
      requestId: id,
      deviceModel: deviceModel,
      socket: socket,
      publicKey: publicKey,
    );
    _pending[id] = pending;
    _requests
      ..removeWhere((item) => item.id == id)
      ..add(request);
    onRequestsChanged?.call(requests);
    unawaited(
      ReaderLog.instance.log(
        'reamicro_lan_login_server',
        fields: <String, Object?>{'phase': 'request', 'model': deviceModel},
      ),
    );
    return id;
  }

  void _sendProfile(Socket socket) {
    final payload = jsonEncode(<String, Object?>{
      'userId': _userId,
      'nickname': _nickname,
      'avatarUrl': _avatar,
    });
    socket.write('PROFILE|$payload\n');
    unawaited(socket.flush().whenComplete(() => _closeSocket(socket)));
  }

  void _removeRequest(String requestId) {
    final before = _requests.length;
    _requests.removeWhere((item) => item.id == requestId);
    if (_requests.length != before) onRequestsChanged?.call(requests);
  }

  static String _clip(String value, int maxCharacters) {
    if (value.length <= maxCharacters) return value;
    return value.substring(0, maxCharacters);
  }

  static String _safeLabel(String value, String fallback) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9-]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return normalized.isEmpty ? fallback : normalized;
  }

  static Future<void> _closeSocket(Socket socket) async {
    try {
      await socket.flush();
    } on Object {
      // 对端可能已经关闭连接。
    }
    try {
      await socket.close();
    } on Object {
      // 同上。
    }
    socket.destroy();
  }
}

/// 阅微从服务实例名读取设备身份和展示名，TXT 仅作为后备。
@visibleForTesting
String reaMicroSyncServiceName(int userId, String deviceId, String name) {
  final id = deviceId.replaceAll(RegExp('[^A-Za-z0-9]'), '');
  final suffix = id.length <= 6 ? id : id.substring(id.length - 6);
  final label = name
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp('[^A-Za-z0-9_+]'), '');
  final visible = label.isEmpty ? 'ReaMicroExtend' : label;
  final prefix = 'ReaMicroSync-$userId-${suffix.isEmpty ? 'device' : suffix}-';
  final room = (63 - prefix.length).clamp(0, 28);
  return '$prefix${visible.substring(0, visible.length.clamp(0, room))}';
}

/// 中文设备名沿用阅微的 Base64 TXT 编码。
@visibleForTesting
String reaMicroTxtName(String name) =>
    name.codeUnits.every((value) => value >= 32 && value <= 126)
    ? name
    : 'b64:${base64Encode(utf8.encode(name))}';

class _PendingLogin {
  _PendingLogin({
    required this.requestId,
    required this.deviceModel,
    required this.socket,
    required this.publicKey,
  });

  final String requestId;
  final String deviceModel;
  final Socket socket;
  final RSAPublicKey publicKey;
  Timer? timeout;
}

class _ServedArchive {
  const _ServedArchive({
    required this.signature,
    required this.files,
    required this.manifestFiles,
  });

  final String signature;
  final Map<String, Uint8List> files;
  final List<Map<String, Object?>> manifestFiles;
}

bool _isSafeServedPath(String value) {
  final path = value.trim().replaceAll('\\', '/');
  if (path.isEmpty || path.startsWith('/') || path.endsWith('/')) return false;
  final segments = path.split('/');
  return segments.every(
    (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
  );
}

/// 按换行命令头和长度字段读取局域网同步协议数据。
class _LanFrameReader {
  _LanFrameReader(this.socket, {required this.timeout})
    : _iterator = StreamIterator<List<int>>(socket.cast<List<int>>());

  final Socket socket;
  final Duration timeout;
  final StreamIterator<List<int>> _iterator;
  final List<int> _buffer = <int>[];
  bool _closed = false;

  Future<String?> readLine() async {
    while (true) {
      final newline = _buffer.indexOf(10);
      if (newline >= 0) {
        final bytes = _buffer.sublist(0, newline);
        _buffer.removeRange(0, newline + 1);
        if (bytes.isNotEmpty && bytes.last == 13) bytes.removeLast();
        return utf8.decode(bytes, allowMalformed: true);
      }
      if (!await _fill()) {
        if (_buffer.isEmpty) return null;
        final bytes = List<int>.of(_buffer);
        _buffer.clear();
        return utf8.decode(bytes, allowMalformed: true);
      }
    }
  }

  Future<Uint8List> readBytes(int length) async {
    if (length <= 0) return Uint8List(0);
    while (_buffer.length < length) {
      if (!await _fill()) {
        throw const FormatException('同步请求数据不完整');
      }
    }
    final value = Uint8List.fromList(_buffer.sublist(0, length));
    _buffer.removeRange(0, length);
    return value;
  }

  Future<void> waitForClose({Duration? timeout}) async {
    while (await _fill(timeout: timeout)) {
      _buffer.clear();
    }
  }

  Future<bool> _fill({Duration? timeout}) async {
    if (_closed) return false;
    final hasNext = await _iterator.moveNext().timeout(
      timeout ?? this.timeout,
      onTimeout: () => false,
    );
    if (!hasNext) {
      _closed = true;
      return false;
    }
    _buffer.addAll(_iterator.current);
    return true;
  }

  Future<void> cancel() async {
    if (_closed) return;
    _closed = true;
    try {
      await _iterator.cancel();
    } on StateError {
      // 对端已断开时流迭代器可能已经结束。
    }
  }
}

class _MdnsAdvertisedService {
  const _MdnsAdvertisedService({
    required this.instanceName,
    required this.serviceType,
    required this.port,
    required this.txt,
  });

  final String instanceName;
  final String serviceType;
  final int port;
  final Map<String, String> txt;
}

class _MdnsServiceAdvertiser {
  _MdnsServiceAdvertiser({required this.hostName, required this.services});

  static const int _port = 5353;
  static final InternetAddress _group = InternetAddress('224.0.0.251');

  final String hostName;
  final List<_MdnsAdvertisedService> services;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  List<NetworkInterface> _interfaces = const <NetworkInterface>[];
  List<InternetAddress> _addresses = const <InternetAddress>[];
  Timer? _announceTimer;

  Future<void> start() async {
    final candidates = await NetworkInterface.list(
      includeLinkLocal: true,
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final reachable = await selectReachableMulticastInterfaces(
      candidates.where((interface) => interface.addresses.isNotEmpty),
      _canSendMulticast,
    );
    final preferred =
        reachable
            .where(
              (interface) => shouldAdvertiseLanInterface(
                interface.name,
                interface.addresses,
              ),
            )
            .toList(growable: false)
          ..sort(
            (left, right) =>
                _interfacePriority(left.name)
                    .compareTo(_interfacePriority(right.name)),
          );
    final interfaces = preferred.isEmpty ? reachable : preferred;
    if (interfaces.isEmpty) {
      throw const SocketException('没有可用于 mDNS 广播的网络接口');
    }
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      _port,
      reuseAddress: true,
    );
    _socket = socket;
    socket.multicastLoopback = true;
    socket.multicastHops = 255;
    final joined = <NetworkInterface>[];
    for (final interface in interfaces) {
      try {
        socket.joinMulticast(_group, interface);
        joined.add(interface);
      } on Object {
        // 虚拟网卡或 VPN 可能拒绝加入组播组。
      }
    }
    _interfaces = joined.isEmpty ? interfaces : joined;
    _addresses = <InternetAddress>[
      for (final interface in _interfaces)
        for (final address in interface.addresses)
          if (address.type == InternetAddressType.IPv4 &&
              !address.isLoopback &&
              !address.isLinkLocal &&
              isPrivateLanIpv4(address))
            address,
    ];
    if (_addresses.isEmpty) {
      _addresses = <InternetAddress>[
        for (final interface in _interfaces)
          for (final address in interface.addresses)
            if (address.type == InternetAddressType.IPv4 && !address.isLoopback)
              address,
      ];
    }
    _subscription = socket.listen(
      (event) {
        if (event == RawSocketEvent.read) _handleDatagram();
      },
      onError: (Object _) {
        // 单块网卡的 ICMP 错误不应终止整个广播服务。
      },
    );
    _sendAnnouncement();
    _announceTimer = Timer(const Duration(seconds: 1), _sendAnnouncement);
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _announceTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
    _interfaces = const <NetworkInterface>[];
    _addresses = const <InternetAddress>[];
  }

  void _handleDatagram() {
    final datagram = _socket?.receive();
    if (datagram == null || datagram.data.length < 12) return;
    final query = _parseQuery(datagram.data);
    if (query == null) return;
    if (!query.service && !query.instance && !query.host) {
      return;
    }
    final response = _buildResponse();
    if (query.unicastResponse) {
      _socket?.send(response, datagram.address, datagram.port);
      return;
    }
    _sendMulticast(response);
  }

  void _sendAnnouncement() {
    if (_socket == null) return;
    _sendMulticast(_buildResponse());
  }

  void _sendMulticast(Uint8List payload) {
    final socket = _socket;
    if (socket == null) return;
    for (final interface in _interfaces) {
      final address = _preferredAddress(interface);
      if (address == null) continue;
      try {
        socket.setRawOption(
          RawSocketOption(
            RawSocketOption.levelIPv4,
            RawSocketOption.IPv4MulticastInterface,
            address.rawAddress,
          ),
        );
        socket.send(payload, _group, _port);
      } on Object {
        // 继续尝试其余网卡。
      }
    }
  }

  _MdnsQuery? _parseQuery(Uint8List data) {
    if ((data[2] & 0x80) != 0) return null;
    final questionCount = (data[4] << 8) | data[5];
    if (questionCount <= 0) return null;
    var offset = 12;
    var service = false;
    var instance = false;
    var host = false;
    var unicast = false;
    final serviceNames = <String>{
      for (final service in services) service.serviceType.toLowerCase(),
    };
    final instanceNames = <String>{
      for (final service in services)
        '${service.instanceName}.${service.serviceType}'.toLowerCase(),
    };
    final hostLower = hostName.toLowerCase();
    for (var index = 0; index < questionCount; index++) {
      final name = _readDnsName(data, offset);
      if (name == null) return null;
      offset = name.nextOffset;
      if (offset + 4 > data.length) return null;
      final type = (data[offset] << 8) | data[offset + 1];
      final qclass = (data[offset + 2] << 8) | data[offset + 3];
      offset += 4;
      final normalized = name.value.toLowerCase();
      final isService =
          serviceNames.contains(normalized) && (type == 12 || type == 255);
      final isInstance =
          instanceNames.contains(normalized) &&
          (type == 33 || type == 16 || type == 255);
      final isHost = normalized == hostLower && (type == 1 || type == 255);
      if (!isService && !isInstance && !isHost) continue;
      service = service || isService;
      instance = instance || isInstance;
      host = host || isHost;
      if ((qclass & 0x8000) != 0) unicast = true;
    }
    if (!service && !instance && !host) return null;
    return _MdnsQuery(
      service: service,
      instance: instance,
      host: host,
      unicastResponse: unicast,
    );
  }

  Uint8List _buildResponse() {
    return _buildReaMicroMdnsResponse(
      hostName: hostName,
      services: services,
      addresses: _addresses,
    );
  }

  InternetAddress? _preferredAddress(NetworkInterface interface) {
    for (final address in interface.addresses) {
      if (address.type == InternetAddressType.IPv4 &&
          !address.isLinkLocal &&
          !address.isLoopback) {
        return address;
      }
    }
    for (final address in interface.addresses) {
      if (address.type == InternetAddressType.IPv4) return address;
    }
    return null;
  }

  Future<bool> _canSendMulticast(NetworkInterface interface) async {
    RawDatagramSocket? socket;
    try {
      final address = _preferredAddress(interface);
      if (address == null) return false;
      socket = await RawDatagramSocket.bind(address, 0);
      socket.setRawOption(
        RawSocketOption(
          RawSocketOption.levelIPv4,
          RawSocketOption.IPv4MulticastInterface,
          address.rawAddress,
        ),
      );
      final sent = socket.send(<int>[0, 0, 0, 0], _group, _port);
      return sent > 0;
    } on Object {
      return false;
    } finally {
      socket?.close();
    }
  }

  int _interfacePriority(String name) {
    final normalized = name.toLowerCase();
    if (normalized.contains('wlan') ||
        normalized.contains('wi-fi') ||
        normalized.contains('wifi')) {
      return 0;
    }
    if (normalized.contains('ethernet') ||
        normalized.contains('以太网') ||
        normalized.contains('本地连接')) {
      return 1;
    }
    return 2;
  }
}

/// 判断网卡是否适合对外广播局域网授权登录地址。
///
/// Windows 同时启用 Radmin、Tailscale、WSL 等虚拟网卡时，同一份 mDNS
/// 应答会携带多个 A 记录。Android 客户端可能选中 VPN 地址，导致申请登录
/// 的 TCP 连接一直停在 SYN-SENT。这里优先只广播真实局域网网卡。
@visibleForTesting
bool shouldAdvertiseLanInterface(String name, List<InternetAddress> addresses) {
  final normalized = name.toLowerCase();
  final virtual = RegExp(
    r'vpn|radmin|tailscale|zerotier|wireguard|tap|tun|virtual|hyper-v|wsl|'
    r'docker|vmware|virtualbox|loopback',
  );
  if (virtual.hasMatch(normalized)) return false;
  return addresses.any(
    (address) =>
        address.type == InternetAddressType.IPv4 &&
        !address.isLoopback &&
        !address.isLinkLocal &&
        isPrivateLanIpv4(address),
  );
}

/// 判断 IPv4 地址是否属于常见局域网私有地址段。
@visibleForTesting
bool isPrivateLanIpv4(InternetAddress address) {
  if (address.type != InternetAddressType.IPv4) return false;
  final bytes = address.rawAddress;
  if (bytes.length != 4) return false;
  final first = bytes[0];
  final second = bytes[1];
  return first == 10 ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 168);
}

class _MdnsQuery {
  const _MdnsQuery({
    required this.service,
    required this.instance,
    required this.host,
    required this.unicastResponse,
  });

  final bool service;
  final bool instance;
  final bool host;
  final bool unicastResponse;
}

class _DnsName {
  const _DnsName(this.value, this.nextOffset);

  final String value;
  final int nextOffset;
}

/// 构造阅微局域网授权登录的 mDNS 应答包。
///
/// 独立成顶层函数，便于回归测试 SRV 端口和 TXT 字段。阅微客户端会丢弃
/// SRV 端口小于等于 0 的记录，因此这里必须写入实际 TCP 监听端口。
@visibleForTesting
Uint8List buildReaMicroLoginMdnsResponse({
  required String instanceName,
  required String hostName,
  required int port,
  required Map<String, String> txt,
  required List<InternetAddress> addresses,
}) => _buildReaMicroMdnsResponse(
  hostName: hostName,
  addresses: addresses,
  services: <_MdnsAdvertisedService>[
    _MdnsAdvertisedService(
      instanceName: instanceName,
      serviceType: '_reamicro-login._tcp.local',
      port: port,
      txt: txt,
    ),
  ],
);

Uint8List _buildReaMicroMdnsResponse({
  required String hostName,
  required List<_MdnsAdvertisedService> services,
  required List<InternetAddress> addresses,
}) {
  const ttl = 120;
  const ptrTtl = 4500;

  List<int> record(
    String name, {
    required int type,
    required int recordTtl,
    required List<int> data,
    bool cacheFlush = false,
  }) {
    return <int>[
      ..._encodeName(name),
      (type >> 8) & 0xff,
      type & 0xff,
      cacheFlush ? 0x80 : 0,
      1,
      (recordTtl >> 24) & 0xff,
      (recordTtl >> 16) & 0xff,
      (recordTtl >> 8) & 0xff,
      recordTtl & 0xff,
      (data.length >> 8) & 0xff,
      data.length & 0xff,
      ...data,
    ];
  }

  final records = <List<int>>[];
  for (final service in services) {
    final instance = '${service.instanceName}.${service.serviceType}';
    final port = service.port;
    records
      ..add(
        record(
          service.serviceType,
          type: 12,
          recordTtl: ptrTtl,
          data: _encodeName(instance),
        ),
      )
      ..add(
        record(
          instance,
          type: 33,
          recordTtl: ttl,
          cacheFlush: true,
          data: <int>[
            0,
            0,
            0,
            0,
            (port >> 8) & 0xff,
            port & 0xff,
            ..._encodeName(hostName),
          ],
        ),
      )
      ..add(
        record(
          instance,
          type: 16,
          recordTtl: ttl,
          cacheFlush: true,
          data: <int>[
            for (final entry in service.txt.entries)
              if (utf8.encode('${entry.key}=${entry.value}').length <= 255) ...[
                utf8.encode('${entry.key}=${entry.value}').length,
                ...utf8.encode('${entry.key}=${entry.value}'),
              ],
          ],
        ),
      );
  }
  for (final address in addresses) {
    records.add(
      record(
        hostName,
        type: 1,
        recordTtl: ttl,
        cacheFlush: true,
        data: address.rawAddress,
      ),
    );
  }
  return Uint8List.fromList(<int>[
    0,
    0,
    0x84,
    0,
    0,
    0,
    (records.length >> 8) & 0xff,
    records.length & 0xff,
    0,
    0,
    0,
    0,
    for (final item in records) ...item,
  ]);
}

_DnsName? _readDnsName(Uint8List data, int offset) {
  final parts = <String>[];
  var cursor = offset;
  var nextOffset = offset;
  var jumped = false;
  final visited = <int>{};
  while (cursor < data.length) {
    final length = data[cursor];
    if (length == 0) {
      if (!jumped) nextOffset = cursor + 1;
      return _DnsName(parts.join('.'), nextOffset);
    }
    if ((length & 0xc0) == 0xc0) {
      if (cursor + 1 >= data.length) return null;
      final pointer = ((length & 0x3f) << 8) | data[cursor + 1];
      if (!jumped) nextOffset = cursor + 2;
      if (pointer >= data.length || !visited.add(pointer)) return null;
      cursor = pointer;
      jumped = true;
      continue;
    }
    cursor += 1;
    if (length > 63 || cursor + length > data.length) return null;
    parts.add(utf8.decode(data.sublist(cursor, cursor + length)));
    cursor += length;
    if (!jumped) nextOffset = cursor;
  }
  return null;
}

List<int> _encodeName(String name) {
  final result = <int>[];
  for (final label in name.split('.')) {
    if (label.isEmpty) continue;
    final bytes = utf8.encode(label);
    if (bytes.length > 63) {
      throw FormatException('mDNS 标签过长：$label');
    }
    result
      ..add(bytes.length)
      ..addAll(bytes);
  }
  result.add(0);
  return result;
}
