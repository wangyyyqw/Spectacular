import 'dart:async';
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

class _TrackingProgressStore implements ReaderProgressStore {
  _TrackingProgressStore(this.items);

  final Map<String, ReaderProgress> items;
  int loads = 0;
  int snapshots = 0;

  @override
  Future<ReaderProgress?> load(String bookId) async {
    loads += 1;
    return items[bookId];
  }

  @override
  Future<void> save(String bookId, ReaderProgress progress) async {
    items[bookId] = progress;
  }

  @override
  Future<void> clear(String bookId) async {
    items.remove(bookId);
  }

  @override
  Future<Map<String, ReaderProgress>> snapshot() async {
    snapshots += 1;
    return Map<String, ReaderProgress>.of(items);
  }
}

class _GatedLibraryStore extends LibraryStore {
  _GatedLibraryStore() : super.memory();

  Completer<void>? gate;
  int listCalls = 0;
  String? entryId;

  @override
  Future<List<BookEntry>> list() async {
    listCalls += 1;
    await gate?.future;
    return super.list();
  }

  void notifyShelf() => unawaited(touchLastRead(entryId!));
}

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

    late BookEntry entry;
    await tester.runAsync(() async {
      entry = await library.importBytes(buildTestEpub(title: '进度书'));
    });
    // 读到第 0 章第 2 页：单章书进度 0%，但状态应为在读。
    await library.touchLastRead(entry.id);
    final progressStore = _TrackingProgressStore(<String, ReaderProgress>{});
    await progressStore.save(
      entry.id,
      const ReaderProgress(spineIndex: 0, pageIndex: 2),
    );
    final weights = await library.progressWeights(entry.id);
    expect(weights.total, greaterThan(0), reason: '导入期已统计字符数');

    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(library: library, progressStore: progressStore),
      ),
    );
    await _settle(tester, frames: 16);

    expect(find.textContaining('在读 0%'), findsOneWidget);
    expect(progressStore.loads, 0, reason: '书架应一次读取全部进度');
    expect(progressStore.snapshots, 1);
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

  testWidgets('到达全书末页后书架显示已读完状态', (tester) async {
    final dir = Directory.systemTemp.createTempSync('bookshelf-finished');
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
      entry = await library.importBytes(buildTestEpub(title: '读完书'));
      await library.touchLastRead(entry.id);
    });
    await progressStore.save(
      entry.id,
      const ReaderProgress(spineIndex: 0, pageIndex: 0, finished: true),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(library: library, progressStore: progressStore),
      ),
    );
    await _settle(tester, frames: 16);

    expect(
      find.byKey(const ValueKey<String>('book-reading-badge')),
      findsOneWidget,
    );
    expect(find.text('已读完'), findsWidgets);

    await tester.pump();
    await tester.tap(find.byTooltip('列表视图'));
    await _settle(tester);
    expect(
      tester
          .widget<Text>(
            find.byKey(ValueKey<String>('book-row-meta-${entry.id}')),
          )
          .data,
      '测试作者 · 已读完',
    );
  });

  testWidgets('刷新进行中连续通知只追加一次最终刷新', (tester) async {
    final library = _GatedLibraryStore();
    final entry = await library.importBytes(buildTestEpub(title: '刷新合并'));
    library.entryId = entry.id;
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await _settle(tester);
    final initialCalls = library.listCalls;

    library.gate = Completer<void>();
    library
      ..notifyShelf()
      ..notifyShelf()
      ..notifyShelf();
    await tester.pump();
    expect(library.listCalls, initialCalls + 1);

    library.notifyShelf();
    await tester.pump();
    expect(library.listCalls, initialCalls + 1, reason: '在途刷新期间不并行启动');

    library.gate!.complete();
    library.gate = null;
    await _settle(tester);
    expect(library.listCalls, initialCalls + 2, reason: '只补一次最终状态');
  });
}
