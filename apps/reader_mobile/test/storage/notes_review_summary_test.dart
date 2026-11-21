import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/reading_insights.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_ui/annotations/annotation.dart';

import '../support/test_epub.dart';

void main() {
  late Directory dir;
  late AppDatabase db;
  late LibraryStore library;
  late BookEntry noted;
  late BookEntry untouched;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('notes-review-summary');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryStore(database: db, directoryProvider: () async => dir);
    noted = await library.importBytes(
      buildTestEpub(title: '有笔记的书', identifier: 'notes-summary'),
    );
    untouched = await library.importBytes(
      buildTestEpub(title: '没有笔记的书', identifier: 'notes-empty'),
    );
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('按书汇总想法和划线，排除书签、空书和已移出书架的书', () async {
    final annotations = library.annotationStore(noted.id)!;
    await annotations.add(
      type: ReaderAnnotationType.thought,
      startCfi: 'epubcfi(/6/2!/4/2/1:0)',
      endCfi: 'epubcfi(/6/2!/4/2/1:4)',
      quote: '写下想法',
      note: '这是一条想法。',
    );
    await annotations.add(
      type: ReaderAnnotationType.mark,
      startCfi: 'epubcfi(/6/2!/4/4/1:0)',
      endCfi: 'epubcfi(/6/2!/4/4/1:5)',
      quote: '一条划线',
    );
    await library
        .bookmarkStore(noted.id)!
        .add(cfi: 'epubcfi(/6/2!/4/6/1:0)', spineIndex: 1, label: '书签不算笔记');

    var counts = await library.bookNoteCounts();
    expect(counts.keys, [noted.id]);
    expect(counts[noted.id]!.thoughts, 1);
    expect(counts[noted.id]!.marks, 1);

    await library.remove(noted.id);
    counts = await library.bookNoteCounts();
    expect(counts, isEmpty);
  });

  test('票根时长累计短于五分钟的有效阅读片段', () async {
    final sessions = library.readingSessionStore()!;
    final start = DateTime(2026, 11, 18, 9);
    await sessions.add(
      bookId: noted.id,
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 5)),
    );
    await sessions.add(
      bookId: noted.id,
      startedAt: start.add(const Duration(hours: 1)),
      endedAt: start.add(const Duration(hours: 1, minutes: 4, seconds: 59)),
    );
    await sessions.add(
      bookId: noted.id,
      startedAt: start.add(const Duration(hours: 2)),
      endedAt: start.add(const Duration(hours: 2, minutes: 10)),
    );
    await sessions.add(
      bookId: untouched.id,
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 2)),
    );

    final durations = await library.bookReadingDurations(
      minimumCountedSessionDuration,
    );
    expect(durations, {
      noted.id: const Duration(minutes: 19, seconds: 59),
      untouched.id: const Duration(minutes: 2),
    });
  });
}
