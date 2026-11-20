import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';

import '../support/test_epub.dart';

import 'package:reader_ui/reader_session.dart';

/// 慢速书库：给「导入中」进度条留出观察窗口。
class _SlowLibrary extends LibraryStore {
  _SlowLibrary() : super.memory();

  @override
  Future<BookEntry> importBytes(
    Uint8List bytes, {
    String? fallbackTitle,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    onProgress?.call(0.2);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return super.importBytes(
      bytes,
      fallbackTitle: fallbackTitle,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }
}

Future<void> _settle(WidgetTester tester, {int frames = 6}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late Directory temp;
  late File epubFile;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('bookshelf-import');
    epubFile = File('${temp.path}/山海小记.epub')
      ..writeAsBytesSync(buildTestEpub(title: '山海小记'));
  });

  tearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  testWidgets('导入中显示进度条，可取消且不留半成品', (tester) async {
    final library = _SlowLibrary();
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
          pickEpubFiles: () async => <String>[epubFile.path],
          readFile: (path) async => File(path).readAsBytesSync(),
        ),
      ),
    );
    await _settle(tester);

    await tester.tap(find.byTooltip('导入 EPUB / TXT'));
    await _settle(tester, frames: 2);

    expect(find.textContaining('正在导入'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.tap(find.text('取消'));
    await _settle(tester, frames: 16);

    expect(find.textContaining('正在导入'), findsNothing);
    expect(find.text('书架还是空的'), findsOneWidget, reason: '取消后无残留');
  });

  testWidgets('长按卡片看详情，详情里删除后书架清空', (tester) async {
    final library = LibraryStore.memory();
    final progressStore = MemoryReaderProgressStore();
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: progressStore,
          pickEpubFiles: () async => <String>[epubFile.path],
          readFile: (path) async => File(path).readAsBytesSync(),
        ),
      ),
    );
    await _settle(tester);
    await tester.tap(find.byTooltip('导入 EPUB / TXT'));
    await _settle(tester, frames: 10);
    expect(find.text('山海小记'), findsWidgets);
    final book = (await library.list()).single;
    await progressStore.save(
      book.id,
      const ReaderProgress(spineIndex: 0, pageIndex: 0),
    );

    await tester.longPress(find.text('山海小记').first);
    await _settle(tester);
    expect(find.text('详情'), findsOneWidget, reason: '长按打开快捷操作面板');
    expect(find.text('导入报告'), findsNothing);
    expect(find.text('已读 1 / 1 章'), findsOneWidget);

    await tester.ensureVisible(find.text('删除'));
    await tester.pump();
    await tester.tap(find.text('删除'));
    await _settle(tester);
    expect(find.text('删除《山海小记》'), findsOneWidget, reason: '删除需要确认');

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await _settle(tester, frames: 10);
    expect(await library.list(), isEmpty);
    expect(find.text('书架还是空的'), findsOneWidget);
  });

  testWidgets('长按卡片可从详情面板进入完整图书详情页', (tester) async {
    final library = LibraryStore.memory();
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
          pickEpubFiles: () async => <String>[epubFile.path],
          readFile: (path) async => File(path).readAsBytesSync(),
        ),
      ),
    );
    await _settle(tester);
    await tester.tap(find.byTooltip('导入 EPUB / TXT'));
    await _settle(tester, frames: 10);

    await tester.longPress(find.text('山海小记').first);
    await _settle(tester);
    final detailButton = find.text('详情');
    await tester.ensureVisible(detailButton);
    await tester.tap(detailButton);
    await _settle(tester, frames: 8);

    expect(find.text('图书资料'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('book-detail-title-field')),
      findsOneWidget,
    );
  });

  testWidgets('多选两本：队列依次导入并刷新书架', (tester) async {
    final library = LibraryStore.memory();
    final second = File('${temp.path}/第二本.epub')
      ..writeAsBytesSync(buildTestEpub(title: '第二本'));
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
          pickEpubFiles: () async => <String>[epubFile.path, second.path],
          readFile: (path) async => File(path).readAsBytesSync(),
        ),
      ),
    );
    await _settle(tester);

    await tester.tap(find.byTooltip('导入 EPUB / TXT'));
    await _settle(tester, frames: 10);

    expect(find.text('山海小记'), findsWidgets);
    expect(find.text('第二本'), findsWidgets);
    expect((await library.list()).length, 2);
  });

  testWidgets('临时模式禁用导入入口，不调用文件选择器', (tester) async {
    final library = LibraryStore.memory();
    var pickCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
          allowImport: false,
          pickEpubFiles: () async {
            pickCalls++;
            return <String>[epubFile.path];
          },
        ),
      ),
    );
    await _settle(tester);

    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('bookshelf-import')),
    );
    expect(button.onPressed, isNull);
    await tester.tap(find.byTooltip('导入 EPUB / TXT'));
    await _settle(tester);
    expect(pickCalls, 0);
    expect(await library.list(), isEmpty);
    expect(find.text('书库暂时不可用'), findsOneWidget);
    expect(find.text('书架还是空的'), findsNothing);
  });

  testWidgets('选择文件期间转入临时模式，不将迟到文件入队', (tester) async {
    final library = LibraryStore.memory();
    final progress = MemoryReaderProgressStore();
    final pending = Completer<List<String>>();
    var readCalls = 0;
    Widget page(bool allowImport) => MaterialApp(
      home: BookshelfPage(
        library: library,
        progressStore: progress,
        allowImport: allowImport,
        pickEpubFiles: () => pending.future,
        readFile: (_) async {
          readCalls++;
          return buildTestEpub();
        },
      ),
    );
    await tester.pumpWidget(page(true));
    await _settle(tester);
    await tester.tap(find.byTooltip('导入 EPUB / TXT'));
    await tester.pumpWidget(page(false));
    pending.complete(<String>[epubFile.path]);
    await _settle(tester);

    expect(readCalls, 0);
    expect(await library.list(), isEmpty);
    expect(find.textContaining('正在导入'), findsNothing);
  });
}
