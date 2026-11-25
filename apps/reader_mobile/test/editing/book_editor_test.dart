import 'dart:io';
import 'dart:convert';

import 'package:reader_ui/theme/reader_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
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
import 'package:reader_mobile/editing/book_editor_inspector.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

const _chapter = 'OEBPS/c1.xhtml';

Future<BookEditorController> _open(
  WidgetTester tester, {
  SaveEditorDraft? saveDraft,
  CommitEditor? commit,
  CommitEditor? export,
  ReaderSettings? readingSettings,
  Future<void> Function()? discardDraft,
  bool withImages = false,
  String? firstChapter,
  String? secondChapter,
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
          secondChapter ?? '<p>第二章节正文。</p>',
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
    export: export,
    readingSettings: readingSettings,
    discardDraft: discardDraft,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    editor.dispose();
    // 文件归档异步关闭后再清理，Windows 不允许删除仍被占用的 EPUB。
    await tester.runAsync(() async {
      final target = temporary.absolute.path;
      expect(target, startsWith(Directory.systemTemp.absolute.path));
      for (var attempt = 0; attempt < 10; attempt++) {
        try {
          await temporary.delete(recursive: true);
          return;
        } on PathAccessException {
          if (attempt == 9) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });
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
  testWidgets('CRLF 源码首次打开保留换行且不触发修改和构建期通知', (tester) async {
    final editor = await _open(
      tester,
      firstChapter: '<p id="paragraph">第一行正文。</p>\r\n<p>第二行正文。</p>',
    );
    final original = editor.session.readText(_chapter);
    await _show(tester, editor, const Size(1360, 900));
    expect(editor.activeDocument!.code.text, original);
    expect(editor.dirty, isFalse);
    expect(editor.hasPendingText, isFalse);
    expect(editor.session.changedPaths, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

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
      () => find
          .byWidgetPredicate((widget) => widget is AlertDialog)
          .evaluate()
          .isEmpty,
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
    expect(find.byType(ReaderSheetForm), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
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
    await pumpReaderUntil(tester, find.byType(ReaderSheetForm));
    final imageRoute = ModalRoute.of(
      tester.element(find.byType(ReaderSheetForm)),
    )!;
    await pumpReaderUntilComplete(
      tester,
      () => imageRoute.animation!.status == AnimationStatus.completed,
      description: '图片编辑抽屉入场',
    );
    expect(find.byType(ReaderSheetForm), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is ReaderDropdownButtonFormField<String>,
      ),
    );
    await pumpReaderUntil(tester, find.text('OEBPS/other.png'));
    final option = find.text('OEBPS/other.png').last;
    final dropdownRoute = ModalRoute.of(tester.element(option))!;
    await pumpReaderUntilComplete(
      tester,
      () =>
          dropdownRoute.animation!.status == AnimationStatus.completed &&
          option.hitTestable().evaluate().isNotEmpty,
      description: '图片资源下拉选项入场',
    );
    await tester.tap(option);
    await pumpReaderTask(tester, dropdownRoute.completed);
    await tester.enterText(find.byKey(const ValueKey('image-alt')), '新图片 & 描述');
    final history = editor.session.history.length;
    await tester.tap(find.text('应用图片修改'));
    await pumpReaderUntilComplete(
      tester,
      () =>
          find.byType(ReaderSheetForm).evaluate().isEmpty &&
          find.byType(BookEditorElementSheet).evaluate().isEmpty,
      description: '图片编辑与段落抽屉退场',
    );
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
        throw const FileSystemException('磁盘写入失败：空间不足', '', OSError('空间不足', 28));
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

  testWidgets('取消系统导出保留修改并允许重试', (tester) async {
    var attempts = 0;
    final editor = await _open(
      tester,
      export: (_) async {
        attempts++;
        if (attempts == 1) throw const EditorExportCancelled();
      },
    );
    final paragraph = editor.session
        .editableDocument(_chapter)
        .elements
        .firstWhere((node) => node.tag == 'p');
    editor.session.insertAfter(paragraph, '<p>未保存正文</p>');
    expect(await editor.exportBook(), isFalse);
    expect(editor.busy, isFalse);
    expect(editor.error, isNull);
    expect(editor.dirty, isTrue);
    expect(await editor.exportBook(), isTrue);
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
  });

  testWidgets('源码光标跨章节定位到正式预览，非法输入不跳转', (tester) async {
    final editor = await _open(tester);
    ReaderSession? reader;
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: editor,
          builder: (_, _) => BookEditorPreview(
            source: editor.previewSource!,
            revision: editor.previewRevision,
            target: editor.previewTarget,
            navigation: editor.previewNavigation,
            onEditTarget: (_) {},
            onSessionReady: (value) => reader = value,
          ),
        ),
      ),
    );
    await pumpReaderUntilComplete(tester, () => reader?.page != null);
    final doc = editor.openDocument(
      'OEBPS/c2.xhtml',
      offset: editor.session.readText('OEBPS/c2.xhtml').indexOf('第二章节'),
    );
    await tester.pump();
    expect(await editor.locateSource(), isNotNull);
    await pumpReaderUntilComplete(
      tester,
      () => reader?.progress?.spineIndex == 1 && !reader!.loading,
    );
    expect(
      (await editor.previewSource!.loadAnchorChapter(1)).text,
      contains('第二章节'),
    );
    expect(editor.session.revision, 0);
    final navigation = editor.previewNavigation;
    doc.code.text = '<html>';
    await tester.pump(const Duration(milliseconds: 300));
    expect(await editor.locateSource(), isNull);
    await tester.pump();
    expect(editor.previewNavigation, navigation);
    expect(reader!.progress!.spineIndex, 1);
    expect(doc.code.text, '<html>');
    await tester.pumpWidget(const SizedBox());
    editor.previewSource!.close();
    await pumpReaderTask(tester, editor.previewSource!.preparationsStopped);
    expect(tester.takeException(), isNull);
  });

  testWidgets('折叠源码保留 UTF-16 定位，预览反向定位展开嵌套行', (tester) async {
    final editor = await _open(
      tester,
      firstChapter:
          '<section>\n<div>\n<p id="nested">嵌套正文</p>\n</div>\n</section>\n'
          '<p id="paragraph">中文😀目标正文</p>',
    );
    final doc = editor.openDocument(_chapter);
    final lines = doc.code.text.split('\n');
    final section = lines.indexWhere((line) => line.contains('<section>'));
    final nested = lines.indexWhere((line) => line.contains('id="nested"'));
    final target = lines.indexWhere((line) => line.contains('id="paragraph"'));
    doc.code.collapseChunk(section + 1, section + 3);
    doc.code.collapseChunk(section, doc.code.lineIndex2Index(target).index);
    expect(
      doc.code.lineIndex2Index(nested).chunkIndex,
      greaterThanOrEqualTo(0),
    );
    editor.openDocument(_chapter, offset: doc.code.text.indexOf('嵌套正文'));
    expect(doc.code.unfoldLineSelection.extentIndex, nested);
    expect(doc.code.lineIndex2Index(nested).chunkIndex, -1);

    doc.code.collapseChunk(section, target);
    doc.code.selection = CodeLineSelection.collapsed(
      index: doc.code.lineIndex2Index(target).index,
      offset: lines[target].indexOf('目标正文'),
    );
    final element = await editor.locateSource();
    expect(element?.attributes['id'], 'paragraph');
    expect(element?.sourceStart, doc.code.text.indexOf('<p id="paragraph"'));
    expect(doc.code.unfoldLineSelection.extentIndex, target);
    expect(editor.session.revision, 0);
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
  });

  testWidgets('源码底部查找替换与样式检查器左右切换，打开查找不回跳', (tester) async {
    final editor = await _open(
      tester,
      firstChapter: '<p id="paragraph" class="body">正文</p>',
    );
    await _show(tester, editor, const Size(1360, 900));
    expect(find.text('查找替换'), findsOneWidget);
    expect(find.text('样式检查器'), findsOneWidget);
    expect(find.byType(EditorFindBar), findsOneWidget);
    expect(find.text('点击预览元素或从源码定位，查看样式。'), findsNothing);

    await tester.tap(find.text('样式检查器'));
    await tester.pump();
    expect(find.byType(EditorFindBar), findsNothing);
    expect(find.byType(BookEditorInspector), findsNothing);
    expect(find.text('点击预览元素或从源码定位，查看样式。'), findsOneWidget);

    tester.widget<ReaderPage>(find.byType(ReaderPage)).onEditTarget!(
      _target(editor),
    );
    await tester.pump();
    expect(find.byType(BookEditorInspector), findsOneWidget);

    await tester.tap(find.text('查找替换'));
    await tester.pump();
    expect(find.byType(EditorFindBar), findsOneWidget);
    expect(find.byType(BookEditorInspector), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('全书查找范围限制文件，结果片段高亮命中词', (tester) async {
    final editor = await _open(
      tester,
      firstChapter: '<p id="paragraph">目标词出现两次：目标词。</p>',
      secondChapter: '<p>第二章也有目标词。</p>',
    );
    await _show(tester, editor, const Size(1360, 900));
    await tester.tap(find.byTooltip('全书查找替换'));
    await pumpReaderUntil(tester, find.text('全书源码查找替换'));
    final queryField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '查找内容',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(queryField, '目标词');
    final findButton = find.widgetWithText(TextButton, '查找');
    await tester.ensureVisible(findButton);
    await tester.tap(findButton);
    await tester.pump();
    expect(find.text('3 处匹配'), findsOneWidget);
    bool hasHighlight(InlineSpan span) =>
        span is TextSpan &&
        (span.style?.backgroundColor != null ||
            (span.children?.any(hasHighlight) ?? false));
    expect(
      find.byWidgetPredicate(
        (widget) => widget is RichText && hasHighlight(widget.text),
      ),
      findsWidgets,
    );

    await tester.tap(find.text('所有文本文件'));
    for (
      var index = 0;
      index < 10 && find.text('当前文件').hitTestable().evaluate().isEmpty;
      index++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('当前文件').hitTestable());
    for (
      var index = 0;
      index < 10 && find.text('2 处匹配').evaluate().isEmpty;
      index++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('2 处匹配'), findsOneWidget);
    expect(find.byKey(const ValueKey('search-result-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-result-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-result-2')), findsNothing);
    await tester.tap(find.text('关闭'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('桌面检查器显示精确元素、多类选择、全书属性入口并可折叠', (tester) async {
    final editor = await _open(
      tester,
      firstChapter: '<p id="paragraph" class="body extra">正文<em>行内</em></p>',
    );
    await _show(tester, editor, const Size(1360, 900));
    tester.widget<ReaderPage>(find.byType(ReaderPage)).onEditTarget!(
      _target(editor),
    );
    await tester.pump();
    expect(find.byType(BookEditorElementSheet), findsNothing);
    expect(find.byType(BookEditorInspector), findsOneWidget);
    expect(find.text('.body'), findsOneWidget);
    expect(find.text('.extra'), findsOneWidget);
    await tester.tap(find.text('.body'));
    await pumpReaderUntil(tester, find.text('编辑全书 .body 属性'));
    await tester.ensureVisible(find.text('编辑全书 .body 属性'));
    await tester.tap(find.text('编辑全书 .body 属性'));
    await pumpReaderUntil(tester, find.text('全书 .body'));
    Navigator.of(tester.element(find.text('全书 .body'))).pop();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('查找替换'));
    await tester.pump();
    expect(find.byType(BookEditorInspector), findsNothing);
    expect(find.byType(EditorFindBar), findsOneWidget);
    await tester.tap(find.text('样式检查器'));
    await tester.pump();
    expect(find.byType(BookEditorInspector), findsOneWidget);
    editor.session.insertAfter(
      editor.session
          .editableDocument(_chapter)
          .elements
          .firstWhere((node) => node.tag == 'p'),
      '<p>新正文</p>',
    );
    await tester.pump();
    expect(find.byType(BookEditorInspector), findsNothing);
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
    await tester.pumpWidget(const SizedBox());
    editor.previewSource!.close();
    await pumpReaderTask(tester, editor.previewSource!.preparationsStopped);
    expect(tester.takeException(), isNull);
  });
}
