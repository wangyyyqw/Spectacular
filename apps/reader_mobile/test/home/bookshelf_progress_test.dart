import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/book_source/online_epub_builder.dart';
import 'package:reader_mobile/storage/db.dart';
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
  testWidgets('列表分行显示作者、有效阅读时长和已读章节', (tester) async {
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
      entry = await library.importBytes(
        buildMultiChapterEpub(title: '进度书', chapters: ['甲', '乙', '丙']),
      );
      final other = await library.importBytes(buildTestEpub(title: '其他书'));
      final sessions = library.readingSessionStore()!;
      final start = DateTime(2026, 11, 21, 10);
      for (final (bookId, minutes) in [
        (entry.id, 60),
        (entry.id, 15),
        (entry.id, 1),
        (other.id, 90),
      ]) {
        await sessions.add(
          bookId: bookId,
          startedAt: start,
          endedAt: start.add(Duration(minutes: minutes)),
        );
      }
    });
    await library.touchLastRead(entry.id);
    final progressStore = _TrackingProgressStore(<String, ReaderProgress>{});
    await progressStore.save(
      entry.id,
      const ReaderProgress(spineIndex: 1, pageIndex: 2, readingPercent: 0.5),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(library: library, progressStore: progressStore),
      ),
    );
    await _settle(tester, frames: 16);

    expect(find.text('已读 1 小时 16 分'), findsNothing);
    expect(find.text('已读 2 / 3 章'), findsNothing);
    expect(progressStore.loads, 0, reason: '书架应一次读取全部进度');
    expect(progressStore.snapshots, 1);
    await tester.tap(find.byTooltip('列表视图'));
    await _settle(tester);
    final row = find.byKey(ValueKey('book-row-${entry.id}'));
    Finder line(String label) =>
        find.descendant(of: row, matching: find.text(label));
    final author = tester.getRect(line('未知作者'));
    final duration = tester.getRect(line('已读 1 小时 16 分'));
    final chapters = tester.getRect(line('已读 2 / 3 章'));
    expect(author.bottom, lessThanOrEqualTo(duration.top));
    expect(duration.bottom, lessThanOrEqualTo(chapters.top));
    expect(find.textContaining('50%'), findsNothing);
    expect(find.text('已读 0 / 1 章'), findsOneWidget);
  });

  testWidgets('已读完的书回翻后列表显示当前章节与累计时长', (tester) async {
    final dir = Directory.systemTemp.createTempSync('bookshelf-finished');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => dir,
    );
    final progressStore = MemoryReaderProgressStore();

    late BookEntry entry;
    await tester.runAsync(() async {
      entry = await library.importBytes(
        buildMultiChapterEpub(title: '读完书', chapters: ['甲', '乙']),
      );
      await library.touchLastRead(entry.id);
    });
    await progressStore.save(
      entry.id,
      const ReaderProgress(
        spineIndex: 0,
        pageIndex: 0,
        finished: true,
        readingPercent: 0.375,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(library: library, progressStore: progressStore),
      ),
    );
    await _settle(tester, frames: 16);

    await tester.pump();
    await tester.tap(find.byTooltip('列表视图'));
    await _settle(tester);
    expect(find.text('已读 1 / 2 章'), findsOneWidget);
    expect(find.text('已读 0 分钟'), findsOneWidget);
  });

  testWidgets('在线书架章节进度忽略封面 spine 并读取在线读完状态', (tester) async {
    final library = LibraryStore.memory();
    late BookEntry entry;
    await tester.runAsync(() async {
      entry = await library.importBytes(
        const OnlineEpubBuilder().build(
          OnlineEpubInput(
            title: '在线进度书',
            author: '作者',
            sourceName: '测试源',
            bookUrl: 'https://example.test/book',
            sourceId: 'test-source',
            chapters: const [
              OnlineEpubChapter(
                title: '第一章',
                html: '正文一',
                sourceUrl: 'https://example.test/1',
              ),
              OnlineEpubChapter(
                title: '第二章',
                html: '正文二',
                sourceUrl: 'https://example.test/2',
              ),
              OnlineEpubChapter(
                title: '第三章',
                html: '正文三',
                sourceUrl: 'https://example.test/3',
              ),
            ],
          ),
        ),
      );
      await library.setSetting(
        'online_reading_progress:${entry.id}',
        '{"spine":2,"chapterIdentity":"${entry.id}","finished":true}',
      );
    });
    final sourceIdentity = '';
    await library.setSetting(
      'online_reading_progress:${entry.id}',
      '{"spine":1,"chapterIdentity":"$sourceIdentity","finished":true}',
    );
    await library.setSetting('bookshelf.grid', 'false');

    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await _settle(tester, frames: 16);

    expect(find.text('在线进度书'), findsOneWidget);
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
