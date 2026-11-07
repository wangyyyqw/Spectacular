import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

Uint8List _corpusBook(String name) {
  var directory = Directory.current;
  while (true) {
    final candidate = Directory('${directory.path}/test_corpus');
    if (candidate.existsSync()) {
      return File('${candidate.path}/$name').readAsBytesSync();
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('缺少 test_corpus/$name');
    }
    directory = parent;
  }
}

void main() {
  testWidgets('翻页后焦点落到新页首块，连续翻页不跳段（P4-28）', (tester) async {
    final source = await openTestChapterSource(_corpusBook('basic.epub'));
    late ReaderSession session;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 520,
              child: ReaderPage(
                source: source,
                store: MemoryReaderProgressStore(),
                bookId: 'semantics-focus',
                onSessionReady: (value) => session = value,
              ),
            ),
          ),
        ),
      ),
    );
    await pumpReaderUntilComplete(
      tester,
      () => !session.loading && session.hasContent,
      description: '读屏首屏正文',
    );

    // 首页聚焦后落在首块。
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'reader-first-block',
    );

    // 连续翻三页：每页焦点都回到新页首块（读屏续读不跳段）。
    for (var i = 0; i < 3; i++) {
      await pumpReaderTask(tester, session.next());
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'reader-first-block',
        reason: '第 ${i + 2} 页焦点在首块',
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    source.close();
    await tester.pump();
  });
}
