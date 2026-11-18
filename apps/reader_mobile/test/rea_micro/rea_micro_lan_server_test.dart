import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/rea_micro/rea_micro_lan.dart';
import 'package:reader_mobile/rea_micro/rea_micro_lan_rsa.dart';
import 'package:reader_mobile/rea_micro/rea_micro_lan_server.dart';

void main() {
  test('授权端显示登录申请并用请求方公钥加密令牌', () async {
    final server = ReaMicroLanLoginServer(discoveryEnabled: false);
    addTearDown(server.stop);
    await server.start(
      userId: 7,
      nickname: '授权端',
      avatar: '',
      token: 'access-token-123',
      deviceId: 'test-device',
    );
    final pair = await Isolate.run(ReaMicroLanRsa.generate);
    final client = await Socket.connect(
      InternetAddress.loopbackIPv4,
      server.port!,
    );
    addTearDown(client.destroy);
    final changed = Completer<ReaMicroLanLoginRequest>();
    server.onRequestsChanged = (requests) {
      if (requests.isNotEmpty && !changed.isCompleted) {
        changed.complete(requests.single);
      }
    };

    client.write(
      'REQUEST|Windows PC|${ReaMicroLanRsa.encodePublicKey(pair.publicKey)}\n',
    );
    await client.flush();

    final request = await changed.future.timeout(const Duration(seconds: 2));
    expect(request.deviceModel, 'Windows PC');
    expect(server.requests, hasLength(1));

    final response = Completer<String>();
    final subscription = client
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (!response.isCompleted) response.complete(line);
        });
    addTearDown(subscription.cancel);

    await server.approve(request.id);

    final line = await response.future.timeout(const Duration(seconds: 2));
    expect(line, startsWith('TOKEN|'));
    final token = ReaMicroLanRsa.decryptToken(
      line.substring('TOKEN|'.length),
      pair.privateKey,
    );
    expect(token, 'access-token-123');
    expect(server.requests, isEmpty);
  });

  test('授权端拒绝登录申请并清理待授权列表', () async {
    final server = ReaMicroLanLoginServer(discoveryEnabled: false);
    addTearDown(server.stop);
    await server.start(
      userId: 7,
      nickname: '授权端',
      avatar: '',
      token: 'access-token-123',
      deviceId: 'test-device',
    );
    final pair = await Isolate.run(ReaMicroLanRsa.generate);
    final client = await Socket.connect(
      InternetAddress.loopbackIPv4,
      server.port!,
    );
    addTearDown(client.destroy);
    final changed = Completer<ReaMicroLanLoginRequest>();
    server.onRequestsChanged = (requests) {
      if (requests.isNotEmpty && !changed.isCompleted) {
        changed.complete(requests.single);
      }
    };
    client.write(
      'REQUEST|Android|${ReaMicroLanRsa.encodePublicKey(pair.publicKey)}\n',
    );
    await client.flush();

    final request = await changed.future.timeout(const Duration(seconds: 2));
    final lines = StreamIterator<String>(
      client
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter()),
    );
    addTearDown(lines.cancel);
    await server.reject(request.id);

    expect(await lines.moveNext().timeout(const Duration(seconds: 2)), isTrue);
    expect(lines.current.trim(), 'REJECT');
    expect(server.requests, isEmpty);
  });

  test('授权端回复 PROFILE 时不产生待授权申请', () async {
    final server = ReaMicroLanLoginServer(discoveryEnabled: false);
    addTearDown(server.stop);
    await server.start(
      userId: 7,
      nickname: '授权端',
      avatar: 'https://example.com/avatar.png',
      token: 'access-token-123',
      deviceId: 'test-device',
    );
    final client = await Socket.connect(
      InternetAddress.loopbackIPv4,
      server.port!,
    );
    addTearDown(client.destroy);
    final lines = StreamIterator<String>(
      client
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter()),
    );
    addTearDown(lines.cancel);

    client.write('PROFILE\n');
    await client.flush();

    expect(await lines.moveNext().timeout(const Duration(seconds: 2)), isTrue);
    expect(lines.current, startsWith('PROFILE|'));
    final profile = jsonDecode(
      lines.current.substring('PROFILE|'.length),
    ) as Map<String, Object?>;
    expect(profile['userId'], 7);
    expect(profile['nickname'], '授权端');
    expect(server.requests, isEmpty);
  });

  test('授权端 mDNS 应答包含实际端口、TXT 和地址记录', () {
    final packet = buildReaMicroLoginMdnsResponse(
      instanceName: 'ReaMicro-7',
      hostName: 'spectacular-test.local',
      port: 6255,
      txt: <String, String>{
        'userId': '7',
        'nickname': '授权端',
        'avatar': 'https://example.com/avatar.png',
      },
      addresses: <InternetAddress>[InternetAddress('192.168.10.123')],
    );

    final answers = _parseMdnsAnswers(packet);
    expect(answers, hasLength(4));

    final srv = answers.singleWhere((answer) => answer.type == 33);
    expect(srv.name, 'ReaMicro-7._reamicro-login._tcp.local');
    expect(srv.port, 6255);
    expect(srv.target, 'spectacular-test.local');

    final txt = answers.singleWhere((answer) => answer.type == 16);
    expect(txt.name, 'ReaMicro-7._reamicro-login._tcp.local');
    expect(txt.txt, <String, String>{
      'userId': '7',
      'nickname': '授权端',
      'avatar': 'https://example.com/avatar.png',
    });

    final address = answers.singleWhere((answer) => answer.type == 1);
    expect(address.name, 'spectacular-test.local');
    expect(address.address, '192.168.10.123');
  });

  test('授权广播优先真实局域网并跳过 VPN 与虚拟网卡', () {
    expect(
      shouldAdvertiseLanInterface('WLAN', <InternetAddress>[
        InternetAddress('192.168.10.123'),
      ]),
      isTrue,
    );
    expect(
      shouldAdvertiseLanInterface('以太网', <InternetAddress>[
        InternetAddress('10.0.0.5'),
      ]),
      isTrue,
    );
    expect(
      shouldAdvertiseLanInterface('Radmin VPN', <InternetAddress>[
        InternetAddress('26.119.101.18'),
      ]),
      isFalse,
    );
    expect(
      shouldAdvertiseLanInterface(
        'vEthernet (WSL (Hyper-V firewall))',
        <InternetAddress>[InternetAddress('172.28.240.1')],
      ),
      isFalse,
    );
    expect(isPrivateLanIpv4(InternetAddress('192.168.10.123')), isTrue);
    expect(isPrivateLanIpv4(InternetAddress('26.119.101.18')), isFalse);
  });

  test('同步端提供书籍清单并返回校验后的 EPUB 文件', () async {
    final directory = await Directory.systemTemp.createTemp('lan-sync-test');
    addTearDown(() => directory.delete(recursive: true));
    final source = <String, List<int>>{
      'mimetype': utf8.encode('application/epub+zip'),
      'META-INF/container.xml': utf8.encode(
        '<container version="1.0"></container>',
      ),
      'OEBPS/chapter.xhtml': utf8.encode('<html><body>正文</body></html>'),
    };
    final archive = Archive();
    for (final entry in source.entries) {
      archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
    }
    final epub = File('${directory.path}/book.epub');
    await epub.writeAsBytes(ZipEncoder().encodeBytes(archive));

    final server = ReaMicroLanLoginServer(discoveryEnabled: false);
    addTearDown(server.stop);
    await server.start(
      userId: 7,
      nickname: '同步端',
      avatar: '',
      token: 'access-token-123',
      deviceId: 'test-device',
      deviceName: '测试电脑',
      syncBooks: () async => <ReaMicroLanServedBook>[
        ReaMicroLanServedBook(
          uuid: 'book-1',
          title: '测试书',
          author: '作者',
          filePath: epub.path,
          cfi: 'epubcfi(/6/4!/4/2)',
          chapterName: '第一章',
          progress: 0.42,
          updatedAt: 1700000000000,
          finished: false,
        ),
      ],
    );

    final manifestSocket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      server.port!,
    );
    final manifestReader = _TestFrameReader(manifestSocket);
    addTearDown(manifestReader.cancel);
    manifestSocket.write('MANIFEST\n');
    await manifestSocket.flush();
    final manifestLine = await manifestReader.readLine();
    expect(manifestLine, startsWith('MANIFEST '));
    final manifestLength = int.parse(manifestLine!.split(' ')[1]);
    final manifestBytes = await manifestReader.readBytes(manifestLength);
    final manifest =
        jsonDecode(utf8.decode(manifestBytes)) as Map<String, Object?>;
    expect(manifest['userId'], 7);
    expect(manifest['deviceId'], 'test-device');
    final books = manifest['books']! as List<Object?>;
    expect(books, hasLength(1));
    final book = books.single! as Map<String, Object?>;
    final snapshot = book['book']! as Map<String, Object?>;
    expect(book['uuid'], 'book-1');
    expect(snapshot['title'], '测试书');
    expect(snapshot['epubcfi'], 'epubcfi(/6/4!/4/2)');
    expect(book['progressUpdatedAt'], 1700000000000);
    final files = book['files']! as List<Object?>;
    expect(files, hasLength(3));
    expect(
      files.map((item) => (item! as Map<String, Object?>)['relativePath']),
      containsAll(<String>['mimetype', 'OEBPS/chapter.xhtml']),
    );
    await manifestReader.cancel();
    manifestSocket.destroy();

    final filesSocket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      server.port!,
    );
    final filesReader = _TestFrameReader(filesSocket);
    addTearDown(filesReader.cancel);
    final request = utf8.encode(
      jsonEncode(<String, Object?>{
        'uuid': 'book-1',
        'paths': <String>['mimetype', 'OEBPS/chapter.xhtml', '../escape'],
      }),
    );
    filesSocket.write('GET_FILES ${request.length}\n');
    filesSocket.add(request);
    await filesSocket.flush();
    final filesLine = await filesReader.readLine();
    expect(filesLine, startsWith('FILES '));
    final filesLength = int.parse(filesLine!.split(' ')[1]);
    final filesBytes = await filesReader.readBytes(filesLength);
    final contents = decodeReaMicroLanFilesPayload(filesBytes);
    expect(contents, hasLength(2));
    expect(utf8.decode(contents['mimetype']!), 'application/epub+zip');
    expect(utf8.decode(contents['OEBPS/chapter.xhtml']!), contains('正文'));
    await filesReader.cancel();
    filesSocket.destroy();
  });

  test('等待人工批准登录可超过普通帧超时', () async {
    final server = ReaMicroLanLoginServer(discoveryEnabled: false);
    addTearDown(server.stop);
    await server.start(
      userId: 7,
      nickname: '授权端',
      avatar: '',
      token: 'access-token-delayed',
      deviceId: 'test-device',
    );
    final changed = Completer<ReaMicroLanLoginRequest>();
    server.onRequestsChanged = (requests) {
      if (requests.isNotEmpty && !changed.isCompleted) {
        changed.complete(requests.single);
      }
    };
    final client = ReaMicroLanClient(
      socketTimeout: const Duration(milliseconds: 150),
      loginTimeout: const Duration(seconds: 5),
    );
    final login = client.login(
      ReaMicroLanLoginDevice(
        host: InternetAddress.loopbackIPv4.address,
        port: server.port!,
        userId: '7',
        nickname: '申请端',
        avatar: '',
      ),
    );
    final request = await changed.future.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await server.approve(request.id);
    expect(
      await login.timeout(const Duration(seconds: 5)),
      'access-token-delayed',
    );
  });
}

class _MdnsAnswer {
  const _MdnsAnswer({
    required this.name,
    required this.type,
    this.port,
    this.target,
    this.txt,
    this.address,
  });

  final String name;
  final int type;
  final int? port;
  final String? target;
  final Map<String, String>? txt;
  final String? address;
}

class _TestFrameReader {
  _TestFrameReader(Socket socket)
    : _iterator = StreamIterator<List<int>>(socket.cast<List<int>>());

  final StreamIterator<List<int>> _iterator;
  final List<int> _buffer = <int>[];

  Future<String?> readLine() async {
    while (true) {
      final newline = _buffer.indexOf(10);
      if (newline >= 0) {
        final bytes = _buffer.sublist(0, newline);
        _buffer.removeRange(0, newline + 1);
        if (bytes.isNotEmpty && bytes.last == 13) bytes.removeLast();
        return utf8.decode(bytes);
      }
      if (!await _fill()) return null;
    }
  }

  Future<Uint8List> readBytes(int length) async {
    while (_buffer.length < length) {
      if (!await _fill()) {
        throw StateError('数据不足');
      }
    }
    final value = Uint8List.fromList(_buffer.sublist(0, length));
    _buffer.removeRange(0, length);
    return value;
  }

  Future<bool> _fill() async {
    final hasNext = await _iterator.moveNext().timeout(
      const Duration(seconds: 5),
      onTimeout: () => false,
    );
    if (!hasNext) return false;
    _buffer.addAll(_iterator.current);
    return true;
  }

  Future<void> cancel() => _iterator.cancel();
}

List<_MdnsAnswer> _parseMdnsAnswers(Uint8List packet) {
  final answerCount = (packet[6] << 8) | packet[7];
  var offset = 12;
  final answers = <_MdnsAnswer>[];
  for (var index = 0; index < answerCount; index++) {
    final name = _readName(packet, offset);
    offset = name.nextOffset;
    final type = (packet[offset] << 8) | packet[offset + 1];
    final dataLength = (packet[offset + 8] << 8) | packet[offset + 9];
    final dataStart = offset + 10;
    final dataEnd = dataStart + dataLength;
    if (dataEnd > packet.length) {
      throw const FormatException('mDNS 记录长度超出数据包');
    }
    switch (type) {
      case 33:
        final port = (packet[dataStart + 4] << 8) | packet[dataStart + 5];
        final target = _readName(packet, dataStart + 6);
        answers.add(
          _MdnsAnswer(
            name: name.value,
            type: type,
            port: port,
            target: target.value,
          ),
        );
        break;
      case 16:
        final txt = <String, String>{};
        var cursor = dataStart;
        while (cursor < dataEnd) {
          final length = packet[cursor++];
          if (cursor + length > dataEnd) {
            throw const FormatException('TXT 记录长度超出数据包');
          }
          final line = utf8.decode(packet.sublist(cursor, cursor + length));
          cursor += length;
          final separator = line.indexOf('=');
          if (separator > 0) {
            txt[line.substring(0, separator)] = line.substring(separator + 1);
          }
        }
        answers.add(_MdnsAnswer(name: name.value, type: type, txt: txt));
        break;
      case 1:
        if (dataLength != 4) {
          throw const FormatException('A 记录长度不正确');
        }
        answers.add(
          _MdnsAnswer(
            name: name.value,
            type: type,
            address: packet.sublist(dataStart, dataEnd).join('.'),
          ),
        );
        break;
      default:
        answers.add(_MdnsAnswer(name: name.value, type: type));
        break;
    }
    offset = dataEnd;
  }
  if (offset != packet.length) {
    throw const FormatException('mDNS 数据包包含多余字节');
  }
  return answers;
}

({String value, int nextOffset}) _readName(Uint8List packet, int offset) {
  final parts = <String>[];
  var cursor = offset;
  var nextOffset = offset;
  var jumped = false;
  while (cursor < packet.length) {
    final length = packet[cursor];
    if (length == 0) {
      if (!jumped) nextOffset = cursor + 1;
      break;
    }
    if ((length & 0xc0) == 0xc0) {
      final pointer = ((length & 0x3f) << 8) | packet[cursor + 1];
      if (!jumped) nextOffset = cursor + 2;
      cursor = pointer;
      jumped = true;
      continue;
    }
    cursor++;
    if (cursor + length > packet.length) {
      throw const FormatException('mDNS 名称越界');
    }
    parts.add(utf8.decode(packet.sublist(cursor, cursor + length)));
    cursor += length;
    if (!jumped) nextOffset = cursor;
  }
  return (value: parts.join('.'), nextOffset: nextOffset);
}
