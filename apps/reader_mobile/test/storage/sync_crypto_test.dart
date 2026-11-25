import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/sync/sync_crypto.dart';
import 'package:reader_mobile/sync/sync_models.dart';
import 'package:reader_mobile/sync/sync_state.dart';

void main() {
  test('认证加密拒绝不同同步库、错误密钥和篡改', () async {
    final key = await SyncCrypto.generateKey();
    final crypto = SyncCrypto('library-a', key);
    final bytes = await crypto.encode([1, 2, 3], 'log');
    expect(await crypto.decode(bytes, 'log'), [1, 2, 3]);
    await expectLater(
      SyncCrypto('library-b', key).decode(bytes, 'log'),
      throwsA(isA<FormatException>()),
    );
    bytes[bytes.length - 1] ^= 1;
    await expectLater(
      crypto.decode(bytes, 'log'),
      throwsA(isA<FormatException>()),
    );
  });

  test('文件分块加密跨越块边界且拒绝截断', () async {
    final root = await Directory.systemTemp.createTemp('sync-crypto-');
    addTearDown(() => root.delete(recursive: true));
    final plain = List<int>.generate(SyncCrypto.chunkSize + 37, (i) => i % 251);
    final source = await File('${root.path}/source').writeAsBytes(plain);
    final encoded = File('${root.path}/encrypted');
    final decoded = File('${root.path}/decoded');
    final digest = sha256.convert(plain).toString();
    final crypto = SyncCrypto('library', await SyncCrypto.generateKey());
    await crypto.encodeFile(source, encoded, digest);
    await crypto.decodeFile(encoded, decoded, digest, plain.length);
    expect(await decoded.readAsBytes(), plain);
    final file = await encoded.open(mode: FileMode.append);
    await file.truncate((await encoded.length()) - 1);
    await file.close();
    await expectLater(
      crypto.decodeFile(encoded, decoded, digest, plain.length),
      throwsA(isA<FormatException>()),
    );
  });

  test('版本向量阻止旧副本覆盖，并发删除优先且显式恢复可传播', () {
    final a = SyncState(device: 'a');
    final first = a.change(const SyncEntity('book/book', {'title': '原版'}));
    final b = SyncState(device: 'b')..receive(first);
    final edit = a.change(const SyncEntity('book/book', {'title': '新版'}));
    final removed = b.change(
      const SyncEntity('book/book', {'title': '原版'}, deleted: true),
    );
    a.receive(removed);
    b.receive(edit);
    expect(a.heads['book/book']!.deleted, isTrue);
    expect(b.heads['book/book']!.deleted, isTrue);
    expect(a.receive(first), isFalse);
    final restored = a.change(const SyncEntity('book/book', {'title': '恢复'}));
    expect(b.receive(restored), isTrue);
    expect(b.heads['book/book']!.deleted, isFalse);
  });
}
