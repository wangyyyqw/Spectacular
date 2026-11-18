import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:multicast_dns/multicast_dns.dart';

import '../diagnostics/reader_log.dart';
import 'rea_micro_cbor.dart';
import 'rea_micro_lan_rsa.dart';
import 'rea_micro_models.dart';

/// 可用于局域网授权登录的阅微设备。
class ReaMicroLanLoginDevice {
  /// 创建设备。
  const ReaMicroLanLoginDevice({
    required this.host,
    required this.port,
    required this.userId,
    required this.nickname,
    required this.avatar,
  });

  /// 设备地址。
  final String host;

  /// 登录服务端口。
  final int port;

  /// 设备账号标识。
  final String userId;

  /// 账号昵称。
  final String nickname;

  /// 头像地址。
  final String avatar;

  /// 用于界面去重的稳定标识。
  String get key => '$userId|$host|$port';
}

/// 可用于同步阅读进度的同账号设备。
class ReaMicroLanSyncPeer {
  /// 创建同步设备。
  const ReaMicroLanSyncPeer({
    required this.host,
    required this.port,
    required this.userId,
    required this.deviceId,
    required this.nickname,
    required this.deviceName,
  });

  /// 设备地址。
  final String host;

  /// 同步服务端口。
  final int port;

  /// 同账号用户标识。
  final int userId;

  /// 对端设备标识。
  final String deviceId;

  /// 账号昵称。
  final String nickname;

  /// 设备名。
  final String deviceName;

  /// 用于界面去重的稳定标识。
  String get key => '$deviceId|$host|$port';
}

/// 阅微局域网服务客户端。
///
/// 实现局域网授权登录、同步清单读取和整本书文件下载。所有连接都有明确
/// 超时，服务发现结束后会立即停止 mDNS 客户端。
class ReaMicroLanClient {
  /// 创建客户端。
  ReaMicroLanClient({
    this.discoveryTimeout = const Duration(seconds: 4),
    this.socketTimeout = const Duration(seconds: 8),
    this.loginTimeout = const Duration(minutes: 2),
  });

  /// 等待 mDNS 返回记录的时间。
  final Duration discoveryTimeout;

  /// 单次局域网连接或读取的超时。
  final Duration socketTimeout;

  /// 等待另一台设备人工批准登录的最长时间。
  final Duration loginTimeout;

  /// 扫描局域网授权登录设备。
  Future<List<ReaMicroLanLoginDevice>> discoverLoginDevices({
    String? excludeUserId,
  }) async {
    final services = await _discoverServices('_reamicro-login._tcp');
    final devices = <String, ReaMicroLanLoginDevice>{};
    for (final service in services) {
      final userId = service.txt['userId']?.trim() ?? '';
      if (userId.isEmpty || userId == excludeUserId) continue;
      final device = ReaMicroLanLoginDevice(
        host: service.host,
        port: service.port,
        userId: userId,
        nickname: service.txt['nickname']?.trim() ?? '',
        avatar: service.txt['avatar']?.trim() ?? '',
      );
      devices[device.key] = device;
    }
    final result = devices.values.toList(growable: false);
    result.sort((left, right) => left.nickname.compareTo(right.nickname));
    unawaited(
      ReaderLog.instance.log(
        'reamicro_lan_login_discovery',
        fields: <String, Object?>{
          'found': result.length,
          'services': services.length,
        },
      ),
    );
    return result;
  }

  /// 扫描局域网同步设备。
  Future<List<ReaMicroLanSyncPeer>> discoverSyncPeers({
    String? excludeDeviceId,
  }) async {
    final services = await _discoverServices('_reamicro-sync._tcp');
    final peers = <String, ReaMicroLanSyncPeer>{};
    for (final service in services) {
      final rawUserId = int.tryParse(service.txt['userId']?.trim() ?? '');
      final deviceId = service.txt['deviceId']?.trim() ?? '';
      if (rawUserId == null || rawUserId <= 0) continue;
      if (deviceId.isEmpty || deviceId == excludeDeviceId) continue;
      final peer = ReaMicroLanSyncPeer(
        host: service.host,
        port: service.port,
        userId: rawUserId,
        deviceId: deviceId,
        nickname: service.txt['nickname']?.trim() ?? '',
        deviceName:
            service.txt['device']?.trim() ??
            service.txt['deviceName']?.trim() ??
            '',
      );
      peers[peer.key] = peer;
    }
    final result = peers.values.toList(growable: false);
    result.sort((left, right) => left.deviceName.compareTo(right.deviceName));
    unawaited(
      ReaderLog.instance.log(
        'reamicro_lan_sync_discovery',
        fields: <String, Object?>{
          'found': result.length,
          'services': services.length,
        },
      ),
    );
    return result;
  }

  /// 通过局域网设备完成授权登录，返回访问令牌。
  Future<String> login(
    ReaMicroLanLoginDevice device, {
    String? deviceModel,
  }) async {
    unawaited(
      ReaderLog.instance.log(
        'reamicro_lan_login',
        fields: <String, Object?>{
          'phase': 'request',
          'host': device.host,
          'port': device.port,
          'userId': device.userId,
        },
      ),
    );
    // 2048 位密钥生成耗时较长，放到后台 isolate 避免卡住阅读界面。
    final pair = await Isolate.run(ReaMicroLanRsa.generate);
    final publicKey = ReaMicroLanRsa.encodePublicKey(pair.publicKey);
    final model = _safeText(
      deviceModel?.trim().isNotEmpty == true
          ? deviceModel!.trim()
          : 'Spectacular-${Platform.operatingSystem}',
    );
    final socket = await _connect(device.host, device.port);
    final iterator = _lineIterator(socket);
    try {
      socket.write('REQUEST|$model|$publicKey\n');
      await socket.flush();
      for (var attempt = 0; attempt < 3; attempt++) {
        final line = await _nextLine(iterator, timeout: loginTimeout);
        if (line == 'REJECT') {
          throw const ReaMicroException('设备拒绝了本次局域网授权登录');
        }
        if (line.startsWith('TOKEN|')) {
          final encrypted = line.substring('TOKEN|'.length).trim();
          if (encrypted.isEmpty) {
            throw const ReaMicroException('设备返回的授权令牌为空');
          }
          final token = ReaMicroLanRsa.decryptToken(encrypted, pair.privateKey);
          if (token.isEmpty) {
            throw const ReaMicroException('无法解密设备返回的授权令牌');
          }
          unawaited(
            ReaderLog.instance.log(
              'reamicro_lan_login',
              fields: <String, Object?>{
                'phase': 'token',
                'host': device.host,
                'port': device.port,
                'userId': device.userId,
              },
            ),
          );
          return token;
        }
        // 兼容设备先发送 PROFILE 等附加信息，继续等待 TOKEN/REJECT。
        if (line.startsWith('PROFILE|') || line == 'PROFILE') continue;
        throw ReaMicroException('设备返回了无法识别的授权响应：$line');
      }
      throw const ReaMicroException('设备未返回授权令牌');
    } finally {
      await iterator.cancel();
      socket.destroy();
    }
  }

  /// 读取对端同步清单。
  Future<ReaMicroLanManifest> fetchManifest(ReaMicroLanSyncPeer peer) async {
    unawaited(
      ReaderLog.instance.log(
        'reamicro_lan_manifest',
        fields: <String, Object?>{
          'phase': 'request',
          'host': peer.host,
          'port': peer.port,
          'deviceId': peer.deviceId,
        },
      ),
    );
    final socket = await _connect(peer.host, peer.port);
    final reader = _SocketFrameReader(socket, timeout: socketTimeout);
    try {
      socket.write('MANIFEST\n');
      await socket.flush();
      final line = await reader.readLine();
      if (line == null) {
        throw const ReaMicroException('局域网设备未返回数据或连接已关闭');
      }
      final parts = line.trim().split(RegExp(r'\s+'));
      final command = parts.isEmpty ? '' : parts.first;
      if (command == 'ERR') {
        throw ReaMicroException('设备返回错误：${parts.skip(1).join(' ').trim()}');
      }
      if (command != 'MANIFEST' || parts.length < 2) {
        throw const ReaMicroException('设备返回了无法识别的同步清单');
      }
      final length = int.tryParse(parts[1]);
      if (length == null || length <= 0) {
        throw const ReaMicroException('同步清单长度不正确');
      }
      final payload = await reader.readBytes(length);
      final decoded = _decodeManifestPayload(payload);
      if (decoded is! Map<String, Object?>) {
        throw const ReaMicroException('同步清单格式不正确');
      }
      final manifest = ReaMicroLanManifest.fromJson(decoded);
      unawaited(
        ReaderLog.instance.log(
          'reamicro_lan_manifest',
          fields: <String, Object?>{
            'phase': 'ok',
            'host': peer.host,
            'port': peer.port,
            'bytes': payload.length,
            'books': manifest.books.length,
          },
        ),
      );
      return manifest;
    } on FormatException {
      unawaited(
        ReaderLog.instance.log(
          'reamicro_lan_manifest',
          fields: <String, Object?>{
            'phase': 'format_error',
            'host': peer.host,
            'port': peer.port,
          },
        ),
      );
      throw const ReaMicroException('同步清单不是有效的 JSON 或 CBOR');
    } finally {
      try {
        socket.write('BYE\n');
        await socket.flush();
      } catch (_) {
        // 对端可能已主动断开，不影响已经读取的清单。
      }
      await reader.cancel();
      socket.destroy();
    }
  }

  /// 从对端设备读取一本书的全部文件，并重建为 EPUB 字节。
  ///
  /// 阅微设备按解析后的目录保存书籍，`GET_FILES` 一次可读取多个相对路径。
  /// 这里一次请求全部路径，逐文件校验大小与 MD5，再按 EPUB 要求把 `mimetype`
  /// 作为第一个且不压缩的条目写入 ZIP。
  Future<Uint8List> downloadBookArchive(
    ReaMicroLanSyncPeer peer,
    ReaMicroLanBookProgress book,
  ) async {
    if (book.uuid.trim().isEmpty) {
      throw const ReaMicroException('待下载书籍缺少设备标识');
    }
    final sourceFiles = book.files
        .where((file) => _isSafeArchivePath(file.relativePath))
        .toList(growable: false);
    if (sourceFiles.isEmpty) {
      throw ReaMicroException('《${book.title}》没有可下载的书籍文件');
    }
    final socket = await _connect(peer.host, peer.port);
    final reader = _SocketFrameReader(socket, timeout: socketTimeout);
    final contents = <String, Uint8List>{};
    var downloadedBytes = 0;
    try {
      // 阅微服务端处理 GET_FILES 时会在 FILES 帧后额外写一帧
      // `ERR unknown command`。分批请求时下一批会先读到上一批残留的
      // 错误帧，因此这里一次请求全部文件，读完 FILES 后立即结束会话。
      final requestBytes = utf8.encode(
        jsonEncode(<String, Object?>{
          'uuid': book.uuid,
          'paths': <String>[for (final file in sourceFiles) file.relativePath],
        }),
      );
      socket.write('GET_FILES ${requestBytes.length}\n');
      socket.add(requestBytes);
      await socket.flush();

      final line = await reader.readLine();
      if (line == null) {
        throw const ReaMicroException('局域网设备未返回图书文件');
      }
      final parts = line.trim().split(RegExp(r'\s+'));
      final command = parts.isEmpty ? '' : parts.first;
      if (command == 'ERR') {
        throw ReaMicroException('设备返回错误：${parts.skip(1).join(' ').trim()}');
      }
      if (command != 'FILES' || parts.length < 2) {
        throw const ReaMicroException('设备返回了无法识别的图书文件');
      }
      final length = int.tryParse(parts[1]);
      if (length == null || length < 4 || length > 512 * 1024 * 1024) {
        throw const ReaMicroException('图书文件长度不正确');
      }
      final payload = await reader.readBytes(length);
      downloadedBytes += payload.length;
      contents.addAll(decodeReaMicroLanFilesPayload(payload));

      final expectedPaths = <String>{
        for (final file in sourceFiles)
          _normalizeArchivePath(file.relativePath),
      };
      for (final file in sourceFiles) {
        final path = _normalizeArchivePath(file.relativePath);
        final data = contents[path];
        if (data == null) {
          throw ReaMicroException('设备未返回文件：$path');
        }
        if (file.size > 0 && data.length != file.size) {
          throw ReaMicroException('文件大小不一致：$path');
        }
        final digest = file.md5.trim().toLowerCase();
        if (digest.isNotEmpty &&
            md5.convert(data).toString().toLowerCase() != digest) {
          throw ReaMicroException('文件校验失败：$path');
        }
      }
      contents.removeWhere((path, _) => !expectedPaths.contains(path));
      final archive = _buildEpubArchive(contents);
      unawaited(
        ReaderLog.instance.log(
          'reamicro_lan_book',
          fields: <String, Object?>{
            'phase': 'ok',
            'host': peer.host,
            'port': peer.port,
            'files': sourceFiles.length,
            'payloadBytes': downloadedBytes,
            'epubBytes': archive.length,
          },
        ),
      );
      return archive;
    } catch (error) {
      unawaited(
        ReaderLog.instance.log(
          'reamicro_lan_book',
          fields: <String, Object?>{
            'phase': 'error',
            'host': peer.host,
            'port': peer.port,
            'files': sourceFiles.length,
            'payloadBytes': downloadedBytes,
            'error': error.toString(),
          },
        ),
      );
      rethrow;
    } finally {
      try {
        socket.write('BYE\n');
        await socket.flush();
      } catch (_) {
        // 对端可能已主动断开，不影响已完整读取并校验的文件。
      }
      await reader.cancel();
      socket.destroy();
    }
  }

  Future<Socket> _connect(String host, int port) async {
    try {
      final socket = await Socket.connect(host, port, timeout: socketTimeout);
      socket.setOption(SocketOption.tcpNoDelay, true);
      return socket;
    } on SocketException catch (error) {
      throw ReaMicroException('无法连接局域网设备：${error.message}');
    } on TimeoutException {
      throw const ReaMicroException('连接局域网设备超时');
    }
  }

  StreamIterator<String> _lineIterator(Socket socket) => StreamIterator<String>(
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter()),
  );

  Future<String> _nextLine(
    StreamIterator<String> iterator, {
    Duration? timeout,
  }) async {
    final hasLine = await iterator.moveNext().timeout(
      timeout ?? socketTimeout,
      onTimeout: () => false,
    );
    if (!hasLine) {
      throw const ReaMicroException('局域网设备未返回数据或连接已关闭');
    }
    return iterator.current.trim();
  }

  Future<List<_DiscoveredService>> _discoverServices(String serviceType) async {
    await _acquireAndroidMulticastLock();
    _WindowsMdnsEnvironment? windows;
    final MDnsClient client;
    try {
      windows = await _prepareWindowsMdns();
      client = windows == null
          ? MDnsClient()
          : MDnsClient(rawDatagramSocketFactory: windows.bindDatagramSocket);
      await client.start(
        interfacesFactory: windows?.interfacesFactory,
        onError: (Object _) {
          // Windows 上不可达的虚拟网卡可能异步回报 ICMP 错误，不影响其他网卡。
        },
      );
    } on Object catch (error) {
      windows?.close();
      await _releaseAndroidMulticastLock();
      if (error is ReaMicroException) rethrow;
      throw ReaMicroException('无法启动局域网服务发现：$error');
    }
    try {
      final pointerQueries = <Future<List<PtrResourceRecord>>>[
        _collect(
          client.lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer('$serviceType.local'),
          ),
          discoveryTimeout,
        ),
        if (Platform.isWindows)
          _collect(
            client.lookup<PtrResourceRecord>(
              ResourceRecordQuery.serverPointer(
                '$serviceType.local',
                isMulticast: false,
              ),
            ),
            discoveryTimeout,
          ),
      ];
      final pointerResults = await Future.wait(pointerQueries);
      final pointers = <PtrResourceRecord>[
        for (final result in pointerResults) ...result,
      ];
      final domains = <String>{
        for (final pointer in pointers)
          if (pointer.domainName.trim().isNotEmpty) pointer.domainName.trim(),
      };
      final resolved = await Future.wait(
        domains.map((domain) => _resolveService(client, domain)),
      );
      final services = resolved.whereType<_DiscoveredService>().toList(
        growable: false,
      );
      unawaited(
        ReaderLog.instance.log(
          'reamicro_lan_discovery',
          fields: <String, Object?>{
            'service': serviceType,
            'pointers': pointers.length,
            'domains': domains.length,
            'resolved': services.length,
          },
        ),
      );
      return services;
    } finally {
      client.stop();
      windows?.close();
      await _releaseAndroidMulticastLock();
    }
  }

  Future<_WindowsMdnsEnvironment?> _prepareWindowsMdns() async {
    if (!Platform.isWindows) return null;
    final candidates = await NetworkInterface.list(
      includeLinkLocal: true,
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final usable = await selectReachableMulticastInterfaces(
      candidates.where((interface) => interface.addresses.isNotEmpty),
      _canSendMulticast,
    );
    if (usable.isEmpty) {
      throw const ReaMicroException('没有可用于局域网发现的网络接口');
    }
    return _WindowsMdnsEnvironment(interfaces: usable);
  }

  Future<void> _acquireAndroidMulticastLock() async {
    if (!Platform.isAndroid) return;
    try {
      await const MethodChannel('com.spectacular.reader_mobile/reader')
          .invokeMethod<void>('acquireMulticastLock');
    } on PlatformException {
      // mDNS 在部分设备上仍可工作，锁申请失败不阻断设备扫描。
    } on MissingPluginException {
      // 测试或非完整平台宿主没有注册通道。
    }
  }

  Future<void> _releaseAndroidMulticastLock() async {
    if (!Platform.isAndroid) return;
    try {
      await const MethodChannel('com.spectacular.reader_mobile/reader')
          .invokeMethod<void>('releaseMulticastLock');
    } on PlatformException {
      // 同上。
    } on MissingPluginException {
      // 同上。
    }
  }

  Future<_DiscoveredService?> _resolveService(
    MDnsClient client,
    String domain,
  ) async {
    final srvFuture = _first<SrvResourceRecord>(
      client.lookup<SrvResourceRecord>(ResourceRecordQuery.service(domain)),
    );
    final txtFuture = _collect(
      client.lookup<TxtResourceRecord>(ResourceRecordQuery.text(domain)),
      discoveryTimeout,
    );
    final srv = await srvFuture;
    if (srv == null) return null;
    final host = await _resolveHost(client, srv.target);
    if (host == null) return null;
    final txtRecords = await txtFuture;
    final txt = <String, String>{};
    for (final record in txtRecords) {
      txt.addAll(_parseTxt(record.text));
    }
    return _DiscoveredService(
      host: host,
      port: srv.port,
      txt: <String, String>{
        for (final entry in txt.entries)
          entry.key: _decodeTxtValue(entry.value),
      },
    );
  }

  Future<String?> _resolveHost(MDnsClient client, String target) async {
    final ipv4 = await _first<IPAddressResourceRecord>(
      client.lookup<IPAddressResourceRecord>(
        ResourceRecordQuery.addressIPv4(target),
      ),
    );
    if (ipv4 != null) return ipv4.address.address;
    final ipv6 = await _first<IPAddressResourceRecord>(
      client.lookup<IPAddressResourceRecord>(
        ResourceRecordQuery.addressIPv6(target),
      ),
    );
    if (ipv6 != null) return ipv6.address.address;
    final host = target.replaceFirst(RegExp(r'\.$'), '');
    try {
      final addresses = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 2));
      return addresses.isEmpty ? null : addresses.first.address;
    } on Object {
      return null;
    }
  }

  /// 让流在固定时间内收集结果；mDNS 查询可能持续等待后续响应。
  Future<List<T>> _collect<T>(Stream<T> stream, Duration timeout) async {
    final items = <T>[];
    final completer = Completer<void>();
    late final StreamSubscription<T> subscription;
    late final Timer timer;
    void finish() {
      if (!completer.isCompleted) completer.complete();
    }

    timer = Timer(timeout, finish);
    subscription = stream.listen(
      items.add,
      onError: (Object _) => finish(),
      onDone: finish,
      cancelOnError: true,
    );
    try {
      await completer.future;
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
    return items;
  }

  Future<T?> _first<T>(Stream<T> stream) async {
    try {
      return await stream.first.timeout(const Duration(seconds: 2));
    } on Object {
      return null;
    }
  }
}

/// 解码阅微 `GET_FILES` 的二进制响应。
///
/// 格式为一个大端 `uint32` 文件数，随后每项依次为 `uint32` 路径字节数、
/// UTF-8 路径、`uint32` 内容字节数和原始内容。
@visibleForTesting
Map<String, Uint8List> decodeReaMicroLanFilesPayload(Uint8List payload) {
  final reader = _BytePayloadReader(payload);
  final count = reader.readUint32();
  if (count > 100000) {
    throw const ReaMicroException('设备返回的文件数量异常');
  }
  final result = <String, Uint8List>{};
  for (var index = 0; index < count; index++) {
    final pathLength = reader.readUint32();
    final path = reader.readUtf8(pathLength);
    final dataLength = reader.readUint32();
    result[path] = reader.readBytes(dataLength);
  }
  if (!reader.finished) {
    throw const ReaMicroException('设备返回的图书文件包含多余数据');
  }
  return result;
}

bool _isSafeArchivePath(String value) {
  final path = value.trim().replaceAll('\\', '/');
  if (path.isEmpty || path.startsWith('/') || path.endsWith('/')) return false;
  final segments = path.split('/');
  return segments.every(
    (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
  );
}

String _normalizeArchivePath(String value) =>
    value.trim().replaceAll('\\', '/');

Uint8List _buildEpubArchive(Map<String, Uint8List> contents) {
  // 部分设备导出目录时不会保留 mimetype 文件；EPUB 规范要求的这个
  // 固定条目可以由客户端补回，不能因此判定整本书不可下载。
  const epubMimetype = 'application/epub+zip';
  final mimetype = utf8.encode(epubMimetype);
  final archive = Archive()
    ..addFile(ArchiveFile.noCompress('mimetype', mimetype.length, mimetype));
  final paths = contents.keys.where((path) => path != 'mimetype').toList()
    ..sort();
  for (final path in paths) {
    final bytes = contents[path]!;
    archive.addFile(ArchiveFile.bytes(path, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

class _BytePayloadReader {
  _BytePayloadReader(this.bytes);

  final Uint8List bytes;
  int offset = 0;

  bool get finished => offset == bytes.length;

  int readUint32() {
    if (offset + 4 > bytes.length) {
      throw const ReaMicroException('图书文件数据长度不足');
    }
    final value =
        (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
    offset += 4;
    return value;
  }

  Uint8List readBytes(int length) {
    if (length < 0 || offset + length > bytes.length) {
      throw const ReaMicroException('图书文件内容长度不足');
    }
    final value = Uint8List.sublistView(bytes, offset, offset + length);
    offset += length;
    return Uint8List.fromList(value);
  }

  String readUtf8(int length) =>
      utf8.decode(readBytes(length), allowMalformed: true);
}

Object? _decodeManifestPayload(Uint8List payload) {
  var offset = 0;
  if (payload.length >= 3 &&
      payload[0] == 0xef &&
      payload[1] == 0xbb &&
      payload[2] == 0xbf) {
    offset = 3;
  }
  while (offset < payload.length && _isJsonWhitespace(payload[offset])) {
    offset++;
  }
  if (offset < payload.length &&
      (payload[offset] == 0x7b || payload[offset] == 0x5b)) {
    return jsonDecode(utf8.decode(Uint8List.sublistView(payload, offset)));
  }
  return ReaMicroCborDecoder.decode(payload);
}

bool _isJsonWhitespace(int byte) =>
    byte == 0x20 || byte == 0x09 || byte == 0x0a || byte == 0x0d;

/// 过滤无法发送 mDNS 组播的网卡。
///
/// Windows 上断开或虚拟的网卡可能让组播设置返回 `WSAENOPROTOOPT` 或
/// `WSAEADDRNOTAVAIL`，单个坏网卡不应阻断整个设备发现。
Future<List<T>> selectReachableMulticastInterfaces<T>(
  Iterable<T> candidates,
  Future<bool> Function(T candidate) canJoin,
) async {
  final selected = <T>[];
  for (final candidate in candidates) {
    if (await canJoin(candidate)) selected.add(candidate);
  }
  return selected;
}

Future<bool> _canSendMulticast(NetworkInterface interface) async {
  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0, ttl: 255);
    socket.multicastHops = 255;
    socket.setRawOption(
      RawSocketOption(
        RawSocketOption.levelIPv4,
        RawSocketOption.IPv4MulticastInterface,
        _preferredMulticastAddress(interface).rawAddress,
      ),
    );
    return true;
  } on Object {
    return false;
  } finally {
    socket?.close();
  }
}

InternetAddress _preferredMulticastAddress(NetworkInterface interface) {
  for (final address in interface.addresses) {
    if (address.type == InternetAddressType.IPv4 &&
        !address.isLinkLocal &&
        !address.isLoopback) {
      return address;
    }
  }
  return interface.addresses.first;
}

class _WindowsMdnsEnvironment {
  _WindowsMdnsEnvironment({required this.interfaces});

  final List<NetworkInterface> interfaces;
  final List<RawDatagramSocket> _boundSockets = <RawDatagramSocket>[];

  Future<Iterable<NetworkInterface>> interfacesFactory(
    InternetAddressType type,
  ) async {
    if (type != InternetAddressType.IPv4) return const <NetworkInterface>[];
    return interfaces;
  }

  Future<RawDatagramSocket> bindDatagramSocket(
    dynamic host,
    int port, {
    bool reuseAddress = true,
    bool reusePort = false,
    int ttl = 1,
  }) async {
    final socket = await RawDatagramSocket.bind(
      host,
      port,
      reuseAddress: reuseAddress,
      reusePort: false,
      ttl: ttl,
    );
    _boundSockets.add(socket);
    if (host.toString() != InternetAddress.anyIPv4.address) return socket;
    return _LanMdnsDatagramSocket(socket, interfaces);
  }

  void close() {
    for (final socket in _boundSockets) {
      socket.close();
    }
    _boundSockets.clear();
  }
}

/// 在 Windows 上从每块可用网卡分别发送 mDNS 查询，并保持 5353 源端口。
///
/// 系统默认组播路由可能指向 VPN 或虚拟网卡，导致查询走到不可达的网络。
/// 查询和接收共用绑定 `0.0.0.0:5353` 的原始套接字，避免 responder 把响应
/// 送回临时发送端口而应用收不到。
class _LanMdnsDatagramSocket extends Stream<RawSocketEvent>
    implements RawDatagramSocket {
  _LanMdnsDatagramSocket(this._inner, this._interfaces) {
    _inner.multicastHops = 255;
  }

  final RawDatagramSocket _inner;
  final List<NetworkInterface> _interfaces;

  @override
  bool get readEventsEnabled => _inner.readEventsEnabled;

  @override
  set readEventsEnabled(bool value) => _inner.readEventsEnabled = value;

  @override
  bool get writeEventsEnabled => _inner.writeEventsEnabled;

  @override
  set writeEventsEnabled(bool value) => _inner.writeEventsEnabled = value;

  @override
  bool get multicastLoopback => _inner.multicastLoopback;

  @override
  set multicastLoopback(bool value) => _inner.multicastLoopback = value;

  @override
  int get multicastHops => _inner.multicastHops;

  @override
  set multicastHops(int value) => _inner.multicastHops = value;

  @override
  NetworkInterface? get multicastInterface => null;

  @override
  set multicastInterface(NetworkInterface? value) {}

  @override
  bool get broadcastEnabled => _inner.broadcastEnabled;

  @override
  set broadcastEnabled(bool value) => _inner.broadcastEnabled = value;

  @override
  int get port => _inner.port;

  @override
  InternetAddress get address => _inner.address;

  @override
  void close() {
    _inner.close();
  }

  @override
  Datagram? receive() => _inner.receive();

  @override
  int send(List<int> buffer, InternetAddress address, int port) {
    var sent = 0;
    for (final interface in _interfaces) {
      try {
        _inner.setRawOption(
          RawSocketOption(
            RawSocketOption.levelIPv4,
            RawSocketOption.IPv4MulticastInterface,
            _preferredMulticastAddress(interface).rawAddress,
          ),
        );
        final result = _inner.send(buffer, address, port);
        if (result > sent) sent = result;
      } on Object {
        // 某块网卡暂时不可达时继续尝试其余网卡。
      }
    }
    return sent;
  }

  @override
  void joinMulticast(InternetAddress group, [NetworkInterface? interface]) {
    try {
      _inner.joinMulticast(group, interface);
    } on Object {
      // 已被筛选的网卡仍可能因系统状态变化失败，跳过即可。
    }
  }

  @override
  void leaveMulticast(InternetAddress group, [NetworkInterface? interface]) {
    try {
      _inner.leaveMulticast(group, interface);
    } on Object {
      // 套接字可能已关闭。
    }
  }

  @override
  Uint8List getRawOption(RawSocketOption option) => _inner.getRawOption(option);

  @override
  void setRawOption(RawSocketOption option) => _inner.setRawOption(option);

  @override
  StreamSubscription<RawSocketEvent> listen(
    void Function(RawSocketEvent event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _inner.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

class _DiscoveredService {
  const _DiscoveredService({
    required this.host,
    required this.port,
    required this.txt,
  });

  final String host;
  final int port;
  final Map<String, String> txt;
}

/// 按换行命令头和长度字段读取局域网协议数据。
///
/// 清单负载可能是二进制 CBOR 或 UTF-8 JSON，不能先经过文本行切分；该读取器
/// 直接从套接字缓存字节，确保命令头之后的数据不会被解码器或行切分器吞掉。
class _SocketFrameReader {
  _SocketFrameReader(Socket socket, {required this.timeout})
    : _iterator = StreamIterator<List<int>>(socket.cast<List<int>>());

  final StreamIterator<List<int>> _iterator;
  final Duration timeout;
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
        throw const ReaMicroException('设备返回的同步清单数据不完整');
      }
    }
    final value = Uint8List.fromList(_buffer.sublist(0, length));
    _buffer.removeRange(0, length);
    return value;
  }

  Future<bool> _fill() async {
    if (_closed) return false;
    final hasNext = await _iterator.moveNext().timeout(
      timeout,
      onTimeout: () => false,
    );
    if (!hasNext) {
      _closed = true;
      return false;
    }
    _buffer.addAll(_iterator.current);
    return true;
  }

  Future<void> cancel() => _iterator.cancel();
}

Map<String, String> _parseTxt(String text) {
  final result = <String, String>{};
  for (final rawLine in text.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final separator = line.indexOf('=');
    if (separator <= 0) continue;
    result[line.substring(0, separator).trim()] = line
        .substring(separator + 1)
        .trim();
  }
  return result;
}

String _decodeTxtValue(String value) {
  if (!value.startsWith('b64:')) return value;
  try {
    return utf8.decode(base64Decode(value.substring(4)));
  } on FormatException {
    return '';
  }
}

String _safeText(String value) {
  final text = value.replaceAll(RegExp(r'[\r\n|]'), ' ').trim();
  return text.length > 48 ? text.substring(0, 48) : text;
}
