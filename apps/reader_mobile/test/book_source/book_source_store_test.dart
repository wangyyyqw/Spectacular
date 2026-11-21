import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';
import 'package:reader_mobile/book_source/book_source_store.dart';
import 'package:reader_mobile/book_source/online_epub_metadata.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _sourceJson = '''
{
  "bookSourceName": "示例源",
  "bookSourceUrl": "https://example.com",
  "bookSourceType": 0,
  "customField": "保留",
  "searchUrl": "/search?q={{key}}",
  "ruleSearch": {
    "bookList": "div.book",
    "name": "a.title@text",
    "author": "span.author@text",
    "bookUrl": "a.title@href"
  },
  "ruleBookInfo": {"name": "h1@text", "tocUrl": "a#toc@href"},
  "ruleToc": {
    "chapterList": "ul li",
    "chapterName": "a@text",
    "chapterUrl": "a@href"
  },
  "ruleContent": {"content": "#content"}
}
''';

void main() {
  late Directory directory;
  late BookSourceStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('book-source-test-');
    store = BookSourceStore(directoryProvider: () async => directory);
  });

  tearDown(() async {
    store.dispose();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('导入 JSON 后重新读取，未知字段保留', () async {
    final source = await store.importText(_sourceJson);
    expect(source.name, '示例源');
    expect(source.id, startsWith('online_'));
    expect(source.canSearch, isTrue);
    expect(source.toJson()['customField'], '保留');

    final reader = BookSourceStore(directoryProvider: () async => directory);
    final reloaded = await reader.load();
    reader.dispose();
    expect(reloaded, hasLength(1));
    expect(reloaded.single.id, source.id);
    expect(reloaded.single.toJson()['customField'], '保留');
    expect(reloaded.single.toc.chapterList, 'ul li');
    expect(reloaded.single.loadMode, BookSourceLoadMode.chapter);
  });

  test('书源可以显式选择整本加载并持久化', () async {
    final source = await store.importText(
      _sourceJson.replaceFirst(
        '"bookSourceName": "示例源"',
        '"bookSourceName": "整本源", "loadMode": "book"',
      ),
    );
    expect(source.loadMode, BookSourceLoadMode.book);
    final json = source.toJson();
    expect(json['loadMode'], 'book');
  });

  test('重复导入保留启停状态', () async {
    final source = await store.importText(_sourceJson);
    await store.setEnabled(source.id, false);
    await store.setLoadMode(source.id, BookSourceLoadMode.book);

    await store.importText(_sourceJson);
    final reader = BookSourceStore(directoryProvider: () async => directory);
    final reloaded = await reader.load(refresh: true);
    reader.dispose();
    expect(reloaded.single.enabled, isFalse);
    expect(reloaded.single.loadMode, BookSourceLoadMode.book);
  });

  test('对象合集、字符串规则与 ZIP 数组统一识别且完整地址区分同站书源', () async {
    final first = jsonDecode(_sourceJson) as Map<String, dynamic>;
    first['searchUrl'] = '/search, {"method":"POST","body":"key={{key}}"}';
    first['ruleToc'] = jsonEncode(first['ruleToc']);
    final second = {...first, 'bookSourceUrl': 'https://example.com/other'};
    final archive = Archive();
    final content = utf8.encode(jsonEncode([first, second]));
    archive.addFile(ArchiveFile('sources.json', content.length, content));
    await store.importBytes(
      Uint8List.fromList(ZipEncoder().encodeBytes(archive)),
    );
    expect(store.lastImportedCount, 2);
    final loaded = await store.load(refresh: true);
    expect(loaded, hasLength(2));
    expect(loaded.first.searchOptions['method'], 'POST');
    expect(loaded.first.toc.chapterList, 'ul li');
    await store.importText(
      jsonEncode({
        'bookSources': [
          {...first, 'bookSourceUrl': 'https://EXAMPLE.com/'},
        ],
      }),
    );
    expect(await store.load(refresh: true), hasLength(2));
  });

  test('发现和已有书籍可使用无搜索源，data 正文与无效选项不误拆', () async {
    final json = jsonDecode(_sourceJson) as Map<String, dynamic>;
    json.remove('searchUrl');
    json.remove('ruleSearch');
    final source = await store.importText(jsonEncode(json));
    expect(source.canRead, isTrue);
    expect(source.canSearch, isFalse);
    const data = 'data:text/html,<p>原文,{"content":"内容"}</p>';
    expect(splitBookSourceUrlOptions(data).url, data);
    const jsonData = 'data:application/json,{"type":"正文","text":"100%+"}';
    expect(splitBookSourceUrlOptions(jsonData).url, jsonData);
    expect(splitBookSourceUrlOptions(jsonData).options, isEmpty);
    final encoded = splitBookSourceUrlOptions(
      'data:;base64,NzYwMDc4MzAzOTAwOTkxNTQxNw==, {"type":"novel"}',
    );
    expect(encoded.url, 'data:;base64,NzYwMDc4MzAzOTAwOTkxNTQxNw==');
    expect(encoded.options, {'type': 'novel'});
    expect(
      splitBookSourceUrlOptions('data:;base64,MTIz,{broken}').url,
      'data:;base64,MTIz,{broken}',
    );
    expect(splitBookSourceUrlOptions('/page,{broken}').url, '/page,{broken}');
  });

  test('Legado 导入链接解析远程合集，失败合集不改已有源或关联', () async {
    final networkStore = BookSourceStore(
      directoryProvider: () async => directory,
      client: MockClient((request) async {
        expect(request.url.toString(), 'https://example.test/sources.json');
        return http.Response(
          _sourceJson,
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(networkStore.dispose);
    final source = await networkStore.importText(
      'legado://import/bookSource?src=https%3A%2F%2Fexample.test%2Fsources.json',
    );
    await networkStore.saveLink(
      'book',
      OnlineBookLink(
        sourceId: source.id,
        bookUrl: 'https://example.com/book',
        name: '测试书',
        author: '作者',
      ),
    );
    final invalid = <String, Object?>{
      ...jsonDecode(_sourceJson) as Map<String, dynamic>,
      'bookSourceUrl': 'https://example.test/broken',
      'ruleContent': {},
    };
    await expectLater(
      networkStore.importText(
        jsonEncode([
          {
            ...jsonDecode(_sourceJson) as Map<String, dynamic>,
            'bookSourceName': '改名',
          },
          invalid,
        ]),
      ),
      throwsA(isA<BookSourceException>()),
    );
    expect((await networkStore.load(refresh: true)).single.name, source.name);
    expect((await networkStore.loadLinks())['book']?.sourceId, source.id);
    expect(stableBookSourceId('https://EXAMPLE.com/'), source.id);
    expect(
      stableBookSourceId('https://example.com/Book'),
      isNot(stableBookSourceId('https://example.com/book')),
    );
    final pathSource = source.copyWith(
      id: stableBookSourceId('https://example.com/Book'),
      sourceUrl: 'https://example.com/Book',
    );
    expect(
      OnlineEpubMetadata.findSource(legacyBookSourceId(pathSource.sourceUrl), [
        pathSource,
      ]),
      same(pathSource),
    );
  });

  test('书籍关联随配置持久化，删除书源时清理', () async {
    final source = await store.importText(_sourceJson);
    await store.saveLink(
      'book-1',
      OnlineBookLink(
        sourceId: source.id,
        bookUrl: 'https://example.com/book/1',
        name: '书名',
        author: '作者',
      ),
    );

    final other = BookSourceStore(directoryProvider: () async => directory);
    final links = await other.loadLinks();
    expect(links['book-1']?.sourceId, source.id);
    expect(links['book-1']?.updatedAt, isNotNull);
    other.dispose();

    await store.remove(source.id);
    expect(await store.loadLinks(), isEmpty);
  });

  test('多书源数组与损坏内容给出明确错误', () async {
    expect(
      () => store.importText('["{}", "{}"]'),
      throwsA(isA<BookSourceException>()),
    );
    expect(
      () => store.importText('not json'),
      throwsA(isA<BookSourceException>()),
    );
  });

  test('编译型压缩书源提示无法直接执行', () async {
    final manifest = utf8.encode('{"name":"编译书源"}');
    final archive = Archive()
      ..addFile(ArchiveFile('classes.dex', 4, <int>[0, 1, 2, 3]))
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest));
    final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(archive));
    expect(
      () => store.importBytes(bytes),
      throwsA(
        isA<BookSourceException>().having(
          (error) => error.message,
          'message',
          contains('无法直接执行'),
        ),
      ),
    );
  });
}
