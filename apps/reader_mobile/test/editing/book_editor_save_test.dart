import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_mobile/editing/book_edit_repository.dart';
import 'package:reader_mobile/editing/book_editor_controller.dart';
import 'package:reader_mobile/editing/book_editor_page.dart';
import 'package:reader_mobile/editing/book_editor_route.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/theme/app_theme.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

void main() {
  testWidgets(
    '书库工作台连续保存、草稿恢复、撤销和外部版本冲突',
    (tester) async {
      late Directory root;
      late AppDatabase database;
      late LibraryStore library;
      late BookEntry original;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('editor-save-');
        database = AppDatabase(NativeDatabase.memory());
        library = LibraryStore(
          database: database,
          directoryProvider: () async => root,
        );
        original = await library.importBytes(
          buildTestEpub(paragraphs: ['原始正文']),
        );
      });
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(paths, (_) async => root.path);
      addTearDown(() async {
        messenger.setMockMethodCallHandler(paths, null);
        await database.close();
        await root.delete(recursive: true);
      });
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1360, 900);
      addTearDown(tester.view.reset);
      final repository = BookEditRepository(library);
      var current = original;
      Future<void> open() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: BookEditorRoute(
              key: ValueKey(current.contentRevision),
              repository: repository,
              bookId: current.id,
              sourcePath: current.filePath,
              contentRevision: current.contentRevision!,
              title: current.title,
            ),
          ),
        );
        await pumpReaderUntil(tester, find.byType(BookEditorPage));
        await tester.pump(const Duration(milliseconds: 400));
      }

      BookEditorController controller() =>
          tester.widget<BookEditorPage>(find.byType(BookEditorPage)).controller;
      // 阅读器内打开编辑器时，退出编辑不能提前解除阅读器的接收保护。
      library.beginSyncRead();
      await open();
      expect(library.syncRepository().busy, isTrue);
      final editor = controller();
      final document = editor.activeDocument!;
      for (final text in ['第一次保存', '第二次保存']) {
        document.code.text = document.code.text.replaceFirst(
          RegExp('原始正文|第一次保存'),
          text,
        );
        await tester.tap(find.byTooltip('保存书籍'));
        await pumpReaderUntilComplete(
          tester,
          () => !editor.busy && !editor.dirty,
          maxFrames: 250,
        );
        expect(editor.error, isNull);
        expect(editor.activeDocument, same(document));
        current = (await pumpReaderTask(tester, library.list())).single;
        expect(current.id, original.id);
        expect(current.contentRevision, isNot(original.contentRevision));
        expect(
          await pumpReaderTask(tester, repository.openDraft(current.id)),
          isNull,
        );
      }
      editor.undo();
      expect(document.code.text, contains('第一次保存'));
      editor.redo();
      expect(document.code.text, contains('第二次保存'));
      document.code.text = document.code.text.replaceFirst('第二次保存', '保存后的草稿');
      await pumpReaderTask(tester, editor.persistDraft());
      final draft = (await pumpReaderTask(
        tester,
        repository.openDraft(current.id),
      ))!;
      expect(draft.baseRevision, current.contentRevision);
      expect(draft.sourceFile.path, current.filePath);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 400));
      expect(library.syncRepository().busy, isTrue);
      library.endSyncRead();
      expect(library.syncRepository().busy, isFalse);
      await open();
      expect(library.syncRepository().busy, isTrue);
      final recovered = controller();
      expect(recovered.activeDocument!.code.text, contains('保存后的草稿'));
      await tester.tap(find.byTooltip('保存书籍'));
      await pumpReaderUntilComplete(
        tester,
        () => !recovered.busy && !recovered.dirty,
        maxFrames: 250,
      );
      expect(recovered.error, isNull);
      current = (await pumpReaderTask(tester, library.list())).single;
      final updated = await pumpReaderTask(
        tester,
        EpubEditSession.open(File(current.filePath)),
      );
      expect(updated.readText('OEBPS/c1.xhtml'), contains('保存后的草稿'));
      updated.close();
      await pumpReaderTask(
        tester,
        library.updateBytes(current.id, buildTestEpub(paragraphs: ['外部更新'])),
      );
      recovered.activeDocument!.code.text = recovered.activeDocument!.code.text
          .replaceFirst('保存后的草稿', '冲突时保留输入');
      await tester.tap(find.byTooltip('保存书籍'));
      await pumpReaderUntilComplete(
        tester,
        () => !recovered.busy && !recovered.previewLoading,
        maxFrames: 250,
      );
      expect(recovered.error, contains('书籍版本已变化'));
      expect(recovered.dirty, isTrue);
      expect(recovered.activeDocument!.code.text, contains('冲突时保留输入'));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 400));
      expect(library.syncRepository().busy, isFalse);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );
}
