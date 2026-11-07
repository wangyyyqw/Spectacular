import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

/// 找 test_corpus 样书（有真实目录）。
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
  testWidgets('点中央打开菜单 → 目录 → 点击章节跳转（P4-11）', (tester) async {
    final source = await openTestChapterSource(_corpusBook('toc-ncx.epub'));
    final store = MemoryReaderProgressStore();
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
                store: store,
                bookId: 'toc-nav',
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
      description: '目录首屏正文',
    );
    expect(session.toc, isNotEmpty, reason: '样书应有目录');

    // 点阅读区中央打开菜单（用控件实际中心，避免 SizedBox 溢出边界）。
    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    expect(find.text('目录'), findsOneWidget);

    // 进目录面板。
    await tester.tap(find.text('目录'));
    await tester.pumpAndSettle();
    expect(find.textContaining('共 '), findsOneWidget);

    // 点一个非当前章。
    final target = session.toc.last;
    final before = session.progress?.spineIndex;
    await tester.tap(find.text(target.title).last);
    await pumpReaderUntilComplete(
      tester,
      () =>
          !session.loading && session.progress?.spineIndex == target.spineIndex,
      description: '目录目标章正文',
    );

    expect(session.progress?.spineIndex, target.spineIndex);
    expect(session.progress?.spineIndex, isNot(before), reason: '应跳到目标章');
    await tester.pumpWidget(const SizedBox.shrink());
    source.close();
    await tester.pump();
  });
}
