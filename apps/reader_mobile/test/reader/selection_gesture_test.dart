import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/selection/selection_layer.dart';

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
  testWidgets('长按进入选词，拖拽手柄扩展选区，翻页清除（P4-15）', (tester) async {
    final source = await openTestChapterSource(_corpusBook('basic.epub'));
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
                bookId: 'selection-gesture',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SelectionLayer), findsNothing);

    // 长按正文区中央 → 选词。
    await tester.longPressAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionLayer), findsOneWidget);

    final before = tester.widget<SelectionLayer>(find.byType(SelectionLayer));
    expect(before.selection.isCollapsed, isFalse);

    // 拖拽终点手柄 → 选区变化。
    await tester.drag(
      find.byKey(const ValueKey<String>('selection-handle-end')),
      const Offset(30, 0),
    );
    await tester.pumpAndSettle();
    final after = tester.widget<SelectionLayer>(find.byType(SelectionLayer));
    expect(
      after.selection.end.charOffset != before.selection.end.charOffset ||
          after.selection.end.lineIndex != before.selection.end.lineIndex,
      isTrue,
      reason: '拖拽应改变选区终点',
    );

    // 翻页清除选区。
    await tester.tapAt(const Offset(320, 260)); // 右区 → 下一页
    await tester.pumpAndSettle();
    expect(find.byType(SelectionLayer), findsNothing);
  });
}
