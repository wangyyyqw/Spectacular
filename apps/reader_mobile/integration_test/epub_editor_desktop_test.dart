import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_mobile/editing/book_edit_repository.dart';
import 'package:reader_mobile/editing/book_editor_controller.dart';
import 'package:reader_mobile/editing/book_editor_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/theme/app_theme.dart';

import '../test/library/fixtures/revision_epub.dart';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('桌面编辑任务等待超时');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump();
}

/// ReEditor 使用增量输入协议；标准 tester.enterText 只发送旧版完整状态。
void _enterCode(WidgetTester tester, String text) {
  final input = tester.testTextInput;
  final client =
      (input.log
                  .lastWhere((call) => call.method == 'TextInput.setClient')
                  .arguments
              as List)
          .first;
  final oldText = input.editingState!['text'] as String;
  tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.textInput.name,
    SystemChannels.textInput.codec.encodeMethodCall(
      MethodCall('TextInputClient.updateEditingStateWithDeltas', [
        client,
        {
          'deltas': [
            {
              'oldText': oldText,
              'deltaText': text,
              'deltaStart': 0,
              'deltaEnd': oldText.length,
              'selectionBase': text.length,
              'selectionExtent': text.length,
              'selectionAffinity': 'TextAffinity.downstream',
              'selectionIsDirectional': false,
              'composingBase': -1,
              'composingExtent': -1,
            },
          ],
        },
      ]),
    ),
    (_) {},
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('桌面真实引擎：ReEditor输入 → 正式预览 → 保存书库 → 导出重开', (tester) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = await Directory.systemTemp.createTemp('desktop-epub-editor-');
    final db = AppDatabase(NativeDatabase.memory());
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => root,
    );
    BookEditorController? editor;
    addTearDown(() async {
      editor?.dispose();
      await db.close();
      await root.delete(recursive: true);
    });
    final book = await library.importBytes(buildRevisionTestEpub());
    final repository = BookEditRepository(library);
    final session = await EpubEditSession.open(File(book.filePath));
    final exported = File('${root.path}/exported.epub');
    BookEntry? savedBook;
    editor = BookEditorController(
      session: session,
      saveDraft: (session, buffers) => repository.saveDraft(
        book.id,
        book.contentRevision!,
        (storeBlob) => {
          ...session.toDraft(storeBlob: storeBlob),
          'uiBuffers': buffers,
        },
      ),
      commit: (session) async {
        final output = File('${root.path}/saved.epub');
        await EpubWriter.write(session, output);
        savedBook = await repository.commitEditedFile(
          book.id,
          book.contentRevision!,
          output,
          session.summary,
        );
      },
      export: (session) => EpubWriter.write(session, exported),
    );
    final controller = editor;
    var saved = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  saved =
                      await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => BookEditorPage(
                            controller: controller,
                            title: book.title,
                          ),
                        ),
                      ) ??
                      false;
                },
                child: const Text('打开桌面编辑器'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开桌面编辑器'));
    await _until(
      tester,
      () =>
          find.byType(BookEditorPage).evaluate().isNotEmpty &&
          controller.previewSource != null,
    );
    // 小窗口也走同一个工作台：先切换源码，再使用真实键盘快捷键全选。
    final sourceTab = find.text('源码');
    if (sourceTab.evaluate().isNotEmpty) {
      await tester.tap(sourceTab);
      await tester.pump();
    }
    await _until(tester, () => find.byType(CodeEditor).evaluate().isNotEmpty);
    final doc = controller.activeDocument!;
    final next = doc.code.text.replaceFirst(revisionQuote, '桌面编辑器实际输入的新正文。');
    await tester.tap(find.byType(CodeEditor));
    await tester.pump();
    final modifier = Platform.isMacOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(modifier);
    _enterCode(tester, next);
    await tester.pump(const Duration(milliseconds: 350));
    expect(doc.code.text, next);
    await _until(
      tester,
      () =>
          !controller.previewLoading &&
          controller.previewRevision == session.revision,
    );
    expect(
      controller.previewSource!.document.chapterXhtml(0),
      contains('桌面编辑器实际输入的新正文。'),
    );
    expect(await controller.exportBook(), isTrue);
    final reopened = await EpubChapterSource.openFile(exported);
    expect(
      (await reopened.loadAnchorChapter(0)).text,
      contains('桌面编辑器实际输入的新正文。'),
    );
    reopened.close();
    await reopened.preparationsStopped;
    await tester.tap(find.byTooltip('保存书籍'));
    await _until(tester, () => saved);
    expect(savedBook!.id, book.id);
    expect(savedBook!.contentRevision, isNot(book.contentRevision));
    expect(await repository.openDraft(book.id), isNull);
    final savedSource = await EpubChapterSource.openFile(
      File(savedBook!.filePath),
    );
    expect(
      (await savedSource.loadAnchorChapter(0)).text,
      contains('桌面编辑器实际输入的新正文。'),
    );
    savedSource.close();
    await savedSource.preparationsStopped;
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
