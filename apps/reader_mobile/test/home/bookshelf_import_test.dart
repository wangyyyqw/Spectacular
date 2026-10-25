import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/file_progress_store.dart';

import '../support/test_epub.dart';

/// 慢速书库：给「导入中」进度条留出观察窗口。
class _SlowLibrary extends LibraryStore {
  _SlowLibrary() : super.memory();

  @override
  Future<BookEntry> importBytes(
    Uint8List bytes, {
    String? fallbackTitle,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.2);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return super.importBytes(
      bytes,
      fallbackTitle: fallbackTitle,
      onProgress: onProgress,
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
          progressStore: FileReaderProgressStore.memory(),
          pickEpubFiles: () async => <String>[epubFile.path],
          readFile: (path) async => File(path).readAsBytesSync(),
        ),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('导入 EPUB'));
    await _settle(tester, frames: 2);

    expect(find.textContaining('正在导入'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.tap(find.text('取消'));
    await _settle(tester, frames: 8);

    expect(find.textContaining('正在导入'), findsNothing);
    expect(find.text('书架还是空的'), findsOneWidget, reason: '取消后无残留');
  });

  testWidgets('长按卡片看详情，详情里删除后书架清空', (tester) async {
    final library = LibraryStore.memory();
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: FileReaderProgressStore.memory(),
          pickEpubFiles: () async => <String>[epubFile.path],
          readFile: (path) async => File(path).readAsBytesSync(),
        ),
      ),
    );
    await _settle(tester);
    await tester.tap(find.text('导入 EPUB'));
    await _settle(tester, frames: 10);
    expect(find.text('山海小记'), findsWidgets);

    await tester.longPress(find.text('山海小记').first);
    await _settle(tester);
    expect(find.text('导入报告'), findsOneWidget, reason: '长按打开详情面板');

    await tester.tap(find.text('删除本书'));
    await _settle(tester);
    expect(find.text('删除《山海小记》'), findsOneWidget, reason: '删除需要确认');

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await _settle(tester, frames: 10);
    expect(await library.list(), isEmpty);
    expect(find.text('书架还是空的'), findsOneWidget);
  });

  testWidgets('多选两本：队列依次导入并刷新书架', (tester) async {
    final library = LibraryStore.memory();
    final second = File('${temp.path}/第二本.epub')
      ..writeAsBytesSync(buildTestEpub(title: '第二本'));
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: FileReaderProgressStore.memory(),
          pickEpubFiles: () async => <String>[epubFile.path, second.path],
          readFile: (path) async => File(path).readAsBytesSync(),
        ),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('导入 EPUB'));
    await _settle(tester, frames: 10);

    expect(find.text('山海小记'), findsWidgets);
    expect(find.text('第二本'), findsWidgets);
    expect((await library.list()).length, 2);
  });
}
