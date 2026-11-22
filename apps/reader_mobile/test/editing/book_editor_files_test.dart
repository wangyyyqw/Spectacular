import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_mobile/diagnostics/reader_log.dart';
import 'package:reader_mobile/editing/book_editor_controller.dart';
import 'package:reader_mobile/editing/book_editor_tools.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

const _first = 'OEBPS/c1.xhtml';
const _second = 'OEBPS/c2.xhtml';
const _extra = 'OEBPS/附录.xhtml';
const _left = 'OEBPS/Book/Volume-One/原排版/theme.css';
const _right = 'OEBPS/Book/Volume-Two/原排版/theme.css';

Future<BookEditorController> _openBook(WidgetTester tester) async {
  late Directory temporary;
  late EpubEditSession session;
  await tester.runAsync(() async {
    temporary = await Directory.systemTemp.createTemp('book-browser-');
    final file = File('${temporary.path}/book.epub');
    await file.writeAsBytes(buildMultiChapterEpub(chapters: ['第一段', '命中正文']));
    session = await EpubEditSession.open(file);
    final package = PackageEditor(session);
    package.reorderChapters([_second, _first]);
    package.addResource(_extra, session.readBytes(_first)!, 'application/xhtml+xml');
    for (final path in [_left, _right]) {
      package.addResource(path, utf8.encode('p { color: red; }'), 'text/css');
    }
    package.addResource('OEBPS/typeface', utf8.encode('12345'), 'application/font-sfnt');
    package.addResource('OEBPS/vector.svg', utf8.encode('<svg/>'), 'image/svg+xml');
    package.addResource(
      'OEBPS/picture',
      base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='),
      'image/png',
    );
  });
  final editor = BookEditorController(session: session);
  addTearDown(() async {
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
    await tester.pumpWidget(const SizedBox.shrink());
    editor.dispose();
    await tester.runAsync(() => temporary.delete(recursive: true));
  });
  await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
  return editor;
}

Future<void> _mount(
  WidgetTester tester,
  BookEditorController editor, {
  double width = 200,
  VoidCallback? onOpen,
}) => tester.pumpWidget(MaterialApp(
  theme: buildAppTheme(),
  home: Scaffold(body: SizedBox(
    width: width,
    child: BookEditorFiles(editor: editor, onOpen: onOpen ?? () {}),
  )),
));

Finder _row(String path) => find.byKey(ValueKey(path));

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pumpAndSettle();
}

Future<void> _menu(WidgetTester tester, String path) async {
  await tester.tap(find.descendant(of: _row(path), matching: find.byTooltip('文件操作')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('200 宽正文遵循 spine，筛选真实路径后打开正确的同名文件', (tester) async {
    final editor = await _openBook(tester);
    var opens = 0;
    await _mount(tester, editor, onOpen: () => opens++);
    for (final label in ['正文', '样式', '图片', '字体', '其他资源']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.getTopLeft(_row(_second)).dy, lessThan(tester.getTopLeft(_row(_first)).dy));
    expect(tester.getTopLeft(_row(_first)).dy, lessThan(tester.getTopLeft(_row(_extra)).dy));
    await tester.tap(find.text('正文'));
    await tester.pump();
    expect(_row(_extra), findsNothing);
    await _search(tester, 'THEME.CSS');
    expect(find.text('theme.css'), findsNWidgets(2));
    expect(find.byTooltip(_left), findsOneWidget);
    expect(find.byTooltip(_right), findsOneWidget);
    await _menu(tester, _right);
    expect(find.text(_right), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    await _search(tester, 'book/VOLUME-TWO/原排版');
    expect(_row(_left), findsNothing);
    await tester.tap(find.text('theme.css'));
    await tester.pump();
    expect(editor.activePath, _right);
    expect(tester.widget<ListTile>(_row(_right)).selected, isTrue);
    expect(opens, 1);
    await _search(tester, '不存在的路径');
    expect(find.text('没有匹配的文件'), findsOneWidget);
    await tester.tap(find.byTooltip('清除筛选'));
    await tester.pump();
    expect(_row(_extra), findsNothing);
    expect(find.text('样式'), findsOneWidget);
  });

  testWidgets('250 宽以声明识别无扩展名的字体和图片，SVG 仍可开源码', (tester) async {
    final log = ReaderLog.instance;
    log.resetForTest();
    addTearDown(log.resetForTest);
    final editor = await _openBook(tester);
    var opens = 0;
    await _mount(tester, editor, width: 250, onOpen: () => opens++);
    await _search(tester, 'typeface');
    expect(find.text('字体'), findsOneWidget);
    await tester.tap(_row('OEBPS/typeface'));
    await tester.pump();
    expect(
      await pumpReaderTask(tester, log.exportText()),
      contains(' | editor_file_info_opened'),
    );
    expect(find.byType(SnackBar), findsNothing);
    await _search(tester, 'picture');
    expect(find.text('图片'), findsOneWidget);
    await _menu(tester, 'OEBPS/picture');
    expect(find.text('替换图片资源（全书）'), findsOneWidget);
    await tester.tap(find.text('设为封面'));
    await tester.pumpAndSettle();
    expect(editor.session.readText(editor.session.opfPath), contains('cover-image'));
    await tester.tap(_row('OEBPS/picture'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.text('关闭图片'));
    await tester.pumpAndSettle();
    expect(opens, 0);
    await _search(tester, 'vector.svg');
    expect(find.text('图片'), findsOneWidget);
    await tester.tap(_row('OEBPS/vector.svg'));
    await tester.pump();
    expect(editor.activePath, 'OEBPS/vector.svg');
    expect(opens, 1);
  });

  testWidgets('新增章节、重命名、删除与撤销后筛选同步到工作副本', (tester) async {
    final editor = await _openBook(tester);
    await _mount(tester, editor);
    await tester.tap(find.byTooltip('新增文件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('空白章节'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'OEBPS/new.xhtml');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(editor.activePath, 'OEBPS/new.xhtml');
    expect(_row('OEBPS/new.xhtml'), findsOneWidget);
    await _search(tester, 'Volume-Two');
    await _menu(tester, _right);
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    const renamed = 'OEBPS/Book/Volume-Two/renamed.css';
    await tester.enterText(find.byType(TextField).last, renamed);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(_row(_right), findsNothing);
    await _menu(tester, renamed);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的文件'), findsOneWidget);
    editor.undo();
    await tester.pump();
    expect(_row(renamed), findsOneWidget);
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
  });

  testWidgets('全书命中携带光标位置、章节工具显式请求切回源码', (tester) async {
    final editor = await _openBook(tester);
    await _mount(tester, editor);
    final context = tester.element(find.byType(BookEditorFiles));
    final tools = BookEditorTools(context, editor);
    final search = tools.findReplace();
    await tester.pumpAndSettle();
    expect(find.byType(ReaderSheetForm), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, '查找内容'), '命中正文');
    await tester.tap(find.text('查找'));
    await tester.pump();
    await tester.tap(find.text(_second));
    await tester.pumpAndSettle();
    await search;
    expect(find.byType(ReaderSheetForm), findsNothing);
    expect(editor.activePath, _second);
    expect(editor.sourceRequested, isTrue);
    expect(editor.activeDocument!.code.selection.extentOffset, editor.session.readText(_second).indexOf('命中正文'));
    editor.sourceRequested = false;
    final chapters = tools.chapters();
    await tester.pumpAndSettle();
    expect(find.byType(ReaderSheetForm), findsOneWidget);
    await tester.tap(find.text(_first));
    await tester.pumpAndSettle();
    await chapters;
    expect(find.byType(ReaderSheetForm), findsNothing);
    expect(editor.activePath, _first);
    expect(editor.sourceRequested, isTrue);
  });

  testWidgets('五千章节按需建行，输入、滚动与同版本通知不再读清单或资源内容', (tester) async {
    final log = ReaderLog.instance;
    log.resetForTest();
    addTearDown(log.resetForTest);
    final session = _CountingSession();
    final editor = _CountingEditor(session);
    addTearDown(editor.dispose);
    await _mount(tester, editor);
    final menus = find.byTooltip('文件操作', skipOffstage: false);
    expect(menus.evaluate().length, inExclusiveRange(0, 50));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(_row('Book/0.xhtml'), findsNothing);
    await _search(tester, 'book/');
    expect(_row('Book/0.xhtml').hitTestable(), findsOneWidget);
    expect(menus.evaluate().length, inExclusiveRange(0, 50));
    await _search(tester, 'BOOK/4999');
    expect(_row('Book/4999.xhtml').hitTestable(), findsOneWidget);
    editor.refresh();
    await tester.pump();
    await _search(tester, 'raw.bin');
    expect(find.text('其他资源'), findsOneWidget);
    await tester.tap(_row('raw.bin'));
    await tester.pump();
    expect(
      await pumpReaderTask(tester, log.exportText()),
      contains(' | editor_file_info_opened'),
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(session.resourceReads, 1);
    expect(session.spineReads, 1);
    await tester.pumpWidget(const SizedBox());
  });
}

class _CountingSession extends Fake implements EpubEditSession {
  int resourceReads = 0;
  int spineReads = 0;
  @override
  int get revision => 0;
  @override
  List<String> get spinePaths {
    spineReads++;
    return List.generate(5000, (index) => 'Book/$index.xhtml');
  }

  @override
  List<EpubEditResource> get resources {
    resourceReads++;
    return [
      for (var index = 0; index < 5000; index++)
        EpubEditResource('Book/$index.xhtml', 'application/xhtml+xml', 256),
      const EpubEditResource('raw.bin', 'application/octet-stream', 987654321),
    ];
  }
}

class _CountingEditor extends Fake with ChangeNotifier implements BookEditorController {
  _CountingEditor(this.session);
  @override
  final EpubEditSession session;
  @override
  String? get activePath => null;
  @override
  bool get busy => false;
  void refresh() => notifyListeners();
}
