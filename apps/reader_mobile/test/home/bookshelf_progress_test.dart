import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/file_progress_store.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('书架按字符权重显示阅读进度（P4-09）', (tester) async {
    final dir = Directory.systemTemp.createTempSync('bookshelf-progress');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => dir,
    );
    final progressStore = FileReaderProgressStore.memory();

    late BookEntry entry;
    await tester.runAsync(() async {
      entry = await library.importBytes(buildTestEpub(title: '进度书'));
    });
    // 读到第 0 章第 2 页：单章书进度 0%，但状态应为在读。
    await library.touchLastRead(entry.id);
    await progressStore.save(
      entry.id,
      const ReaderProgress(spineIndex: 0, pageIndex: 2),
    );
    final weights = await library.progressWeights(entry.id);
    expect(weights.total, greaterThan(0), reason: '导入期已统计字符数');

    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: progressStore,
        ),
      ),
    );
    await _settle(tester, frames: 16);

    expect(find.textContaining('在读 0%'), findsOneWidget);
    await tester.tap(find.byTooltip('列表视图'));
    await _settle(tester);
    expect(
      tester
          .widget<Text>(
            find.byKey(ValueKey<String>('book-row-meta-${entry.id}')),
          )
          .data,
      '测试作者 · 在读 0%',
    );
  });
}
