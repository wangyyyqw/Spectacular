import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader_mobile/dictionary/local_dictionary_store.dart';
import 'package:reader_mobile/dictionary/local_dictionary_view.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';

import '../test/dictionary/mdict_fixture.dart';

class _ObservedSession extends LocalDictionarySession {
  _ObservedSession(this.delegate) : super(delegate.entry, delegate.directory);
  final LocalDictionarySession delegate;
  final paths = <String>[];
  @override
  Future<Uint8List?> resource(String path) {
    paths.add(path);
    return delegate.resource(path);
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('原生词典网页加载超时');
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('原生 WebView 加载离线释义以及 MDD 图片和样式', (tester) async {
    final directory = await Directory.systemTemp.createTemp(
      'native_dictionary_',
    );
    final mdx = await createMdictFixture(
      directory,
      entries: [
        (
          'hello',
          utf8.encode(
            '<link rel="stylesheet" href="style.css">'
            '<a href="entry://help">帮助</a><br><b class="word">你好，离线词典</b>'
            '<img src="image.png" alt="离线图片">',
          ),
        ),
        ('help', utf8.encode('帮助释义')),
      ],
    );
    final mdd = await createMdictFixture(
      directory,
      filename: '测试词典.mdd',
      entries: [
        (r'\style.css', utf8.encode('.word{color:#345678}')),
        (
          r'\image.png',
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl1sAAAAASUVORK5CYII=',
          ),
        ),
      ],
    );
    final store = LocalDictionaryStore(
      LibraryStore.memory(),
      directoryProvider: () async => directory,
    );
    final entry = await store.importFiles([mdx.path, mdd.path]);
    final session = await store.open(entry);
    final observed = _ObservedSession(session);
    addTearDown(() async {
      await session.close();
      await directory.delete(recursive: true);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 360,
              child: LocalDictionaryView(
                session: observed,
                definition: (await session.lookup('hello'))!,
                onLookup: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await _until(
      tester,
      () =>
          observed.paths.contains('image.png') &&
          observed.paths.contains('style.css') &&
          find
              .byKey(const ValueKey('dictionary-local-loading'))
              .evaluate()
              .isEmpty,
    );
    expect(find.text('本地释义显示失败，请重新查询'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
