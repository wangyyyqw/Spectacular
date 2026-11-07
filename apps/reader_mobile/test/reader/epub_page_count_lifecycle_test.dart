import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_mobile/reader/epub/book_page_counter.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_ui/page_furniture/page_furniture.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_view.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

class _GatedCountStore implements BookPageCountStore {
  _GatedCountStore(this.persistent);

  final BookPageCountStore persistent;
  Completer<void>? gate;
  int waitingSaves = 0;

  @override
  Future<Map<int, int>> load(String layoutKey) => persistent.load(layoutKey);

  @override
  Future<void> save(String layoutKey, Map<int, int> counts) async {
    final pending = gate;
    if (pending != null) {
      waitingSaves += 1;
      try {
        await pending.future;
      } finally {
        waitingSaves -= 1;
      }
    }
    await persistent.save(layoutKey, counts);
  }
}

class _GatedProgressStore extends DriftProgressStore {
  _GatedProgressStore(super.db);

  late _GatedCountStore counts;
  String? boundBook;
  String? boundRevision;

  @override
  BookPageCountStore pageCountStore(String bookId, String contentRevision) {
    boundBook = bookId;
    boundRevision = contentRevision;
    return counts = _GatedCountStore(
      super.pageCountStore(bookId, contentRevision),
    );
  }
}

class _LifecycleFixture {
  _LifecycleFixture(this.db, this.source, this.revision)
    : store = _GatedProgressStore(db);

  static const bookId = 'lifecycle-page-count';
  final AppDatabase db;
  final EpubChapterSource source;
  final String revision;
  final _GatedProgressStore store;
  final closed = Completer<void>();
  int closeNotifications = 0;

  void didClose() {
    closeNotifications += 1;
    closed.complete();
  }
}

Future<({File file, String revision})> _bookFile(WidgetTester tester) async {
  final bytes = buildTestEpub(
    title: '计页生命周期',
    paragraphs: List.generate(18, (index) => '第 $index 段。${'退出保留原始内容位置。' * 8}'),
  );
  final directory = await tester.runAsync(
    () => Directory.systemTemp.createTemp('epub-page-count-lifecycle-'),
  );
  addTearDown(() => directory!.delete(recursive: true));
  final file = File('${directory!.path}/book.epub');
  await tester.runAsync(() => file.writeAsBytes(bytes));
  return (file: file, revision: sha256.convert(bytes).toString());
}

Future<_LifecycleFixture> _openReader(WidgetTester tester) async {
  final book = await _bookFile(tester);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await db
      .into(db.books)
      .insert(
        BooksCompanion.insert(
          uuid: _LifecycleFixture.bookId,
          title: '计页生命周期',
          contentDir: '',
          sourcePath: Value(book.file.path),
          contentRevision: Value(book.revision),
          spineCount: const Value(1),
          createdAt: 1,
        ),
      );
  final source = await tester.runAsync(
    () => EpubChapterSource.openFile(book.file, verifyCrc: false),
  );
  addTearDown(source!.close);
  addTearDown(
    () => tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    ),
  );
  final fixture = _LifecycleFixture(db, source, book.revision);
  await tester.pumpWidget(
    MaterialApp(
      home: EpubReaderPage(
        sourcePath: book.file.path,
        sourceFuture: Future.value(source),
        contentRevision: book.revision,
        bookId: _LifecycleFixture.bookId,
        store: fixture.store,
        onClosed: fixture.didClose,
      ),
    ),
  );
  return fixture;
}

Future<void> _turnPage(WidgetTester tester, _LifecycleFixture fixture) async {
  await pumpReaderUntil(tester, find.byType(ReaderPageFooter));
  await tester.pumpAndSettle();
  expect(find.byType(ReaderPage), findsOneWidget);
  expect(fixture.store.boundBook, _LifecycleFixture.bookId);
  expect(fixture.store.boundRevision, fixture.revision);
  final view = tester.getRect(find.byType(ReaderView));
  await tester.tapAt(view.topRight + Offset(-4, view.height * 0.4));
  await tester.pumpAndSettle();
  final layouts = fixture.source.chapterLayoutCount;
  tester.binding.handleMemoryPressure();
  await tester.pump();
  expect(fixture.source.chapterLayoutCount, layouts);
  expect(find.byType(ReaderPageFooter), findsWidgets);
  final state = fixture.source.pageCountState.value;
  expect(state.completedChapters, 1);
  expect(state.completedPages, greaterThan(0));
  expect(state.isComplete, isTrue);
}

Future<void> _closeReader(
  WidgetTester tester,
  _LifecycleFixture fixture,
  bool background,
) async {
  final gate = Completer<void>();
  fixture.store.counts.gate = gate;
  if (background) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(fixture.store.counts.waitingSaves, greaterThan(0));
  }
  await tester.pumpWidget(const SizedBox());
  // paused 会停用普通帧；强制交付卸载帧才能实际执行 dispose。
  if (background) tester.binding.scheduleForcedFrame();
  await tester.pump();
  expect(find.byType(EpubReaderPage), findsNothing);
  expect(fixture.store.counts.waitingSaves, greaterThan(0));
  expect(fixture.source.isClosed, isFalse, reason: '计页写入尚未完成，退出不能释放归档');
  expect(fixture.closed.isCompleted, isFalse);

  gate.complete();
  await pumpReaderUntilComplete(
    tester,
    () => fixture.closed.isCompleted,
    description: '退出落盘与源释放',
  );
  expect(fixture.source.isClosed, isTrue);
  expect(fixture.closeNotifications, 1);
}

Future<void> _expectStored(
  WidgetTester tester,
  _LifecycleFixture fixture,
  String layoutKey,
  int pageCount,
) async {
  expect(await fixture.store.counts.persistent.load(layoutKey), {0: pageCount});
  final saved = await tester.runAsync(
    () => fixture.store.load(_LifecycleFixture.bookId),
  );
  expect(saved?.cfi, startsWith('epubcfi('));
  expect(saved?.contentRevision, fixture.revision);
  expect(saved?.readingPercent, isNotNull);
  final row = await fixture.db.select(fixture.db.readingProgress).getSingle();
  // 原始块 CFI 可以省略零偏移，原文锚点会明确保存 :0，二者位置必须一致。
  expect(cfiBase(row.locatorCfi), cfiBase(saved!.cfi!));
  expect(cfiCharOffset(row.locatorCfi) ?? 0, cfiCharOffset(saved.cfi!) ?? 0);
  expect(tester.takeException(), isNull);
}

void main() {
  for (final background in [false, true]) {
    testWidgets(
      background ? '退后台等待计页写入，随后退出继续等待同一落盘队列' : '退出等待计页与原始 CFI 落盘后才释放源',
      (tester) async {
        final fixture = await _openReader(tester);
        await _turnPage(tester, fixture);
        final state = fixture.source.pageCountState.value;
        await _closeReader(tester, fixture, background);
        await _expectStored(
          tester,
          fixture,
          state.layoutKey,
          state.completedPages,
        );
      },
    );
  }
}
