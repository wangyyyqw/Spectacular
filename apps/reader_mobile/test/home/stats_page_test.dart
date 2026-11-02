import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/position/locator.dart';
import 'package:reader_mobile/home/stats_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/file_progress_store.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

class _FakeLibrary extends LibraryStore {
  _FakeLibrary(this.books, this.weights) : super.memory();

  final List<BookEntry> books;
  final Map<String, ProgressWeights> weights;

  @override
  Future<List<BookEntry>> list() async => books;

  @override
  Future<ProgressWeights> progressWeights(String bookId) async =>
      weights[bookId] ?? ProgressWeights.fromCharCounts(const <int>[]);
}

class _FakeProgressStore implements ReaderProgressStore {
  _FakeProgressStore(this.items);

  final Map<String, ReaderProgress> items;

  @override
  Future<void> clear(String bookId) async {
    items.remove(bookId);
  }

  @override
  Future<ReaderProgress?> load(String bookId) async => items[bookId];

  @override
  Future<void> save(String bookId, ReaderProgress progress) async {
    items[bookId] = progress;
  }

  @override
  Future<Map<String, ReaderProgress>> snapshot() async =>
      Map<String, ReaderProgress>.unmodifiable(items);
}

BookEntry _book(
  String id,
  String title, {
  DateTime? lastReadAt,
  int? spineCount,
}) {
  return BookEntry(
    id: id,
    title: title,
    author: '',
    filePath: '',
    addedAt: DateTime(2026, 1, 1),
    lastReadAt: lastReadAt,
    spineCount: spineCount,
  );
}

void main() {
  testWidgets('统计页展示真实进度、近七日阅读和累计字数', (tester) async {
    final now = DateTime.now();
    final books = [
      _book(
        'a',
        '第一本',
        lastReadAt: now.subtract(const Duration(days: 1)),
        spineCount: 2,
      ),
      _book(
        'b',
        '第二本',
        lastReadAt: now.subtract(const Duration(days: 10)),
        spineCount: 2,
      ),
      _book('c', '第三本', spineCount: 2),
    ];
    final library = _FakeLibrary(books, {
      'a': ProgressWeights.fromCharCounts([60, 40]),
      'b': ProgressWeights.fromCharCounts([50, 50]),
      'c': ProgressWeights.fromCharCounts([25, 25]),
    });
    final progress = _FakeProgressStore({
      'a': const ReaderProgress(spineIndex: 1, pageIndex: 0),
      'b': const ReaderProgress(spineIndex: 0, pageIndex: 0),
    });

    await tester.pumpWidget(
      MaterialApp(
        home: StatsPage(library: library, progressStore: progress),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('stats-total-books')))
          .data,
      '3',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-recent-7-days')),
          )
          .data,
      '1',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-total-characters')),
          )
          .data,
      '250',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-average-progress')),
          )
          .data,
      '30%',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('stats-book-a')))
          .data,
      '60%',
    );
    expect(find.text('2 / 3 本已开始'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('stats-band-unread')))
          .data,
      '未开始 1 本',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('stats-band-early')))
          .data,
      '0-25% 1 本',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('stats-band-advanced')),
          )
          .data,
      '51-75% 1 本',
    );
  });

  testWidgets('点击最近阅读卡片可直接续读', (tester) async {
    final library = LibraryStore.memory();
    late BookEntry entry;
    await tester.runAsync(() async {
      entry = await library.importBytes(buildTestEpub(title: '续读书'));
      await library.touchLastRead(entry.id);
    });
    final progress = FileReaderProgressStore.memory();
    await progress.save(
      entry.id,
      const ReaderProgress(spineIndex: 0, pageIndex: 0),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StatsPage(library: library, progressStore: progress),
      ),
    );
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Hero && widget.tag == bookCoverHeroTag(entry.id),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(ValueKey<String>('stats-open-${entry.id}')));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byKey(const ValueKey<String>('reader-page')), findsOneWidget);
  });
}
