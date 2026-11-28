import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/diagnostics/reader_log.dart';

import '../support/test_epub.dart';

import 'package:reader_ui/reader_session.dart';

void main() {
  testWidgets('相同文件导入记录完成诊断且原书仍可见', (tester) async {
    ReaderLog.instance.resetForTest();
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
    await tester.tap(find.byTooltip('导入 EPUB / TXT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从本机导入'));
    await tester.pumpAndSettle();
    // 导入完成反馈按应用约定记录诊断，不显示浮动提示。
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(await library.list(), hasLength(1));
    expect(
      await ReaderLog.instance.exportText(),
      contains('book_import_completed'),
    );
    expect(
      find.byKey(ValueKey<String>('book-card-${book.id}')),
      findsOneWidget,
    );
    expect(find.text('重试'), findsNothing);
    expect(find.textContaining('无法解析'), findsNothing);
  });
}
