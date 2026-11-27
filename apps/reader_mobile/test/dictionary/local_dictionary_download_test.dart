import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/dictionary/builtin_dictionaries.dart';
import 'package:reader_mobile/dictionary/local_dictionary_download.dart';
import 'package:reader_mobile/dictionary/local_dictionary_store.dart';
import 'package:reader_mobile/library/library_store.dart';

import 'mdict_fixture.dart';

void main() {
  late Directory directory;
  late Directory downloads;
  late LocalDictionaryStore store;
  late List<int> bytes;
  late BuiltInDictionary source;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'dictionary-download-test-',
    );
    downloads = await Directory('${directory.path}/downloads').create();
    store = LocalDictionaryStore(
      LibraryStore.memory(),
      directoryProvider: () async => directory,
    );
    bytes = await (await createMdictFixture(directory)).readAsBytes();
    source = BuiltInDictionary(
      id: 'test',
      name: '离线测试词典',
      url: 'https://example.test/dictionary.mdx',
      size: bytes.length,
      digest: sha256.convert(bytes).toString(),
    );
  });
  tearDown(() async => directory.delete(recursive: true));

  test('下载校验后正式导入并启用，离线重开可查词且回收临时文件', () async {
    final progress = <int>[];
    var importing = false;
    final download = LocalDictionaryDownload(
      temporaryDirectoryProvider: () async => downloads,
      client: MockClient.streaming((request, _) async {
        expect(request.url, Uri.parse(source.url));
        return http.StreamedResponse(
          Stream.fromIterable([bytes.sublist(0, 50), bytes.sublist(50)]),
          200,
          contentLength: bytes.length,
        );
      }),
    );
    final entry = await download.install(
      source,
      store,
      onProgress: progress.add,
      onImport: () => importing = true,
    );
    expect(importing, isTrue);
    expect(progress, [50, bytes.length]);
    expect(entry.enabled, isTrue);
    final reopened = LocalDictionaryStore(
      store.library,
      directoryProvider: () async => directory,
    );
    expect((await reopened.load()).single.digest, source.digest);
    final session = await reopened.open(entry);
    try {
      expect(await session.lookup('hello'), contains('你好'));
    } finally {
      await session.close();
    }
    expect(await downloads.list().toList(), isEmpty);
  });

  for (final failure in ['服务器错误', '文件缺失', '文件篡改', '取消下载']) {
    test('$failure 不写入词典清单并清理临时文件', () async {
      final payload = List<int>.of(bytes);
      if (failure == '文件篡改') payload[20] ^= 1;
      if (failure == '文件缺失') payload.removeLast();
      final download = LocalDictionaryDownload(
        temporaryDirectoryProvider: () async => downloads,
        client: MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            Stream.fromIterable([payload.sublist(0, 50), payload.sublist(50)]),
            failure == '服务器错误' ? 404 : 200,
          ),
        ),
      );
      await expectLater(
        download.install(
          source,
          store,
          onProgress: (_) {
            if (failure == '取消下载') download.cancel();
          },
          onImport: () => fail('失败下载不能进入导入'),
        ),
        throwsA(isA<LocalDictionaryException>()),
      );
      expect(await store.load(), isEmpty);
      expect(await downloads.list().toList(), isEmpty);
    });
  }

  test('下载连接异常时提示重试并释放临时目录', () async {
    final download = LocalDictionaryDownload(
      temporaryDirectoryProvider: () async => downloads,
      client: MockClient.streaming((_, _) async {
        throw http.ClientException('连接失败');
      }),
    );
    await expectLater(
      download.install(source, store, onProgress: (_) {}, onImport: () {}),
      throwsA(
        isA<LocalDictionaryException>().having(
          (error) => error.message,
          '错误提示',
          contains('重试'),
        ),
      ),
    );
    expect(await downloads.list().toList(), isEmpty);
    expect(await store.load(), isEmpty);
  });
}
