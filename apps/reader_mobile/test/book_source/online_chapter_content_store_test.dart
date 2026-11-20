import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/book_source/online_chapter_content_store.dart';

void main() {
  test('章节正文缓存可读写且规则指纹隔离', () async {
    final directory = await Directory.systemTemp.createTemp('chapter-cache-');
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final store = OnlineChapterContentStore(directoryProvider: () async => directory);
    const args = <String, String>{
      'sourceId': 'source',
      'bookUrl': 'https://example.test/book',
      'chapterUrl': 'https://example.test/chapter/1',
    };
    expect(
      await store.read(
        sourceId: args['sourceId']!,
        bookUrl: args['bookUrl']!,
        chapterUrl: args['chapterUrl']!,
        rulesFingerprint: 'v1',
      ),
      isNull,
    );
    await store.write(
      sourceId: args['sourceId']!,
      bookUrl: args['bookUrl']!,
      chapterUrl: args['chapterUrl']!,
      rulesFingerprint: 'v1',
      content: '<p>正文</p>',
    );
    expect(
      await store.read(
        sourceId: args['sourceId']!,
        bookUrl: args['bookUrl']!,
        chapterUrl: args['chapterUrl']!,
        rulesFingerprint: 'v1',
      ),
      '<p>正文</p>',
    );
    expect(
      await store.read(
        sourceId: args['sourceId']!,
        bookUrl: args['bookUrl']!,
        chapterUrl: args['chapterUrl']!,
        rulesFingerprint: 'v2',
      ),
      isNull,
    );
  });
}
