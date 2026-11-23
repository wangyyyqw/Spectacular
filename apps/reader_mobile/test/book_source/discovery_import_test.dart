import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/book_source/book_source_store.dart';
import 'package:reader_mobile/book_source/online_book_controller.dart';
import 'package:reader_mobile/library/library_store.dart';

void main() {
  test('新增支持发现的书源才触发提示，导入其他源与重复导入不重复触发', () async {
    final dir = await Directory.systemTemp.createTemp('discovery-import-');
    addTearDown(() => dir.delete(recursive: true));
    final controller = OnlineBookController(
      library: LibraryStore.memory(),
      store: BookSourceStore(directoryProvider: () async => dir),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    String source(String id, {bool discover = false}) => jsonEncode({
      'bookSourceName': id,
      'bookSourceUrl': 'https://$id.test',
      'searchUrl': 'https://$id.test/search',
      'ruleSearch': {
        'bookList': 'article',
        'name': 'h1@text',
        'bookUrl': 'a@href',
      },
      if (discover) 'exploreUrl': 'https://$id.test/explore',
      'enabledExplore': true,
      'ruleContent': {'content': 'body'},
      'ruleToc': {
        'chapterList': 'a',
        'chapterName': 'text',
        'chapterUrl': 'href',
      },
    });
    await controller.importText(source('plain'));
    expect(controller.discoveryImportRevision, 0);
    await controller.importText(source('explore', discover: true));
    expect(controller.discoveryImportRevision, 1);
    await controller.importText(source('other'));
    await controller.importText(source('explore', discover: true));
    expect(controller.discoveryImportRevision, 1);
  });
}
