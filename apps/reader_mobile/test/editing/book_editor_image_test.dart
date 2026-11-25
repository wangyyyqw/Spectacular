import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_mobile/editing/book_editor_controller.dart';
import 'package:reader_mobile/editing/book_editor_image_dialog.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

const _chapter = 'OEBPS/c1.xhtml';
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

final class _MemoryImage extends PlatformFile {
  _MemoryImage(this.name);
  @override
  final String name;
  @override
  Uri get uri => Uri.file('/images/$name');
  @override
  XFile get xFile => XFile.fromData(_png, name: name);
  @override
  int lengthSync() => _png.length;
  @override
  Future<int> length() async => _png.length;
  @override
  Future<Uint8List> readAsBytes() async => _png;
  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(_png);
}

class _Picker extends FilePickerPlatform {
  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => _MemoryImage('插图.png');
}

Future<BookEditorController> _open(
  WidgetTester tester, {
  bool images = false,
}) async {
  late Directory directory;
  late EpubEditSession session;
  await tester.runAsync(() async {
    directory = await Directory.systemTemp.createTemp('image-dialog-');
    final file = await File('${directory.path}/book.epub').writeAsBytes(
      buildMultiChapterEpub(
        chapters: [
          '<p id="target">原始正文</p>${images ? '<img id="picture" src="Pictures/插图.png" alt="旧描述"/>' : ''}',
        ],
        rawBody: true,
      ),
    );
    session = await EpubEditSession.open(file);
    if (images) {
      PackageEditor(session)
          .addResource('OEBPS/Pictures/插图.png', _png, 'image/png');
    }
  });
  final editor = BookEditorController(session: session);
  addTearDown(() async {
    editor.dispose();
    await directory.delete(recursive: true);
  });
  await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
  return editor;
}

Future<void> _show(
  WidgetTester tester,
  BookEditorController editor, {
  bool insert = true,
}) async {
  tester.view
    ..physicalSize = const Size(1100, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () {
              final element = editor.session
                  .editableDocument(_chapter)
                  .elements
                  .firstWhere(
                    (element) =>
                        element.attributes['id'] ==
                        (insert ? 'target' : 'picture'),
                  );
              if (insert) {
                insertBookImage(context, editor, element);
              } else {
                editBookImage(context, editor, element);
              }
            },
            child: const Text('打开图片表单'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开图片表单'));
  await tester.pumpAndSettle();
}

Future<void> _import(WidgetTester tester) async {
  await tester.tap(find.text('导入另一张图片'));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('image-resource-path')), findsOneWidget);
}

void main() {
  setUp(() {
    final previous = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _Picker();
    addTearDown(() => FilePickerPlatform.instance = previous);
  });

  testWidgets('临时导入可预览，取消后没有资源和历史变化', (tester) async {
    final editor = await _open(tester);
    final before = editor.session.readText(_chapter);
    await _show(tester, editor);
    await _import(tester);
    expect(find.byType(Image), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('image-resource-path')))
          .controller!
          .text,
      'OEBPS/Images/插图.png',
    );
    expect(editor.session.history, isEmpty);
    expect(editor.session.readBytes('OEBPS/Images/插图.png'), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(editor.session.readText(_chapter), before);
    expect(editor.session.history, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('导入替换沿已有图片目录，失败保留输入并可重试，一步撤销资源与正文', (tester) async {
    final editor = await _open(tester, images: true);
    final before = editor.session.readText(_chapter),
        opf = editor.session.readText(editor.session.opfPath);
    final history = editor.session.history.length;
    await _show(tester, editor, insert: false);
    await _import(tester);
    final destination = find.byKey(const ValueKey('image-resource-path'));
    expect(
      tester.widget<TextField>(destination).controller!.text,
      'OEBPS/Pictures/插图-2.png',
    );
    await tester.enterText(find.byKey(const ValueKey('image-alt')), '替换 & 说明');
    await tester.enterText(destination, 'OEBPS/Pictures/插图.png');
    await tester.tap(find.text('应用图片修改'));
    await tester.pump();
    expect(find.textContaining('图片资源已存在'), findsOneWidget);
    expect(editor.session.history.length, history);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('image-alt')))
          .controller!
          .text,
      '替换 & 说明',
    );
    await tester.enterText(destination, 'OEBPS/Pictures/插图-2.png');
    await tester.tap(find.text('应用图片修改'));
    await pumpReaderUntilComplete(
      tester,
      () =>
          find.byType(ReaderSheetForm).evaluate().isEmpty &&
          !editor.previewLoading,
    );
    expect(editor.session.history.length, history + 1);
    expect(editor.session.readBytes('OEBPS/Pictures/插图-2.png'), _png);
    expect(editor.session.readText(_chapter), contains('alt="替换 &amp; 说明"'));
    editor.undo();
    expect(editor.session.readText(_chapter), before);
    expect(editor.session.readText(editor.session.opfPath), opf);
    expect(editor.session.readBytes('OEBPS/Pictures/插图-2.png'), isNull);
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('选择已有资源在元素前插入，不重复导入图片', (tester) async {
    final editor = await _open(tester, images: true);
    final resources = editor.session.resources.length;
    await _show(tester, editor);
    await tester.tap(find.byKey(const ValueKey('image-insert-position')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('所选元素之前').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('image-alt')), '已有插图');
    await tester.tap(find.widgetWithText(FilledButton, '插入图片'));
    await pumpReaderUntilComplete(
      tester,
      () =>
          find.byType(ReaderSheetForm).evaluate().isEmpty &&
          !editor.previewLoading,
    );
    final doc = editor.session.editableDocument(_chapter);
    final image = doc.elements.firstWhere(
      (element) => element.attributes['alt'] == '已有插图',
    );
    final paragraph = doc.elements.firstWhere(
      (element) => element.attributes['id'] == 'target',
    );
    expect(image.end, lessThanOrEqualTo(paragraph.start));
    expect(editor.session.resources.length, resources);
    await tester.pumpWidget(const SizedBox());
  });
}
