import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:multicast_dns/multicast_dns.dart';

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
/// 只实现阅读器需要的登录与进度清单读取，不下载整本书文件。所有连接都有
/// 明确超时，服务发现结束后会立即停止 mDNS 客户端。
class ReaMicroLanClient {
  /// 创建客户端。
  ReaMicroLanClient({
    this.discoveryTimeout = const Duration(seconds: 4),
    this.socketTimeout = const Duration(seconds: 8),
  });

  /// 等待 mDNS 返回记录的时间。
  final Duration discoveryTimeout;

  /// 单次局域网连接或读取的超时。
  final Duration socketTimeout;

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
    return result;
  }

  /// 通过局域网设备完成授权登录，返回访问令牌。
  Future<String> login(
    ReaMicroLanLoginDevice device, {
    String? deviceModel,
  }) async {
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
        final line = await _nextLine(iterator);
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
    final socket = await _connect(peer.host, peer.port);
    final iterator = _lineIterator(socket);
    try {
      socket.write('MANIFEST\n');
      await socket.flush();
      final line = await _nextLine(iterator);
      if (!line.startsWith('MANIFEST ')) {
        throw ReaMicroException(
          line.startsWith('ERR ')
              ? '设备返回错误：${line.substring(4)}'
              : '设备返回了无法识别的同步清单',
        );
      }
      final decoded = jsonDecode(line.substring('MANIFEST '.length));
      if (decoded is! Map<String, Object?>) {
        throw const ReaMicroException('同步清单格式不正确');
      }
      return ReaMicroLanManifest.fromJson(decoded);
    } on FormatException {
      throw const ReaMicroException('同步清单不是有效的 JSON');
    } finally {
      try {
        socket.write('BYE\n');
        await socket.flush();
      } catch (_) {
        // 对端可能已主动断开，不影响已经读取的清单。
      }
      await iterator.cancel();
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

  Future<String> _nextLine(StreamIterator<String> iterator) async {
    final hasLine = await iterator.moveNext().timeout(
      socketTimeout,
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
      return resolved.whereType<_DiscoveredService>().toList(growable: false);
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
    final reachable = await selectReachableMulticastInterfaces(
      candidates.where((interface) => interface.addresses.isNotEmpty),
      _canJoinMulticast,
    );
    if (reachable.isEmpty) {
      throw const ReaMicroException('没有可用于局域网发现的网络接口');
    }
    return _WindowsMdnsEnvironment(interfaces: reachable);
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

/// 过滤无法加入 mDNS 组播的网卡。
///
/// Windows 上断开或虚拟的网卡可能让 `joinMulticast` 返回 `WSAENOPROTOOPT`，
/// 单个坏网卡不应阻断整个设备发现。
@visibleForTesting
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

Future<bool> _canJoinMulticast(NetworkInterface interface) async {
  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.joinMulticast(_mdnsMulticastIPv4, interface);
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

final InternetAddress _mdnsMulticastIPv4 = InternetAddress('224.0.0.251');

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
