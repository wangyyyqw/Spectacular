import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/annotations/annotation_layer.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/selection/selection_layer.dart';

import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';

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
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('选区菜单高亮写入标注库（P4-17）', (tester) async {
    final dir = Directory.systemTemp.createTempSync('annotation-menu');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => dir,
    );
    final bytes = _corpusBook('basic.epub');
    late BookEntry book;
    await tester.runAsync(() async {
      book = await library.importBytes(bytes, fallbackTitle: 'basic');
    });
    final source = await openTestChapterSource(bytes);
    final annotations = library.annotationStore(book.id)!;

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
                annotations: annotations,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPressAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionLayer), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('selection-action-highlight')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('selection-action-highlight')),
    );
    await tester.pumpAndSettle();
    expect(find.text('已高亮'), findsOneWidget);
    expect(find.byType(SelectionLayer), findsNothing, reason: '保存后清除选区');

    final saved = await annotations.list();
    expect(saved, hasLength(1));
    final item = saved.single;
    expect(item.type, ReaderAnnotationType.highlight);
    expect(item.startCfi, contains('epubcfi('));
    expect(item.endCfi, contains('epubcfi('));
    expect(item.quote, isNotEmpty);
    expect(item.color, 0xFFFFEB3B);
    expect(
      find.byType(AnnotationLayer),
      findsOneWidget,
      reason: '保存后页面出现标注装饰层（P4-18）',
    );
  });

  testWidgets('同一区间重复高亮提示已存在（P4-17）', (tester) async {
    final dir = Directory.systemTemp.createTempSync('annotation-dup');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => dir,
    );
    final bytes = _corpusBook('basic.epub');
    late BookEntry book;
    await tester.runAsync(() async {
      book = await library.importBytes(bytes, fallbackTitle: 'basic');
    });
    final source = await openTestChapterSource(bytes);
    final annotations = library.annotationStore(book.id)!;

    Future<void> pumpReader() async {
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
                  annotations: annotations,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpReader();
    final center = tester.getCenter(find.byType(ReaderView));
    await tester.longPressAt(center);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('selection-action-highlight')),
    );
    await tester.pumpAndSettle();
    expect(await annotations.list(), hasLength(1));
    // 等第一条 SnackBar 消失，避免第二条排队看不到。
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // 同一位置再次高亮 → 提示已存在，不新增。
    await tester.longPressAt(center);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('selection-action-highlight')),
    );
    await tester.pumpAndSettle();
    final afterSecond = await annotations.list();
    expect(afterSecond, hasLength(1), reason: '重复区间不新增');
    expect(find.text('该位置已有标注'), findsOneWidget);
  });
}
