import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/annotations/annotation.dart';
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
  testWidgets('拖终点手柄到页底自动翻页，选区跨页（P4-19）', (tester) async {
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
                bookId: 'cross-page',
                onSessionReady: (value) => session = value,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPressAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    final before = tester.widget<SelectionLayer>(find.byType(SelectionLayer));
    expect(before.selection.isMultiPage, isFalse);
    final startPage = session.progress!.pageIndex;

    // 触发边缘翻页（等价于拖终点手柄到页底）→ 300ms 后翻页并扩展选区。
    tester.widget<SelectionLayer>(find.byType(SelectionLayer)).onEdgeDrag!(true);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final after = tester.widget<SelectionLayer>(find.byType(SelectionLayer));
    expect(
      after.selection.isMultiPage,
      isTrue,
      reason: '拖到页边应翻页并扩展选区',
    );
    expect(after.selection.startPageIndex, startPage);
    expect(
      after.selection.endPageIndex,
      session.progress!.pageIndex,
      reason: '终点落在新页',
    );
    expect(after.selection.endPageIndex, greaterThan(after.selection.startPageIndex));
  });

  testWidgets('跨页选区仍可复制（文本按页拼接）', (tester) async {
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
                bookId: 'cross-page-copy',
                annotations: _NoopAnnotationStore(),
                onSessionReady: (value) => session = value,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPressAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();

    tester.widget<SelectionLayer>(find.byType(SelectionLayer)).onEdgeDrag!(true);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final layer = tester.widget<SelectionLayer>(find.byType(SelectionLayer));
    expect(layer.selection.isMultiPage, isTrue);

    final pages = await session.chapterPages();
    expect(pages, isNotEmpty);
  });
}

class _NoopAnnotationStore implements ReaderAnnotationStore {
  @override
  Future<List<ReaderAnnotation>> list() async => const <ReaderAnnotation>[];

  @override
  Future<ReaderAnnotation?> add({
    required ReaderAnnotationType type,
    required String startCfi,
    required String endCfi,
    required String quote,
    String? contextBefore,
    String? contextAfter,
    int? color,
    ReaderAnnotationStyle style = ReaderAnnotationStyle.background,
    String? note,
  }) async => null;

  @override
  Future<void> update(
    String id, {
    int? color,
    ReaderAnnotationStyle? style,
    String? note,
  }) async {}

  @override
  Future<void> remove(String id) async {}
}
