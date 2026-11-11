import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';

import '../support/test_epub.dart';

import 'package:reader_ui/reader_session.dart';

void main() {
  testWidgets('相同文件导入提示内容未变化且原书仍可见', (tester) async {
    final library = LibraryStore.memory();
    final bytes = buildTestEpub(title: '重复验收书', author: '作者');
    final book = await library.importBytes(bytes);
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
          pickEpubFiles: () async => ['副本.epub'],
          readFile: (_) async => bytes,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('导入 EPUB'));
    await tester.pumpAndSettle();
    // 文件选择提示结束后，显示排队的内容未变化通知。
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(await library.list(), hasLength(1));
    expect(find.text('书籍内容未变化'), findsOneWidget);
    expect(
      find.byKey(ValueKey<String>('book-card-${book.id}')),
      findsOneWidget,
    );
    expect(find.text('重试'), findsNothing);
    expect(find.textContaining('无法解析'), findsNothing);
  });
}
