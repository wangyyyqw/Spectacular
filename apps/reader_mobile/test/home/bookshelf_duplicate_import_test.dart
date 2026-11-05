import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/file_progress_store.dart';

import '../support/test_epub.dart';

void main() {
  testWidgets('固定ID拒绝重复导入后，提示准确且原书仍可见', (tester) async {
    final library = LibraryStore.memory();
    final bytes = buildTestEpub(title: '重复验收书', author: '作者');
    final book = await library.importBytes(bytes);
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: FileReaderProgressStore.memory(),
          pickEpubFiles: () async => ['副本.epub'],
          readFile: (_) async => bytes,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('导入 EPUB'));
    await tester.pumpAndSettle();
    // 文件选择提示结束后，显示排队的重复导入通知。
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(await library.list(), hasLength(1));
    expect(find.textContaining('这本书已在书架中'), findsOneWidget);
    expect(
      find.byKey(ValueKey<String>('book-card-${book.id}')),
      findsOneWidget,
    );
    expect(find.text('重试'), findsNothing);
    expect(find.textContaining('无法解析'), findsNothing);
  });
}
