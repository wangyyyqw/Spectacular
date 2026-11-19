import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_mobile/editing/book_editor_controller.dart';
import 'package:reader_mobile/editing/book_editor_page.dart';
import 'package:reader_mobile/editing/book_editor_toolkit.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:spectacular_epub_tools/local_epub_tools.dart';

import '../support/local_toolkit_fixture.dart';
import '../support/reader_pump.dart';
import '../support/test_epub.dart';

Future<({BookEditorController editor, Directory directory})> _open(
  WidgetTester tester, {
  String first = '<p id="原路径">皇后头发与数据库😀</p>',
}) async {
  late Directory directory;
  late EpubEditSession session;
  await tester.runAsync(() async {
    directory = await Directory.systemTemp.createTemp('editor-toolkit-');
    final input = File('${directory.path}/original.epub');
    await input.writeAsBytes(
      buildMultiChapterEpub(
        chapters: [first, '<p>第二章：软件与书籍</p>'],
        rawBody: true,
      ),
    );
    session = await EpubEditSession.open(input);
  });
  final editor = BookEditorController(
    session: session,
    commit: (session) =>
        EpubWriter.write(session, File('${directory.path}/saved.epub')),
    export: (session) =>
        EpubWriter.write(session, File('${directory.path}/exported.epub')),
  );
  addTearDown(() async {
    editor.dispose();
    await directory.delete(recursive: true);
  });
  await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
  return (editor: editor, directory: directory);
}

Future<BookEditorToolResult> _run(
  WidgetTester tester,
  BookEditorController editor,
  LocalEpubTool tool, {
  Map<String, Object?> options = const {},
}) async {
  final result = await pumpReaderTask(
    tester,
    BookEditorToolkit(editor).run(tool, options: options),
  );
  expect(result, isNotNull, reason: editor.error);
  addTearDown(() => tester.runAsync(result!.dispose));
  await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
  return result!;
}

void main() {
  testWidgets('简繁处理使用未保存缓冲，保留路径与 ID，撤销、草稿、保存及导出正常', (tester) async {
    final (:editor, :directory) = await _open(tester);
    final session = editor.session;
    final original = await tester.runAsync(session.baseFile.readAsBytes);
    final doc = editor.openDocument('OEBPS/c1.xhtml');
    doc.code.text = doc.code.text.replaceFirst('数据库', '数据库与后台');
    final output = await _run(tester, editor, LocalEpubTool.s2t);
    expect(output.applied, isTrue);
    expect(session.history.last.label, '简体转繁体');
    expect(doc.code.text, contains('皇后頭髮與數據庫與後臺😀'));
    expect(doc.code.text, contains('id="原路径"'));
    expect(session.spinePaths.first, 'OEBPS/c1.xhtml');
    expect(await tester.runAsync(session.baseFile.readAsBytes), original);

    final restored = await tester.runAsync(
      () => EpubEditSession.open(session.baseFile, draft: session.toDraft()),
    );
    expect(restored!.readText('OEBPS/c1.xhtml'), doc.code.text);
    restored.close();
    editor.undo();
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
    expect(doc.code.text, contains('皇后头发与数据库与后台'));
    editor.redo();
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
    expect(doc.code.text, contains('皇后頭髮'));
    expect(await pumpReaderTask(tester, editor.save()), isTrue);
    expect(await pumpReaderTask(tester, editor.exportBook()), isTrue);
    for (final name in ['saved', 'exported']) {
      final reopened = await tester.runAsync(
        () =>
            openEpubFile(File('${directory.path}/$name.epub'), verifyCrc: true),
      );
      expect(reopened!.ok, isTrue);
      expect(reopened.document!.chapterXhtml(0), contains('皇后頭髮'));
      reopened.document!.archive.close();
    }
  });

  testWidgets('版本与结构转换接入工作副本，目录重建可同步 NAV/NCX 并撤销', (tester) async {
    final (:editor, directory: _) = await _open(tester);
    await _run(tester, editor, LocalEpubTool.epub2);
    expect(
      editor.session.readText(editor.session.opfPath),
      contains('version="2.0"'),
    );
    await _run(tester, editor, LocalEpubTool.epub3);
    final inspected = await _run(
      tester,
      editor,
      LocalEpubTool.navigation,
      options: {'regenerate': true},
    );
    final navigation = inspected.result.data! as EpubNavigationDocument;
    expect(navigation.entries(NavigationSection.toc), hasLength(2));
    final before = editor.session.revision;
    await _run(
      tester,
      editor,
      LocalEpubTool.saveNavigation,
      options: {'navigation': navigation},
    );
    expect(editor.session.revision, before + 1);
    final reader = editor.previewSource!;
    expect(await tester.runAsync(() => reader.loadChapter(0)), isNotEmpty);
    editor.undo();
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
    await _run(tester, editor, LocalEpubTool.reformat);
    expect(editor.session.spinePaths.first, contains('Text/'));
  });

  testWidgets('非法转换与非法源码不应用结果，不返回假成功', (tester) async {
    final (:editor, directory: _) = await _open(tester);
    final before = editor.session.revision;
    final failed = await pumpReaderTask(
      tester,
      BookEditorToolkit(editor)
          .run(LocalEpubTool.cleanText, options: {'patterns': '[|||'}),
    );
    expect(failed, isNull);
    expect(editor.error, isNotNull);
    expect(editor.session.revision, before);
    editor.openDocument('OEBPS/c1.xhtml').code.text = '<html>';
    final invalid = await pumpReaderTask(
      tester,
      BookEditorToolkit(editor).run(LocalEpubTool.s2t),
    );
    expect(invalid, isNull);
    expect(editor.hasPendingText, isTrue);
    expect(editor.session.revision, before);
    expect(editor.session.readText('OEBPS/c1.xhtml'), contains('皇后头发'));
  });

  testWidgets('合并使用当前修订副本，拆分生成独立 EPUB 而不改当前书', (tester) async {
    final (:editor, :directory) = await _open(tester);
    final other = File('${directory.path}/other.epub');
    await tester.runAsync(
      () => other.writeAsBytes(
        buildMultiChapterEpub(chapters: ['外部书籍'], identifier: 'second-book'),
      ),
    );
    editor.openDocument('OEBPS/c1.xhtml').code.text = editor
        .activeDocument!
        .code
        .text
        .replaceFirst('皇后头发', '合并前已修订');
    await _run(
      tester,
      editor,
      LocalEpubTool.merge,
      options: {
        'inputPaths': [other.path],
        'title': '合并测试',
      },
    );
    expect(
      editor.session.spinePaths.where((path) => !path.endsWith('/nav.xhtml')),
      hasLength(3),
    );
    expect(
      editor.session.readText(editor.session.spinePaths.first),
      contains('合并前已修订'),
    );
    final targets = await _run(tester, editor, LocalEpubTool.splitTargets);
    final splitTargets = targets.result.data! as List<SplitTarget>;
    expect(splitTargets.length, greaterThanOrEqualTo(2));
    final before = editor.session.revision;
    final split = await _run(
      tester,
      editor,
      LocalEpubTool.split,
      options: {
        'splitPoints': [
          splitTargets.indexWhere((target) => target.href.contains('c2.xhtml')),
        ],
      },
    );
    expect(split.applied, isFalse);
    expect(editor.session.revision, before);
    expect(split.result.files, hasLength(2));
    for (final file in split.result.files) {
      final opened = await tester.runAsync(
        () => openEpubFile(File(file), verifyCrc: true),
      );
      expect(opened!.ok, isTrue);
      opened.document!.archive.close();
    }
  });

  testWidgets('菜单仅包含 EPUB 编辑工具；正则错误、预览命中和取消正常', (tester) async {
    final (:editor, directory: _) = await _open(tester);
    tester.view
      ..physicalSize = const Size(1200, 760)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: BookEditorPage(controller: editor, title: '工具入口测试'),
      ),
    );
    await pumpReaderUntil(tester, find.byType(PageTurnView));
    final session = tester
        .widget<PageTurnView>(find.byType(PageTurnView))
        .session;
    await pumpReaderUntilComplete(
      tester,
      () => session.page != null && !session.loading,
    );
    await tester.tap(find.widgetWithText(SubmenuButton, '工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('本地 EPUB 工具'));
    await tester.pumpAndSettle();
    expect(find.textContaining('TXT'), findsNothing);
    for (final label in ['转换', '结构', '图片', '字体', '注释与正文']) {
      expect(find.widgetWithText(Tab, label), findsOneWidget);
    }
    await tester.tap(find.widgetWithText(Tab, '注释与正文'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('广告规则清理'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '清理正则'), '[');
    await tester.tap(find.text('预览命中'));
    await tester.pump();
    expect(find.textContaining('正则无效'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '清理正则'), '皇后头发');
    await tester.tap(find.text('预览命中'));
    await tester.pump();
    expect(find.textContaining('源码命中 1 处'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(editor.session.revision, 0);
    expect(editor.busy, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('简繁不改 CSS、代码片段、链接路径和属性身份', (tester) async {
    final (:editor, directory: _) = await _open(
      tester,
      first: '<p id="头发" class="数据库">头发<a href="#头发" title="头发">软件</a></p><pre>头发</pre>',
    );
    PackageEditor(editor.session).addResource(
      'OEBPS/头发.css',
      utf8.encode('.数据库 { color: red; }'),
      'text/css',
    );
    await _run(tester, editor, LocalEpubTool.s2t);
    final source = editor.session.readText('OEBPS/c1.xhtml');
    expect(source, contains('id="头发" class="数据库"'));
    expect(source, contains('href="#头发" title="頭髮"'));
    expect(source, contains('<pre>头发</pre>'));
    expect(editor.session.readText('OEBPS/头发.css'), '.数据库 { color: red; }');
  });

  testWidgets('结构重排保留已有 class 样式归属，后续恢复作者声明仍正常', (tester) async {
    final (:editor, directory: _) = await _open(
      tester,
      first: '<p id="styled" class="managed" style="font-size:14px">正文</p>',
    );
    ClassStyleEditor(editor.session)
        .apply('managed', {'font-size': '20px'}, unifyConflicts: true);
    await _run(tester, editor, LocalEpubTool.reformat);
    final stylesheet = editor.session.metadata['classStylesheet'] as String;
    expect(stylesheet, startsWith('OEBPS/Styles/'));
    expect(editor.session.readBytes(stylesheet), isNotNull);
    ClassStyleEditor(editor.session).apply('managed', {'font-size': ''});
    expect(
      editor.session.readText(editor.session.spinePaths.first),
      contains('style="font-size:14px"'),
    );
  });

  testWidgets('图片处理与水印通过工作副本执行，回写引用并保留横向预览', (tester) async {
    final (:editor, directory: _) = await _open(
      tester,
      first: '<p>图片正文<img src="picture.bmp" alt="测试图片"/></p>',
    );
    PackageEditor(
      editor.session,
    ).addResource('OEBPS/picture.bmp', buildLocalToolkitBitmap(), 'image/bmp');
    await _run(tester, editor, LocalEpubTool.compress);
    expect(editor.session.readText('OEBPS/c1.xhtml'), contains('picture.jpg'));
    await _run(tester, editor, LocalEpubTool.toWebp);
    expect(editor.session.readText('OEBPS/c1.xhtml'), contains('picture.webp'));
    await _run(tester, editor, LocalEpubTool.fromWebp);
    expect(
      editor.session.readText('OEBPS/c1.xhtml'),
      isNot(contains('picture.webp')),
    );
    await _run(
      tester,
      editor,
      LocalEpubTool.watermark,
      options: {'watermarkText': '编辑测试水印'},
    );
    final inspected = await _run(tester, editor, LocalEpubTool.readWatermark);
    expect(inspected.result.message, contains('编辑测试水印'));
    expect(editor.error, isNull);
    final page = await tester.runAsync(
      () => editor.previewSource!.loadChapter(0),
    );
    expect(page, isNotEmpty);
  });

  testWidgets('字体扫描、子集与加密使用真实字体，撤销恢复正文与原字体', (tester) async {
    final (:editor, directory: _) = await _open(
      tester,
      first: '<p class="probe">AB A</p>',
    );
    final font = await tester.runAsync(
      () => File(
        '../../packages/epub_toolkit/test/support/media_complex_probe.ttf',
      ).readAsBytes(),
    );
    final package = PackageEditor(editor.session);
    package.addResource('OEBPS/probe.ttf', font!, 'font/ttf');
    package.addResource(
      'OEBPS/probe.css',
      utf8.encode(
        '@font-face { font-family: Probe; src: url("probe.ttf"); } .probe { font-family: Probe; }',
      ),
      'text/css',
    );
    editor.session.transaction(
      '字体引用',
      (tx) => tx.writeText(
        'OEBPS/c1.xhtml',
        tx
            .readText('OEBPS/c1.xhtml')
            .replaceFirst(
              '</head>',
              '<link rel="stylesheet" href="probe.css"/></head>',
            ),
      ),
    );
    final targets = await _run(tester, editor, LocalEpubTool.fontTargets);
    expect(
      (targets.result.data! as FontEncryptTargets).fontFamilies,
      contains('Probe'),
    );
    await _run(tester, editor, LocalEpubTool.subsetFont);
    expect(
      editor.session.readBytes('OEBPS/probe.ttf')!.length,
      lessThan(font.length),
    );
    final before = editor.session.readBytes('OEBPS/probe.ttf');
    await _run(
      tester,
      editor,
      LocalEpubTool.encryptFont,
      options: {
        'fontFamilies': ['Probe'],
        'xhtmlFiles': ['OEBPS/c1.xhtml'],
      },
    );
    expect(
      editor.session.readText('OEBPS/c1.xhtml'),
      isNot(contains('>AB A</p>')),
    );
    editor.undo();
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
    expect(editor.session.readText('OEBPS/c1.xhtml'), contains('>AB A</p>'));
    expect(editor.session.readBytes('OEBPS/probe.ttf'), before);
  });

  testWidgets('正则清理、三种注释转换和名称混淆往返实际应用', (tester) async {
    final (:editor, directory: _) = await _open(
      tester,
      first:
          '<p>正文广告【测试注释】<a href="#note">1</a></p><aside id="note">脚注说明</aside>',
    );
    await _run(
      tester,
      editor,
      LocalEpubTool.cleanText,
      options: {'patterns': '广告|||'},
    );
    expect(editor.session.readText('OEBPS/c1.xhtml'), isNot(contains('广告')));
    await _run(
      tester,
      editor,
      LocalEpubTool.comment,
      options: {'pattern': r'【(.*?)】'},
    );
    expect(
      editor.session.readText('OEBPS/c1.xhtml'),
      contains('data-wr-footernote="测试注释"'),
    );
    await _run(tester, editor, LocalEpubTool.commentToFootnote);
    expect(editor.session.readText('OEBPS/c1.xhtml'), contains('测试注释'));
    await _run(
      tester,
      editor,
      LocalEpubTool.footnoteToComment,
      options: {'pattern': '^#'},
    );
    expect(
      editor.session.readText('OEBPS/c1.xhtml'),
      contains('data-wr-footernote='),
    );
    final beforePaths = editor.session.spinePaths;
    final beforeText = editor.session.readText(beforePaths.first);
    await _run(tester, editor, LocalEpubTool.encryptNames);
    expect(editor.session.spinePaths, isNot(beforePaths));
    await _run(tester, editor, LocalEpubTool.decryptNames);
    expect(editor.session.spinePaths, beforePaths);
    expect(editor.session.readText(beforePaths.first), contains('测试注释'));
    expect(editor.session.readText(beforePaths.first), beforeText);
  });

  testWidgets('拼音参数通过编辑桥接生效，保留已有注音并可撤销和导出', (tester) async {
    final (:editor, :directory) = await _open(
      tester,
      first: '<p id="原路径">中文龘<ruby>好<rt>hǎo</rt></ruby><code>中文</code>😀</p>',
    );
    final before = editor.session.readText('OEBPS/c1.xhtml');
    await _run(
      tester,
      editor,
      LocalEpubTool.phonetic,
      options: {'toneMode': 'number', 'annotateAll': true},
    );
    final annotated = editor.session.readText('OEBPS/c1.xhtml');
    expect(annotated, contains('<ruby>中<rt>zhong1</rt></ruby>'));
    expect(annotated, contains('<ruby>龘<rt>da2</rt></ruby>'));
    expect(annotated, contains('<ruby>好<rt>hǎo</rt></ruby>'));
    expect(annotated, contains('<code>中文</code>😀'));
    expect(annotated, contains('id="原路径"'));
    expect(await pumpReaderTask(tester, editor.exportBook()), isTrue);
    final reopened = await tester.runAsync(
      () => openEpubFile(
        File('${directory.path}/exported.epub'),
        verifyCrc: true,
      ),
    );
    expect(reopened!.ok, isTrue);
    expect(reopened.document!.chapterXhtml(0), contains('zhong1'));
    reopened.document!.archive.close();
    editor.undo();
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
    expect(editor.session.readText('OEBPS/c1.xhtml'), before);
  });

  testWidgets('体检不改工作副本，选择性修复资源媒体类型可复检和撤销', (tester) async {
    final (:editor, directory: _) = await _open(tester);
    PackageEditor(editor.session).addResource(
      'OEBPS/repair.css',
      utf8.encode('p { color: #333333; }'),
      'text/plain',
    );
    final revision = editor.session.revision;
    final inspected = await _run(tester, editor, LocalEpubTool.health);
    expect(inspected.applied, isFalse);
    expect(editor.session.revision, revision);
    final report = inspected.result.data! as EpubHealthReport;
    final fix = report.fixes.singleWhere(
      (fix) => fix.kind == 'correctMediaType',
    );
    await _run(
      tester,
      editor,
      LocalEpubTool.repair,
      options: {
        'selectedFixIds': [fix.id],
      },
    );
    expect(
      editor.session.readText(editor.session.opfPath),
      contains('text/css'),
    );
    final checked = await _run(tester, editor, LocalEpubTool.health);
    expect(
      (checked.result.data! as EpubHealthReport).issues.where(
        (issue) => issue.code == 'manifest-media-type',
      ),
      isEmpty,
    );
    editor.undo();
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
    expect(
      editor.session.readText(editor.session.opfPath),
      contains('media-type="text/plain"'),
    );
  });
}
