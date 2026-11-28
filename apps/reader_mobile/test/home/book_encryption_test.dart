import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_detail_page.dart';
import 'package:reader_mobile/home/book_encryption_tile.dart';
import 'package:reader_mobile/library/library_store.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

class _RetryLibrary extends LibraryStore {
  _RetryLibrary() : super.memory();

  bool failing = true;

  @override
  Future<Uint8List> readBytes(BookEntry entry) async {
    if (failing) throw StateError('测试读取失败');
    return super.readBytes(entry);
  }
}

void main() {
  testWidgets('从图书详情发起检测，显示结果且不改书籍与资料', (tester) async {
    final library = LibraryStore.memory();
    final bytes = buildTestEpub(title: '加密检测入口');
    final entry = await library.importBytes(bytes);
    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailPage(entry: entry, library: library),
      ),
    );
    final tile = find.byKey(const ValueKey('book-encryption-check'));
    await pumpReaderUntil(tester, tile);
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    expect(find.text('检测'), findsOneWidget);
    await tester.tap(find.text('检测'));
    await pumpReaderUntil(tester, find.textContaining('未发现加密'));
    expect(find.text('重新检测'), findsOneWidget);
    expect(await library.readBytes(entry), bytes);
    expect((await library.bookById(entry.id))?.title, entry.title);
    expect(
      (await library.bookById(entry.id))?.contentRevision,
      entry.contentRevision,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('读取失败不显示未加密，窄窗大字可重试', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final library = _RetryLibrary();
    final entry = await library.importBytes(buildTestEpub());
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: BookEncryptionTile(entry: entry, library: library),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('检测'));
    await pumpReaderUntil(tester, find.text('检测失败，请重试'));
    expect(find.textContaining('未发现加密'), findsNothing);
    library.failing = false;
    await tester.tap(find.text('重新检测'));
    await pumpReaderUntil(tester, find.textContaining('未发现加密'));
    expect(tester.takeException(), isNull);
  });
}
