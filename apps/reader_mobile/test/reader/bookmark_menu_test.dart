import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/library/revision_anchor_index.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

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

/// 菜单测试使用确定性存储，定位证据仍来自完整原 EPUB。
class _Bookmarks implements ReaderBookmarkStore {
  _Bookmarks(this.book);
  final AnchorBook book;
  final items = <ReaderBookmark>[];
  @override
  Future<List<ReaderBookmark>> list() async => List.of(items);
  @override
  Future<ReaderBookmark?> add({
    required String cfi,
    required int spineIndex,
    required String label,
  }) async {
    if (items.any((item) => item.cfi == cfi)) return null;
    final anchor = book.capture(cfi);
    expect(anchor, isNotNull, reason: '书签必须对应原 EPUB 的实际位置');
    final item = ReaderBookmark(
      id: '${items.length + 1}',
      cfi: cfi,
      spineIndex: spineIndex,
      label: label,
      createdAt: DateTime(2026),
      relocationStatus: 'verified',
      currentQuote: anchor!.start.quote,
    );
    items.add(item);
    return item;
  }

  @override
  Future<void> remove(String id) async =>
      items.removeWhere((item) => item.id == id);
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

    // 导入真实样书，菜单使用原 EPUB 的定位索引作为存储 fixture。
    final bytes = _corpusBook('toc-ncx.epub');
    late BookEntry book;
    await tester.runAsync(() async {
      book = await library.importBytes(bytes, fallbackTitle: 'toc-ncx');
    });
    final source = await openTestChapterSource(bytes);
    late _Bookmarks bookmarks;
    await tester.runAsync(() async {
      bookmarks = _Bookmarks(await buildRevisionAnchorBook(bytes));
    });
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
    await pumpReaderUntilComplete(
      tester,
      () => !session.loading && session.hasContent,
      description: '书签菜单首屏正文',
    );

    // 顶部菜单直接加书签。
    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-add-bookmark')));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);

    final saved = await bookmarks.list();
    expect(saved, hasLength(1));
    expect(saved.single.spineIndex, session.progress!.spineIndex);
    expect(saved.single.label, contains('第一章 旧纸'));
    expect(saved.single.label, contains('第 1 页'));
    expect(saved.single.label, contains(session.currentLineText));

    // 翻到下一章后再从书签列表跳回。
    await pumpReaderTask(tester, session.jumpToChapter(2));
    expect(session.progress!.spineIndex, 2);

    await tester.tap(find.byKey(const ValueKey<String>('menu-entry-toc')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('drawer-tab-bookmarks')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey<String>('bookmark-row-${saved.single.id}')),
    );
    await pumpReaderUntilComplete(
      tester,
      () =>
          !session.loading &&
          session.progress?.spineIndex == saved.single.spineIndex,
      description: '书签目标章正文',
    );
    expect(session.progress!.spineIndex, saved.single.spineIndex);
    await tester.pumpWidget(const SizedBox.shrink());
    source.close();
    await tester.pump();
  });
}
