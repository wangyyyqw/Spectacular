import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/rea_micro/rea_micro_lan.dart';

const String _service = '_reamicro-login._tcp.local';
const String _instance = 'Fake Device.$_service';
const String _host = 'fake-reamicro.local';
final InternetAddress _group = InternetAddress('224.0.0.251');

void main() {
  test(
    'Windows 可跳过无效网卡并发现局域网阅微设备',
    () async {
      final responder = await _FakeResponder.start();
      addTearDown(responder.close);
      final client = ReaMicroLanClient(
        discoveryTimeout: const Duration(seconds: 4),
      );

      final devices = await client.discoverLoginDevices();

      final device = devices.firstWhere((item) => item.userId == '42');
      expect(device.nickname, '假设备');
      expect(device.port, 45678);
    },
    skip: !Platform.isWindows ? '仅在 Windows 上验证组播发现' : false,
    timeout: const Timeout(Duration(seconds: 40)),
  );
}

class _FakeResponder {
  _FakeResponder._(this._socket);

  final RawDatagramSocket _socket;

  static Future<_FakeResponder> start() async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      5353,
      reuseAddress: true,
    );
    final interfaces = await NetworkInterface.list(
      includeLinkLocal: true,
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    NetworkInterface? primary;
    for (final interface in interfaces) {
      try {
        socket.joinMulticast(_group, interface);
      } on Object {
        continue;
      }
      if (primary == null &&
          !interface.addresses.first.isLinkLocal &&
          !interface.addresses.first.isLoopback) {
        primary = interface;
      }
    }
    if (primary == null) {
      socket.close();
      throw StateError('没有可用网卡');
    }
    socket.setRawOption(
      RawSocketOption(
        RawSocketOption.levelIPv4,
        RawSocketOption.IPv4MulticastInterface,
        primary.addresses.first.rawAddress,
      ),
    );
    final responder = _FakeResponder._(socket);
    socket.listen(responder._handle);
    return responder;
  }

  void _handle(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket.receive();
    if (datagram == null || datagram.data.length < 12) return;
    final data = datagram.data;
    if ((data[2] & 0x80) != 0) return;
    final questionEnd = _questionEnd(data);
    if (questionEnd == null) return;
    if (_readName(data, 12) != _service) return;
    _socket.send(_buildResponse(data.sublist(12, questionEnd)), _group, 5353);
  }

  void close() => _socket.close();
}

int? _questionEnd(Uint8List data) {
  var offset = 12;
  while (offset < data.length) {
    final length = data[offset];
    if (length == 0) return offset + 5;
    if (length >= 0xC0) return null;
    offset += length + 1;
  }
  return null;
}

String _readName(Uint8List data, int offset) {
  final parts = <String>[];
  while (offset < data.length) {
    final length = data[offset++];
    if (length == 0) break;
    parts.add(utf8.decode(data.sublist(offset, offset + length)));
    offset += length;
  }
  return parts.join('.');
}

List<int> _encodeName(String name) {
  final result = <int>[];
  for (final part in name.split('.')) {
    final bytes = utf8.encode(part);
    result.add(bytes.length);
    result.addAll(bytes);
  }
  result.add(0);
  return result;
}

List<int> _record(String name, int type, List<int> data) {
  return <int>[
    ..._encodeName(name),
    type >> 8,
    type & 0xFF,
    0,
    1,
    0,
    0,
    0,
    120,
    data.length >> 8,
    data.length & 0xFF,
    ...data,
  ];
}

List<int> _buildResponse(List<int> question) {
  final srv = <int>[
    0,
    0,
    0,
    0,
    45678 >> 8,
    45678 & 0xFF,
    ..._encodeName(_host),
  ];
  final txt = <int>[];
  for (final value in <String>['userId=42', 'nickname=假设备', 'avatar=']) {
    final bytes = utf8.encode(value);
    txt
      ..add(bytes.length)
      ..addAll(bytes);
  }
  return <int>[
    0,
    0,
    0x84,
    0,
    0,
    1,
    0,
    4,
    0,
    0,
    0,
    0,
    ...question,
    ..._record(_service, 12, _encodeName(_instance)),
    ..._record(_instance, 33, srv),
    ..._record(_instance, 16, txt),
    ..._record(_host, 1, InternetAddress.loopbackIPv4.rawAddress),
  ];
}
