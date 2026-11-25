import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_mobile/editing/book_editor_page.dart';
import 'package:reader_mobile/editing/epub_file_editor_page.dart';
import 'package:reader_mobile/theme/app_theme.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

const _platforms = TargetPlatformVariant({
  TargetPlatform.macOS,
  TargetPlatform.windows,
});

Future<void> _shortcut(WidgetTester tester) async {
  final modifier = defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

Future<void> _show(WidgetTester tester, EpubFileEditorPage page) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(1200, 800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: page));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('取消选文件可重试，快捷键不重复打开且隐藏页不响应', (tester) async {
    var calls = 0;
    var pending = Completer<String?>();
    Future<String?> pick() {
      calls++;
      return pending.future;
    }

    await _show(tester, EpubFileEditorPage(pickFile: pick));
    await _shortcut(tester);
    await _shortcut(tester);
    expect(calls, 1);
    pending.complete(null);
    await tester.pumpAndSettle();
    pending = Completer<String?>();
    await tester.tap(find.byKey(const ValueKey('editor-open-file')));
    expect(calls, 2);
    pending.complete(null);
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: EpubFileEditorPage(active: false, pickFile: pick),
      ),
    );
    await tester.pumpAndSettle();
    await _shortcut(tester);
    expect(calls, 2);
    pending = Completer<String?>();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: EpubFileEditorPage(pickFile: pick),
      ),
    );
    await tester.pumpAndSettle();
    await _shortcut(tester);
    expect(calls, 3);
    pending.complete(null);
    await tester.pumpAndSettle();
  }, variant: _platforms);

  testWidgets('本地 EPUB 取消保存保留修改，重试输出后可重开且原文件不变', (tester) async {
    late Directory root;
    late File input;
    final original = buildTestEpub(title: '外部书籍', paragraphs: ['原始正文']);
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('file-editor-test-');
      input = await File('${root.path}/外部书籍.epub').writeAsBytes(original);
    });
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(paths, (_) async => root.path);
    addTearDown(() async {
      messenger.setMockMethodCallHandler(paths, null);
      await root.delete(recursive: true);
    });
    var saveCalls = 0;
    var cancel = true;
    final output = File('${root.path}/输出.epub');
    await _show(
      tester,
      EpubFileEditorPage(
        pickFile: () async => input.path,
        saveFile: (source, {required fileName}) async {
          saveCalls++;
          expect(fileName, '外部书籍_已编辑.epub');
          if (cancel) return false;
          await source.copy(output.path);
          return true;
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('editor-open-file')));
    await pumpReaderUntil(tester, find.byType(BookEditorPage));
    final editor = tester
        .widget<BookEditorPage>(find.byType(BookEditorPage))
        .controller;
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
    await tester.pump(const Duration(milliseconds: 400));
    expect(editor.saveDraft, isNull);
    final document = editor.openDocument('OEBPS/c1.xhtml');
    document.code.text = document.code.text.replaceFirst('原始正文', '本地修订正文');
    await tester.tap(find.byTooltip('保存书籍'));
    await pumpReaderUntilComplete(tester, () => saveCalls == 1 && !editor.busy);
    expect(find.byType(BookEditorPage), findsOneWidget);
    expect(editor.dirty, isTrue);
    expect(editor.error, isNull);
    cancel = false;
    await tester.tap(find.byTooltip('保存书籍'));
    await pumpReaderUntilComplete(tester, () => saveCalls == 2 && !editor.busy);
    expect(find.byType(BookEditorPage), findsOneWidget);
    expect(editor.dirty, isFalse);
    await tester.tap(find.byTooltip('退出编辑'));
    await pumpReaderUntil(
      tester,
      find.byKey(const ValueKey('editor-open-file')),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      expect(await input.readAsBytes(), orderedEquals(original));
      final reopened = await EpubEditSession.open(output);
      expect(reopened.readText('OEBPS/c1.xhtml'), contains('本地修订正文'));
      reopened.close();
      expect(
        await root.list().where((entry) => entry is Directory).toList(),
        isEmpty,
      );
    });
    expect(saveCalls, 2);
    expect(tester.takeException(), isNull);
  }, variant: _platforms);

  testWidgets('损坏文件显示错误后可重新选择，放弃修改不生成草稿或输出', (tester) async {
    late Directory root;
    late File input;
    final original = buildTestEpub(paragraphs: ['可编辑正文']);
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('file-editor-discard-');
      input = await File('${root.path}/book.epub').writeAsBytes([1, 2, 3]);
    });
    addTearDown(() => root.delete(recursive: true));
    await _show(
      tester,
      EpubFileEditorPage(
        pickFile: () async => input.path,
        saveFile: (_, {required fileName}) async {
          fail('放弃修改不应保存文件');
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('editor-open-file')));
    await pumpReaderUntil(tester, find.textContaining('打开 EPUB 失败'));
    await tester.runAsync(() => input.writeAsBytes(original));
    await tester.tap(find.byKey(const ValueKey('editor-open-file')));
    await pumpReaderUntil(tester, find.byType(BookEditorPage));
    final editor = tester
        .widget<BookEditorPage>(find.byType(BookEditorPage))
        .controller;
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
    await tester.pump(const Duration(milliseconds: 400));
    final document = editor.openDocument('OEBPS/c1.xhtml');
    document.code.text = document.code.text.replaceFirst('可编辑正文', '放弃的修改');
    await tester.tap(find.byTooltip('退出编辑'));
    await pumpReaderUntil(tester, find.text('放弃修改并退出'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('保留草稿并退出'), findsNothing);
    await tester.tap(find.text('放弃修改并退出'));
    await pumpReaderUntil(
      tester,
      find.byKey(const ValueKey('editor-open-file')),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      expect(await input.readAsBytes(), orderedEquals(original));
      expect(await root.list().length, 1);
    });
    expect(tester.takeException(), isNull);
  }, variant: _platforms);
}
