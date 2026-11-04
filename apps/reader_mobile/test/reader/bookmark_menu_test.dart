import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

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
  testWidgets('菜单里添加书签、打开书签列表并跳转（P4-13）', (tester) async {
    final dir = Directory.systemTemp.createTempSync('bookmark-menu');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => dir,
    );

    // 样书走内存字节打开（不落盘），书签存储挂真实数据库。
    final bytes = _corpusBook('toc-ncx.epub');
    late BookEntry book;
    await tester.runAsync(() async {
      book = await library.importBytes(bytes, fallbackTitle: 'toc-ncx');
    });
    final source = await openTestChapterSource(bytes);
    final bookmarks = library.bookmarkStore(book.id)!;
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
                bookId: book.id,
                bookmarks: bookmarks,
                onSessionReady: (value) => session = value,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 打开菜单 → 目录抽屉 → 「加书签」。
    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-entry-toc')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('drawer-add-bookmark')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('drawer-add-bookmark')));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(find.text('已添加书签'), findsOneWidget);

    final saved = await bookmarks.list();
    expect(saved, hasLength(1));
    expect(saved.single.spineIndex, session.progress!.spineIndex);
    expect(saved.single.label, contains('第一章 旧纸'));
    expect(saved.single.label, contains('第 1 页'));
    expect(saved.single.label, contains(session.currentLineText));

    // 翻到下一章后再从书签列表跳回。
    await session.jumpToChapter(2);
    await tester.pumpAndSettle();
    expect(session.progress!.spineIndex, 2);

    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-entry-toc')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('drawer-tab-bookmarks')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('共 1 条'), findsOneWidget);
    await tester.tap(find.text(saved.single.label));
    await tester.pumpAndSettle();
    expect(session.progress!.spineIndex, saved.single.spineIndex);
  });
}
