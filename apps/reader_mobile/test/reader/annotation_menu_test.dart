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

import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/library/revision_anchor_index.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
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

String _normalized(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim();

/// 菜单使用确定性内存存储；完整原 EPUB 锚点核验仍按实际选中文字执行。
class _Annotations implements ReaderAnnotationStore {
  _Annotations(this.book);
  final AnchorBook book;
  final items = <ReaderAnnotation>[];
  int sequence = 0;
  LocationAnchor _capture(String start, String end, String quote) {
    final anchor = book.capture(start, endCfi: end);
    expect(anchor, isNotNull, reason: '选区必须对应原 EPUB 的实际位置');
    expect(
      _normalized(anchor!.quote),
      _normalized(quote),
      reason: '不能以合法 CFI 替代选中文字的内容核验',
    );
    return anchor;
  }

  @override
  Future<List<ReaderAnnotation>> list() async => List.of(items);
  @override
  Future<ReaderAnnotation?> add({
    required ReaderAnnotationType type,
    required String startCfi,
    required String endCfi,
    required String quote,
    String? contextBefore,
    String? contextAfter,
    int? color,
    ReaderAnnotationStyle style = ReaderAnnotationStyle.background,
    double? opacity,
    String? note,
  }) async {
    final existing = items
        .where((item) => item.startCfi == startCfi && item.endCfi == endCfi)
        .firstOrNull;
    if (existing != null) {
      await update(
        existing.id,
        type: existing.type == ReaderAnnotationType.thought
            ? existing.type
            : type,
        color: color,
        style: style,
        opacity: opacity,
        note: note,
      );
      return items.firstWhere((item) => item.id == existing.id);
    }
    final anchor = _capture(startCfi, endCfi, quote);
    final item = ReaderAnnotation(
      id: '${++sequence}',
      type: type,
      startCfi: startCfi,
      endCfi: endCfi,
      quote: quote,
      contextBefore: contextBefore,
      contextAfter: contextAfter,
      color: color,
      style: style,
      opacity: opacity,
      note: note,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      relocationStatus: 'verified',
      currentQuote: anchor.quote,
      anchorData: AnchorRecord(original: anchor).encode(),
    );
    items.add(item);
    return item;
  }

  @override
  Future<void> update(
    String id, {
    ReaderAnnotationType? type,
    int? color,
    ReaderAnnotationStyle? style,
    double? opacity,
    String? note,
    bool clearNote = false,
  }) async {
    final index = items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final item = items[index];
    items[index] = ReaderAnnotation(
      id: item.id,
      type: type ?? item.type,
      startCfi: item.startCfi,
      endCfi: item.endCfi,
      quote: item.quote,
      contextBefore: item.contextBefore,
      contextAfter: item.contextAfter,
      color: color ?? item.color,
      style: style ?? item.style,
      opacity: opacity ?? item.opacity,
      note: clearNote ? null : note ?? item.note,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      relocationStatus: item.relocationStatus,
      currentQuote: item.currentQuote,
      anchorData: item.anchorData,
    );
  }

  @override
  Future<void> remove(String id) async =>
      items.removeWhere((item) => item.id == id);
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('选区快捷划线写入标注库并支持撤销', (tester) async {
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
    late _Annotations annotations;
    await tester.runAsync(() async {
      annotations = _Annotations(await buildRevisionAnchorBook(bytes));
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 360,
          height: 520,
          child: EpubReaderPage(
            bytes: bytes,
            bookId: book.id,
            store: MemoryReaderProgressStore(),
            annotations: annotations,
            bookTitle: book.title,
          ),
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.byKey(const ValueKey<String>('epub-reader-scaffold')),
      findsOneWidget,
    );

    await tester.longPressAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionLayer), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('selection-action-mark')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('selection-action-mark')),
    );
    await tester.pumpAndSettle();
    expect(find.text('已划线'), findsOneWidget);
    expect(find.byType(SelectionLayer), findsNothing, reason: '保存后清除选区');

    final saved = await annotations.list();
    expect(saved, hasLength(1));
    final item = saved.single;
    expect(item.type, ReaderAnnotationType.mark);
    expect(item.style, ReaderAnnotationStyle.underline);
    expect(item.startCfi, contains('epubcfi('));
    expect(item.endCfi, contains('epubcfi('));
    expect(item.quote, isNotEmpty);
    expect(item.color, 0xFFFFEB3B);
    expect(
      find.byType(AnnotationLayer),
      findsOneWidget,
      reason: '保存后页面出现标注装饰层（P4-18）',
    );
    expect(find.text('撤销'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(await annotations.list(), isEmpty);
    expect(find.byType(AnnotationLayer), findsNothing);
    expect(find.text('已撤销'), findsOneWidget);
  });

  testWidgets('同一区间重复划线更新原记录且不新增', (tester) async {
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
    late _Annotations annotations;
    await tester.runAsync(() async {
      annotations = _Annotations(await buildRevisionAnchorBook(bytes));
    });

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
      find.byKey(const ValueKey<String>('selection-action-mark')),
    );
    await tester.pumpAndSettle();
    expect(await annotations.list(), hasLength(1));
    expect(
      (await annotations.list()).single.style,
      ReaderAnnotationStyle.underline,
    );
    // 等第一条 SnackBar 消失，避免第二条排队看不到。
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // 同一位置再次高亮 → 提示已存在，不新增。
    await tester.longPressAt(center);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('selection-action-mark')),
    );
    await tester.pumpAndSettle();
    final afterSecond = await annotations.list();
    expect(afterSecond, hasLength(1), reason: '重复区间不新增');
    expect(find.text('已划线'), findsOneWidget);
    expect(afterSecond.single.id, '1');
  });

  testWidgets('点击高亮可更换颜色并取消', (tester) async {
    final dir = Directory.systemTemp.createTempSync('annotation-edit');
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
    late _Annotations annotations;
    await tester.runAsync(() async {
      annotations = _Annotations(await buildRevisionAnchorBook(bytes));
    });

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

    final center = tester.getCenter(find.byType(ReaderView));
    await tester.longPressAt(center);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('selection-action-mark')),
    );
    await tester.pumpAndSettle();
    expect(await annotations.list(), hasLength(1));

    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('annotation-editor-sheet')),
      findsOneWidget,
    );
    expect(find.text('删除划线'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-color-0xFF90CAF9')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('annotation-editor-sheet')),
      findsOneWidget,
    );
    expect((await annotations.list()).single.color, defaultHighlightColor);
    final wavyStyle = find.byKey(
      const ValueKey<String>('annotation-style-wavyUnderline'),
    );
    await tester.ensureVisible(wavyStyle);
    await tester.tap(wavyStyle);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('annotation-editor-sheet')),
      findsOneWidget,
    );
    final save = find.byKey(const ValueKey<String>('annotation-save-changes'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final restyled = (await annotations.list()).single;
    expect(restyled.color, 0xFF90CAF9);
    expect(restyled.style, ReaderAnnotationStyle.wavyUnderline);
    expect(
      find.byKey(const ValueKey<String>('annotation-editor-sheet')),
      findsNothing,
    );

    await tester.tapAt(center);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('annotation-color-0xFFA5D6A7')),
    );
    await tester.pumpAndSettle();
    final appearanceSave = find.byKey(
      const ValueKey<String>('annotation-save-changes'),
    );
    expect(tester.widget<FilledButton>(appearanceSave).onPressed, isNotNull);
    await tester.ensureVisible(appearanceSave);
    await tester.tap(appearanceSave);
    await tester.pumpAndSettle();
    final appearanceOnly = (await annotations.list()).single;
    expect(appearanceOnly.type, ReaderAnnotationType.mark);
    expect(appearanceOnly.color, 0xFFA5D6A7);
    expect(appearanceOnly.note, isNull);

    await tester.tapAt(center);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('annotation-remove')));
    await tester.pumpAndSettle();
    expect(await annotations.list(), isEmpty);
    expect(find.byType(AnnotationLayer), findsNothing);
    expect(find.text('撤销'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    final restored = (await annotations.list()).single;
    expect(restored.type, ReaderAnnotationType.mark);
    expect(restored.color, 0xFFA5D6A7);
    expect(restored.style, ReaderAnnotationStyle.wavyUnderline);
    expect(restored.quote, isNotEmpty);
  });
}
