import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/annotations/note_composer_sheet.dart';
import 'package:reader_ui/decorations/decoration.dart';
import 'package:reader_ui/decorations/decoration_rules.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/selection/selection.dart';
import 'package:reader_ui/selection/selection_layer.dart';
import 'package:reader_ui/selection/selection_menu.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

class _ForbiddenDecorations
    implements ReaderDecorationStore, ReaderDecorationRuleStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('混淆书不可读取或修改装饰：${invocation.memberName}');
}

void main() {
  Object? clipboard;
  late Directory dir;
  late AppDatabase db;
  late LibraryStore library;
  late BookEntry book;
  late EpubChapterSource source;
  late ReaderSession session;
  late ReaderAnnotationStore annotations;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('selection-ocr-test');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryStore(database: db, directoryProvider: () async => dir);
    final bytes = buildTestEpub(
      paragraphs: [List.filled(120, '屏汉丹恍搀条，徘廷抓胺乳丹赵欺，院腾固莎崇邪。').join()],
    );
    book = await library.importBytes(bytes);
    annotations = library.annotationStore(book.id)!;
    source = await openTestChapterSource(bytes);
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') clipboard = call.arguments;
          return null;
        });
  });
  tearDown(() async {
    source.close();
    await db.close();
    await dir.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<SelectionLayer> select(
    WidgetTester tester,
    Future<String> Function(Uint8List) recognize, {
    ValueChanged<ReaderEditTarget>? edit,
  }) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final forbidden = _ForbiddenDecorations();
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
                ocrRequired: true,
                onRecognizeSelection: recognize,
                decorations: forbidden,
                decorationRules: forbidden,
                onEditTarget: edit,
                onSessionReady: (value) => session = value,
              ),
            ),
          ),
        ),
      ),
    );
    await pumpReaderUntil(tester, find.byType(ReaderView));
    await tester.longPressAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    final menu = tester.widget<SelectionMenu>(find.byType(SelectionMenu));
    expect(menu.actions.any((a) => a.id == 'decoration'), isFalse);
    return tester.widget<SelectionLayer>(find.byType(SelectionLayer));
  }

  testWidgets('复制交付 OCR 字符；手动与自动装饰均不读取', (tester) async {
    var calls = 0;
    await select(tester, (image) async {
      calls++;
      expect(image.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      return '这是可见的正常文字';
    });
    await tester.tap(find.byKey(const ValueKey('selection-action-copy')));
    await pumpReaderUntilComplete(tester, () => clipboard != null);
    expect(clipboard, {'text': '这是可见的正常文字'});
    expect(calls, 1);
    expect(find.byType(SelectionLayer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('划线保存可读引用和原码点锚点，编辑传递同一精确区间', (tester) async {
    final layer = await select(tester, (_) async => '正常引用');
    final raw = SelectionOps.textOf(layer.page, layer.selection);
    final range = SelectionOps.cfiOf(layer.selection)!;
    await tester.tap(find.byKey(const ValueKey('selection-action-mark')));
    await pumpReaderUntilComplete(
      tester,
      () => find.byType(SelectionLayer).evaluate().isEmpty,
    );
    final saved = (await pumpReaderTask(tester, annotations.list())).single;
    expect(saved.quote, '正常引用');
    expect(saved.startCfi, range.start);
    expect(saved.endCfi, range.end);
    expect(AnchorRecord.decode(saved.anchorData)!.effective.quote, raw);

    ReaderEditTarget? target;
    // 重新建阅读页，避开点击已有划线时弹出的编辑标注面板。
    await tester.pumpWidget(const SizedBox());
    final selected = await select(
      tester,
      (_) async => '编辑可见文字',
      edit: (value) => target = value,
    );
    final expected = SelectionOps.cfiOf(selected.selection)!;
    await tester.tap(
      find.byKey(const ValueKey('selection-action-edit-source')),
    );
    await pumpReaderUntilComplete(tester, () => target != null);
    expect(target!.recognizedText, '编辑可见文字');
    expect(
      target!.sourceText,
      SelectionOps.textOf(selected.page, selected.selection),
    );
    expect(target!.cfi, expected.start);
    expect(target!.endCfi, expected.end);
  });

  testWidgets('想法面板和保存记录使用识别后的引用', (tester) async {
    await select(tester, (_) async => '正常的想法引用');
    await tester.tap(find.byKey(const ValueKey('selection-action-thought')));
    await pumpReaderUntil(tester, find.byType(ReaderNoteComposerSheet));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ReaderNoteComposerSheet>(find.byType(ReaderNoteComposerSheet))
          .quote,
      '正常的想法引用',
    );
    await tester.enterText(
      find.byKey(const ValueKey('note-composer-input')),
      '保留我的想法',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-composer-save')));
    await pumpReaderUntilComplete(
      tester,
      () => find.byType(SelectionLayer).evaluate().isEmpty,
    );
    final saved = (await pumpReaderTask(tester, annotations.list())).single;
    expect(saved.quote, '正常的想法引用');
    expect(saved.note, '保留我的想法');
    expect(saved.type, ReaderAnnotationType.thought);
  });

  testWidgets('OCR 失败不复制乱码，显示失败后可以重试', (tester) async {
    var fail = true;
    await select(tester, (_) async {
      if (fail) throw const FormatException('识别不完整');
      return '重试成功';
    });
    await tester.tap(find.byKey(const ValueKey('selection-action-copy')));
    await pumpReaderUntil(tester, find.text('识别不完整'));
    expect(clipboard, isNull);
    expect(await pumpReaderTask(tester, annotations.list()), isEmpty);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    fail = false;
    await tester.tap(find.byKey(const ValueKey('selection-action-copy')));
    await pumpReaderUntilComplete(tester, () => clipboard != null);
    expect(clipboard, {'text': '重试成功'});
  });

  testWidgets('OCR 忙碌时不重复请求，选择变化后丢弃结果', (tester) async {
    final pending = Completer<String>();
    var calls = 0;
    final layer = await select(tester, (_) {
      calls++;
      return pending.future;
    });
    final copy = tester
        .widget<SelectionMenu>(find.byType(SelectionMenu))
        .actions
        .firstWhere((a) => a.id == 'copy');
    copy.onTap();
    copy.onTap();
    await pumpReaderUntilComplete(tester, () => calls == 1);
    layer.onChanged(
      ReaderSelection.normalized(
        layer.selection.start,
        layer.selection.end,
        pageIndex: layer.pageIndex,
      ),
    );
    pending.complete('过期结果');
    await pumpReaderUntilComplete(
      tester,
      () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
    );
    expect(clipboard, isNull);
    expect(calls, 1);
  });

  testWidgets('跨页 OCR 按页顺序拼接，覆盖终页', (tester) async {
    var calls = 0;
    final layer = await select(tester, (_) async => '第${++calls}页');
    layer.onEdgeDrag!(true);
    await tester.pump(const Duration(milliseconds: 400));
    await pumpReaderUntilComplete(tester, () {
      final layers = find.byType(SelectionLayer).evaluate();
      return layers.length == 1 &&
          !session.loading &&
          (layers.single.widget as SelectionLayer).selection.isMultiPage;
    });
    final selected = tester
        .widget<SelectionLayer>(find.byType(SelectionLayer))
        .selection;
    await tester.tap(find.byKey(const ValueKey('selection-action-copy')));
    await pumpReaderUntilComplete(tester, () => clipboard != null);
    expect(calls, selected.endPageIndex - selected.startPageIndex + 1);
    expect(clipboard, {
      'text': List.generate(calls, (i) => '第${i + 1}页').join(),
    });
  });
}
