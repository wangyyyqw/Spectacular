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
  testWidgets('切墨水屏：只重绘不重排，翻页位置不变（P4-23）', (tester) async {
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
                bookId: 'ink-mode',
                backgroundId: 'paper',
                inkMode: false,
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
      description: '墨水屏首屏正文',
    );
    final fingerprint = session.layoutFingerprint;
    final progress = session.progress;

    // 外部设置变化（书架持久化后回到阅读页的路径）：只重绘不重排。
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
                bookId: 'ink-mode',
                backgroundId: 'paper',
                inkMode: true,
                onSessionReady: (value) => session = value,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(session.layoutFingerprint, fingerprint, reason: '墨水屏不重排');
    expect(session.progress, progress);
    await tester.pumpWidget(const SizedBox.shrink());
    source.close();
    await tester.pump();
  });
}
