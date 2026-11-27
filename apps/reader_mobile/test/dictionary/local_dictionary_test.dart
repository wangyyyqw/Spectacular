import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:reader_mobile/dictionary/local_dictionary_server.dart';
import 'package:reader_mobile/dictionary/local_dictionary_store.dart';
import 'package:reader_mobile/library/library_store.dart';

import 'mdict_fixture.dart';

void main() {
  late Directory directory;
  late LocalDictionaryStore store;
  late LibraryStore library;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('local_dictionary_test_');
    library = LibraryStore.memory();
    store = LocalDictionaryStore(
      library,
      directoryProvider: () async => directory,
    );
  });
  tearDown(() async => directory.delete(recursive: true));

  for (final version in [1, 2]) {
    test('MDX $version.x 导入、索引重开、别名、候选和移除不修改源文件', () async {
      final source = await createMdictFixture(
        directory,
        version: version,
        compression: version == 1 ? 0 : 2,
      );
      final original = await source.readAsBytes();
      final entry = await store.importFiles([source.path]);
      expect(entry.name, '离线测试词典');
      expect(entry.wordCount, 4);
      final other = LocalDictionaryStore(
        library,
        directoryProvider: () async => directory,
      );
      expect((await other.load()).single.digest, entry.digest);
      final session = await other.open(entry);
      expect(await session.lookup(' Hello '), contains('你好'));
      expect(await session.lookup('alias'), contains('你好'));
      expect(await session.lookup('不存在'), isNull);
      expect(session.suggest('hel'), ['hello', 'help']);
      await expectLater(
        session.lookup('loop'),
        throwsA(
          isA<LocalDictionaryException>().having(
            (e) => e.message,
            '消息',
            contains('跳转循环'),
          ),
        ),
      );
      await session.close();
      await expectLater(
        store.importFiles([source.path]),
        throwsA(isA<LocalDictionaryException>()),
      );
      await store.setEnabled(entry.id, false);
      expect((await store.load()).single.enabled, isFalse);
      await store.remove(entry.id);
      expect(await store.load(), isEmpty);
      expect(await source.readAsBytes(), original);
    });
  }

  test('MDD 多卷图片、CSS 及音频按资源键读取，多个并发请求不串卷', () async {
    final mdx = await createMdictFixture(directory);
    final mdd = await createMdictFixture(
      directory,
      filename: '测试词典.mdd',
      entries: [
        (r'\image.png', [137, 80, 78, 71]),
        (r'\styles\main.css', utf8.encode('.word{color:red}')),
      ],
    );
    final volume = await createMdictFixture(
      directory,
      filename: '测试词典.1.mdd',
      entries: [
        (r'\sound\hello.mp3', [73, 68, 51]),
        (r'\image.png', [1, 2, 3]),
      ],
    );
    final css = await File('${directory.path}/extra.css')
        .writeAsString('b{font-weight:bold}');
    final entry = await store.importFiles([
      mdx.path,
      volume.path,
      mdd.path,
      css.path,
    ]);
    final session = await store.open(entry);
    addTearDown(session.close);
    final resources = await Future.wait([
      session.resource('image.png'),
      session.resource('sound/hello.mp3'),
      session.resource('styles/main.css'),
      session.resource('extra.css'),
    ]);
    expect(resources[0], [137, 80, 78, 71]);
    expect(resources[1], [73, 68, 51]);
    expect(utf8.decode(resources[2]!), contains('color:red'));
    expect(utf8.decode(resources[3]!), contains('font-weight:bold'));
    expect(await session.resource('../extra.css'), isNull);
    expect(await session.resource('missing.png'), isNull);
  });

  test('索引丢失或损坏可从导入副本重建', () async {
    final mdx = await createMdictFixture(directory);
    final entry = await store.importFiles([mdx.path]);
    final index = File(
      '${directory.path}/dictionaries/${entry.id}/dictionary.mdx.cidx',
    );
    for (final missing in [true, false]) {
      if (missing) {
        await index.delete();
      } else {
        await index.writeAsBytes([0, 1]);
      }
      final session = await store.open(entry);
      expect(await session.lookup('help'), '帮助');
      await session.close();
    }
  });

  test('不支持的 LZO、3.0、记录块加密和损坏词库明确报错且回收未完成副本', () async {
    for (final config in [
      (2, 1, 'No', 'LZO'),
      (3, 2, 'No', '3.0'),
      (2, 2, '1', '加密'),
    ]) {
      final source = await createMdictFixture(
        directory,
        version: config.$1,
        compression: config.$2,
        encrypted: config.$3,
      );
      await expectLater(
        store.importFiles([source.path]),
        throwsA(
          isA<LocalDictionaryException>().having(
            (e) => e.message,
            '消息',
            contains(config.$4),
          ),
        ),
      );
      expect(await store.load(), isEmpty);
    }
    final source = await File('${directory.path}/损坏.mdx')
        .writeAsBytes([0, 0, 0, 4, 0, 0, 0, 0]);
    await expectLater(
      store.importFiles([source.path]),
      throwsA(isA<LocalDictionaryException>()),
    );
    expect(
      await Directory('${directory.path}/dictionaries').list().toList(),
      isEmpty,
    );
  });

  test('不接受无 MDX、错误配对或临时模式导入', () async {
    final mdx = await createMdictFixture(directory);
    final resource = await File('${directory.path}/其他.mdd').writeAsBytes([0]);
    await expectLater(
      store.importFiles([resource.path]),
      throwsA(isA<LocalDictionaryException>()),
    );
    await expectLater(
      store.importFiles([mdx.path, resource.path]),
      throwsA(isA<LocalDictionaryException>()),
    );
    expect(LocalDictionaryStore(library).canImport, isFalse);
    await expectLater(
      LocalDictionaryStore(library).importFiles([mdx.path]),
      throwsA(isA<LocalDictionaryException>()),
    );
  });

  test('本地网页阻断脚本、外链和路径越界，并读取真实 MDD 与 CSS', () async {
    final mdx = await createMdictFixture(directory);
    final mdd = await createMdictFixture(
      directory,
      filename: '测试词典.mdd',
      entries: [
        (r'\image.png', [137, 80, 78, 71]),
        (r'\style.css', utf8.encode('b{background:url(image.png)}')),
      ],
    );
    final entry = await store.importFiles([mdx.path, mdd.path]);
    final session = await store.open(entry);
    final server = await LocalDictionaryServer.start(session, '''
<script>alert(1)</script><img src="\\image.png" onerror="alert(1)">
<img src="https://remote.test/x"><iframe src="file:///private"></iframe>
<a href="entry://help">跳转</a><a href="javascript:alert(1)">危险链接</a>
<link rel="stylesheet" href="style.css">''');
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.close();
      await session.close();
    });
    final page = await (await client.getUrl(server.pageUri)).close();
    expect(
      page.headers.value('content-security-policy'),
      contains("default-src 'none'"),
    );
    final document = html.parse(await utf8.decoder.bind(page).join());
    expect(document.querySelectorAll('script,iframe'), isEmpty);
    expect(
      document.querySelector('img')!.attributes.containsKey('onerror'),
      isFalse,
    );
    expect(
      document.querySelector('img')!.attributes['src'],
      server.baseUri.resolve('image.png').toString(),
    );
    expect(
      document.querySelectorAll('a').first.attributes['href'],
      'entry://help',
    );
    expect(
      document.querySelectorAll('a').last.attributes.containsKey('href'),
      isFalse,
    );
    final image = await (await client.getUrl(
      server.baseUri.resolve('image.png'),
    )).close();
    expect(await image.fold<List<int>>([], (a, b) => a..addAll(b)), [
      137,
      80,
      78,
      71,
    ]);
    final css = await (await client.getUrl(server.baseUri.resolve('style.css')))
        .close();
    expect(
      await utf8.decoder.bind(css).join(),
      contains(server.baseUri.resolve('image.png').toString()),
    );
    final forbidden = await (await client.getUrl(
      server.baseUri.resolve('/outside'),
    )).close();
    expect(forbidden.statusCode, HttpStatus.forbidden);
    await forbidden.drain<void>();
    expect(dictionaryResourceUri(server.baseUri, '../private'), isNull);
    expect(dictionaryResourceUri(server.baseUri, '//remote.test/x'), isNull);
    expect(dictionaryResourceUri(server.baseUri, 'file:///private'), isNull);
    expect(
      rewriteDictionaryCss(
        'a{background:url(https://remote.test/x)}',
        server.baseUri,
      ),
      isNot(contains('remote.test')),
    );
  });

  test('本地释义页面统一字号并允许结果纵向滚动', () {
    final html = buildLocalDictionaryHtml(
      '<h1>词条</h1><p>释义</p>',
      Uri.parse('http://127.0.0.1:1234/test/'),
    );
    expect(html, contains('font-size:16px !important'));
    expect(html, contains('line-height:1.6 !important'));
    expect(html, contains('overflow-y:auto'));
    expect(html, contains('overflow-x:hidden'));
  });
}
