import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/parser/document_parser.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_mobile/editing/book_editor_controller.dart';
import 'package:reader_mobile/editing/book_editor_element_sheet.dart';
import 'package:reader_mobile/editing/book_editor_page.dart';
import 'package:reader_mobile/editing/book_editor_preview.dart';
import 'package:reader_mobile/editing/book_editor_source.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

const _chapter = 'OEBPS/c1.xhtml';

Future<BookEditorController> _open(
  WidgetTester tester, {
  SaveEditorDraft? saveDraft,
  CommitEditor? commit,
  ReaderSettings? readingSettings,
  Future<void> Function()? discardDraft,
  bool withImages = false,
  String? firstChapter,
}) async {
  late Directory temporary;
  late EpubEditSession session;
  await tester.runAsync(() async {
    temporary = await Directory.systemTemp.createTemp('editor-widget-');
    final file = File('${temporary.path}/book.epub');
    await file.writeAsBytes(
      buildMultiChapterEpub(
        chapters: [
          firstChapter ??
              '<p id="paragraph" class="body">原始正文与<em>行内强调</em>继续阅读。</p>',
          '<p>第二章节正文。</p>',
        ],
        rawBody: true,
      ),
    );
    session = await EpubEditSession.open(file);
    if (withImages) {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      PackageEditor(session).addResource('OEBPS/image.png', png, 'image/png');
      PackageEditor(session).addResource('OEBPS/other.png', png, 'image/png');
      final paragraph = session
          .editableDocument(_chapter)
          .elements
          .firstWhere((node) => node.tag == 'p');
      session.insertAfter(
        paragraph,
        '<img id="picture" src="image.png" alt="旧图片描述"/>',
      );
    }
  });
  final editor = BookEditorController(
    session: session,
    saveDraft: saveDraft,
    commit: commit,
    readingSettings: readingSettings,
    discardDraft: discardDraft,
  );
  addTearDown(() async {
    editor.dispose();
    await temporary.delete(recursive: true);
  });
  await pumpReaderUntilComplete(tester, () => editor.previewSource != null);
  return editor;
}

ReaderEditTarget _target(BookEditorController editor) {
  final parsed = DocumentParser.parse(
    xhtml: editor.session.readText(_chapter),
    spineIndex: 0,
  );
  return ReaderEditTarget(
    spineIndex: 0,
    cfi: parsed.elementById('paragraph')!.cfi.serialize(),
  );
}

Future<void> _show(
  WidgetTester tester,
  BookEditorController editor,
  Size size,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: BookEditorPage(controller: editor, title: '可编辑测试书'),
    ),
  );
  await pumpReaderUntilComplete(
    tester,
    () => find.byType(ReaderPage).evaluate().isNotEmpty,
  );
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets('混合行内段落后半部真实点击与选区编辑均定位到源码元素', (tester) async {
    final editor = await _open(
      tester,
      firstChapter:
          '<p id="paragraph">开<em>行内强调文字</em>'
          '<a href="#paragraph">链接文字</a>后半段正文结束。</p>',
    );
    ReaderSession? reader;
    final targets = <ReaderEditTarget>[];
    const padding = EdgeInsets.all(40);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: editor.previewSource!,
            store: MemoryReaderProgressStore(),
            bookId: 'mixed-inline-editor',
            editMode: true,
            padding: padding,
            overrides: const ReaderOverrides(),
            showPageFooter: false,
            onSessionReady: (value) => reader = value,
            onEditTarget: targets.add,
          ),
        ),
      ),
    );
    await pumpReaderUntilComplete(tester, () => reader?.page != null);
    final line = TextHitTester.lineBoxes(reader!.page!).last;
    expect(line.text, contains('结束'));
    final position =
        tester.getTopLeft(find.byType(ReaderView)) +
        padding.topLeft +
        Offset(line.rect.right - 2, line.rect.center.dy);
    await tester.tapAt(position);
    await pumpReaderUntilComplete(tester, () => targets.isNotEmpty);
    expect(targets, hasLength(1));
    await tester.longPressAt(position);
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑原文'));
    await tester.pumpAndSettle();
    expect(targets, hasLength(2));
    for (final target in targets) {
      expect(cfiCharOffset(target.cfi), isNull);
      final element = editor.session.resolveEditableElement(
        target.spineIndex,
        target.cfi,
      );
      expect(element.attributes['id'], 'paragraph');
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('显式校验展示原书已有断链告警', (tester) async {
    final editor = await _open(
      tester,
      firstChapter: '<p id="paragraph">原文<a href="legacy.xhtml">原有断链</a></p>',
    );
    final paragraph = editor.session
        .editableDocument(_chapter)
        .elements
        .firstWhere((element) => element.tag == 'p');
    editor.session.insertAfter(paragraph, '<p>新增正文</p>');
    await pumpReaderUntilComplete(
      tester,
      () => editor.previewRevision == editor.session.revision,
    );
    await _show(tester, editor, const Size(390, 844));
    await tester.tap(find.byTooltip('书籍工具'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('校验书籍'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('校验通过，原书仍有告警'), findsOneWidget);
    expect(find.textContaining('legacy.xhtml'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await pumpReaderUntilComplete(
      tester,
      () => find.byType(AlertDialog).evaluate().isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('手机class面板应用全书样式，正文HTML保持有效', (tester) async {
    final editor = await _open(tester);
    await _show(tester, editor, const Size(390, 844));
    tester.widget<ReaderPage>(find.byType(ReaderPage)).onEditTarget!(
      _target(editor),
    );
    await pumpReaderUntil(tester, find.byType(BookEditorElementSheet));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('class 样式'));
    await tester.pump();
    await tester.tap(find.text('.body'));
    await pumpReaderUntil(tester, find.text('全书 .body'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('全书 .body'), findsOneWidget);
    final color = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'color',
    );
    await tester.ensureVisible(color);
    await tester.enterText(color, '#663300');
    await tester.tap(find.text('应用全书样式'));
    await pumpReaderUntilComplete(
      tester,
      () =>
          ClassStyleEditor(editor.session)
              .inspect('body')
              .declarations['color'] ==
          '#663300',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      ClassStyleEditor(editor.session).inspect('body').declarations['color'],
      '#663300',
    );
    editor.session.validate();
    await pumpReaderUntilComplete(
      tester,
      () => find.byType(BookEditorElementSheet).evaluate().isEmpty,
    );
    expect(find.byType(BookEditorElementSheet), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('图片面板替换单处src和alt保持一撤销步', (tester) async {
    final editor = await _open(tester, withImages: true);
    await _show(tester, editor, const Size(390, 844));
    final parsed = DocumentParser.parse(
      xhtml: editor.session.readText(_chapter),
      spineIndex: 0,
    );
    tester.widget<ReaderPage>(find.byType(ReaderPage)).onEditTarget!(
      ReaderEditTarget(
        spineIndex: 0,
        cfi: parsed.elementById('picture')!.cfi.serialize(),
      ),
    );
    await pumpReaderUntil(tester, find.text('旧图片描述'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('旧图片描述'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is DropdownButtonFormField<String>,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('OEBPS/other.png').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const ValueKey('image-alt')), '新图片 & 描述');
    final history = editor.session.history.length;
    await tester.tap(find.text('应用图片修改'));
    await tester.pump(const Duration(milliseconds: 300));
    final image = editor.session
        .editableDocument(_chapter)
        .elements
        .firstWhere((node) => node.tag == 'img');
    expect(image.attributes['src'], 'other.png');
    expect(image.attributes['alt'], '新图片 & 描述');
    expect(editor.session.history.length, history + 1);
    editor.undo();
    final original = editor.session
        .editableDocument(_chapter)
        .elements
        .firstWhere((node) => node.tag == 'img');
    expect(original.attributes['src'], 'image.png');
    expect(original.attributes['alt'], '旧图片描述');
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('管理CSS与正文同批提交后源码同步最终内联覆盖，不留下待提交旧文本', (tester) async {
    final editor = await _open(tester);
    editor.session.transaction(
      '准备作者内联颜色',
      (tx) => tx.writeText(
        _chapter,
        tx
            .readText(_chapter)
            .replaceFirst('class="body"', 'class="body" style="color: blue"'),
      ),
    );
    final styles = ClassStyleEditor(editor.session);
    styles.apply('body', {'color': 'red'}, unifyConflicts: true);
    final html = editor.openDocument(_chapter);
    final css = editor.openDocument(styles.stylesheetPath);
    html.code.text = html.code.text.replaceFirst('原始正文', '同步正文');
    css.code.text = css.code.text.replaceAll('red', 'green');
    expect(editor.flush(), isTrue);
    expect(editor.hasPendingText, isFalse);
    expect(html.code.text, editor.session.readText(_chapter));
    expect(html.code.text, contains('green'));
    expect(html.code.text, contains('同步正文'));
  });

  testWidgets('预览切换书籍原始样式和当前阅读设置不写工作副本', (tester) async {
    final editor = await _open(
      tester,
      readingSettings: const ReaderSettings(fontSize: 24, themeId: 'night'),
    );
    await _show(tester, editor, const Size(390, 844));
    expect(find.text('预览'), findsOneWidget);
    expect(find.text('预览 · 点段落编辑'), findsNothing);
    expect(find.byTooltip('点击段落编辑'), findsOneWidget);
    var reader = tester.widget<ReaderPage>(find.byType(ReaderPage));
    expect(reader.overrides!.fontSize, isNull);
    editor.setPreviewSettings(true);
    await tester.pump();
    reader = tester.widget<ReaderPage>(find.byType(ReaderPage));
    expect(reader.overrides!.fontSize, 24);
    expect(editor.session.revision, 0);
    editor.setPreviewSettings(false);
    await tester.pump();
    reader = tester.widget<ReaderPage>(find.byType(ReaderPage));
    expect(reader.overrides!.fontSize, isNull);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('退出显示保存保留放弃；放弃等待旧草稿写入后再删除', (tester) async {
    final events = <String>[];
    final editor = await _open(
      tester,
      saveDraft: (_, _) async => events.add('写草稿'),
      discardDraft: () async => events.add('删除草稿'),
    );
    await _show(tester, editor, const Size(390, 844));
    editor.activeDocument!.code.text = '<html>';
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('退出编辑'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('保留草稿并退出'), findsOneWidget);
    expect(find.text('放弃修改并退出'), findsOneWidget);
    expect(find.text('保存书籍'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(await editor.discard(), isTrue);
    expect(events.last, '删除草稿');
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  testWidgets('源码300ms防抖；非法HTML保留输入和旧预览并可保存草稿', (tester) async {
    final drafts = <Map<String, String>>[];
    final editor = await _open(
      tester,
      saveDraft: (_, buffers) async => drafts.add(Map.of(buffers)),
    );
    final oldPreview = editor.previewSource;
    final doc = editor.openDocument(_chapter);
    final original = doc.code.text;
    doc.code.text = '<html>';
    await tester.pump(const Duration(milliseconds: 299));
    expect(editor.session.revision, 0);
    expect(editor.hasErrors, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    expect(editor.hasErrors, isTrue);
    expect(editor.previewSource, same(oldPreview));
    expect(doc.code.text, '<html>');
    await editor.persistDraft();
    expect(drafts.last[_chapter], '<html>');
    doc.code.text = original.replaceFirst('原始正文', '修订正文');
    await tester.pump(const Duration(milliseconds: 300));
    await pumpReaderUntilComplete(
      tester,
      () => editor.previewRevision == editor.session.revision,
    );
    expect(editor.hasErrors, isFalse);
    expect(editor.session.readText(_chapter), contains('修订正文'));
    expect(editor.previewSource, isNot(same(oldPreview)));
  });

  testWidgets('多文档切换保留缓冲，批量校验失败不部分提交，撤销同步源码', (tester) async {
    final editor = await _open(tester);
    final first = editor.openDocument(_chapter);
    final original = first.code.text;
    first.code.text = original.replaceFirst('原始正文', '有效修改');
    final second = editor.openDocument('OEBPS/c2.xhtml');
    final secondOriginal = second.code.text;
    second.code.text = '<html>';
    editor.openDocument(_chapter);
    expect(first.code.text, contains('有效修改'));
    expect(editor.flush(), isFalse);
    expect(editor.session.revision, 0);
    expect(editor.session.readText(_chapter), original);
    second.code.text = secondOriginal;
    expect(editor.flush(), isTrue);
    editor.undo();
    expect(first.code.text, original);
    expect(editor.hasPendingText, isFalse);
  });

  testWidgets('手机预览段落入口修改正文保留行内结构，预览使用内存进度', (tester) async {
    final editor = await _open(tester);
    await _show(tester, editor, const Size(390, 844));
    final reader = tester.widget<ReaderPage>(find.byType(ReaderPage));
    expect(reader.store, isA<MemoryReaderProgressStore>());
    expect(reader.editMode, isTrue);
    reader.onEditTarget!(_target(editor));
    await pumpReaderUntil(tester, find.byType(BookEditorElementSheet));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(BookEditorElementSheet), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('element-text')),
      '修订正文与行内强调继续阅读。',
    );
    await tester.tap(find.text('应用修改'));
    await tester.pump();
    expect(editor.session.readText(_chapter), contains('修订正文'));
    expect(editor.session.readText(_chapter), contains('<em>行内强调</em>'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(BookEditorElementSheet), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面多栏同屏且可调整分栏，标签切换保留文档内容', (tester) async {
    final editor = await _open(tester);
    await _show(tester, editor, const Size(1360, 900));
    expect(find.byType(BookEditorSource), findsOneWidget);
    expect(find.byType(BookEditorPreview), findsOneWidget);
    final before = tester.getSize(find.byType(BookEditorSource)).width;
    final separators = find.bySemanticsLabel('调整分栏宽度');
    await tester.drag(separators.last, const Offset(70, 0));
    await tester.pump();
    expect(
      tester.getSize(find.byType(BookEditorSource)).width,
      greaterThan(before),
    );
    editor.openDocument('OEBPS/c2.xhtml');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('document-OEBPS/c1.xhtml')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('document-OEBPS/c2.xhtml')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存失败保留修改与草稿，禁止无效源码提交', (tester) async {
    var attempts = 0;
    final editor = await _open(
      tester,
      commit: (_) async {
        attempts++;
        throw StateError('模拟磁盘写入失败');
      },
    );
    final doc = editor.openDocument(_chapter);
    doc.code.text = doc.code.text.replaceFirst('原始正文', '待保存正文');
    expect(await editor.save(), isFalse);
    expect(editor.dirty, isTrue);
    expect(editor.error, contains('磁盘写入失败'));
    doc.code.text = '<html>';
    expect(await editor.save(), isFalse);
    expect(attempts, 1);
    expect(doc.code.text, '<html>');
  });
}
