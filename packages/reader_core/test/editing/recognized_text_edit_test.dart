import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing.dart';
import 'package:reader_core/parser/document_parser.dart';

import 'edit_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('OCR 编辑拒绝错误原文证据、半个字符和跨段替换', () async {
    final dir = await Directory.systemTemp.createTemp('ocr-edit-invalid');
    addTearDown(() => dir.delete(recursive: true));
    const xhtml =
        '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>甲😀乙&nbsp;丙</p><p>丁戊</p></body></html>';
    final file = await createEditingFixture(
      dir,
      chapterBytes: Uint8List.fromList(utf8.encode(xhtml)),
    );
    final session = await EpubEditSession.open(file);
    addTearDown(session.close);
    final parsed = DocumentParser.parse(xhtml: xhtml, spineIndex: 0);
    final first = parsed.textNodes.first;
    String at(int offset) => first.cfi.withCharOffset(offset).serialize();
    expect(
      () => EpubParagraphEdit.fromSelection(
        session,
        0,
        at(0),
        at(1),
        recognizedText: '字',
        sourceText: '错',
      ),
      throwsA(isA<EpubEditException>()),
    );
    expect(
      () => EpubParagraphEdit.fromSelection(
        session,
        0,
        at(1),
        at(2),
        recognizedText: '字',
        sourceText: first.text.substring(1, 2),
      ),
      throwsA(isA<EpubEditException>()),
    );
    expect(
      () => EpubParagraphEdit.fromSelection(
        session,
        0,
        at(0),
        parsed.textNodes.last.cfi.withCharOffset(1).serialize(),
        recognizedText: '字',
        sourceText: '${first.text}丁',
      ),
      throwsA(isA<EpubEditException>()),
    );
    expect(session.readText('OPS/chapter.xhtml'), xhtml);
    final edit = EpubParagraphEdit.fromSelection(
      session,
      0,
      at(3),
      at(first.text.length),
      recognizedText: '乙丙',
      sourceText: first.text.substring(3),
    );
    edit.apply('新字');
    expect(
      DocumentParser.parse(
        xhtml: session.readText('OPS/chapter.xhtml'),
        spineIndex: 0,
      ).plainText,
      '甲😀新字丁戊',
    );
  });
  test('OCR 编辑只替换选中文字，保留邻文、行内标签并隔离混淆字体，可撤销与重开', () async {
    final dir = await Directory.systemTemp.createTemp('ocr-edit-');
    addTearDown(() => dir.delete(recursive: true));
    const xhtml =
        '<html xmlns="http://www.w3.org/1999/xhtml"><head/><body><p style="font-family:secret">甲&amp;<b>乙😀</b>丙<![CDATA[丁戊]]>己</p><p>邻段</p></body></html>';
    final file = await createEditingFixture(
      dir,
      chapterBytes: Uint8List.fromList(utf8.encode(xhtml)),
    );
    final session = await EpubEditSession.open(file);
    addTearDown(session.close);
    final parsed = DocumentParser.parse(xhtml: xhtml, spineIndex: 0);
    final first = parsed.textNodes.firstWhere((n) => n.text.contains('甲'));
    final last = parsed.textNodes.firstWhere((n) => n.text.contains('丁'));
    final start = first.cfi.withCharOffset(1).serialize();
    final end = last.cfi.withCharOffset(last.text.indexOf('戊') + 1).serialize();
    final edit = EpubParagraphEdit.fromSelection(
      session,
      0,
      start,
      end,
      recognizedText: '正确文字',
      sourceText: '&乙😀丙丁戊',
    );
    expect(edit.isHtml, isFalse);
    expect(edit.initialText, '正确文字');
    edit.apply('修改后的文字');
    final updated = session.readText('OPS/chapter.xhtml');
    expect(updated, contains('font-family: serif !important'));
    expect(updated, contains('甲<span'));
    expect(updated, contains('<p>邻段</p>'));
    expect(updated, contains('己</p>'));
    expect(updated, contains('<b>'));
    final reopenedText = DocumentParser.parse(
      xhtml: updated,
      spineIndex: 0,
    ).plainText;
    expect(reopenedText, '甲修改后的文字己邻段');
    session.undo();
    expect(session.readText('OPS/chapter.xhtml'), xhtml);
    session.redo();
    final output = File('${dir.path}/saved.epub');
    await EpubWriter.write(session, output);
    final reopened = await EpubEditSession.open(output);
    addTearDown(reopened.close);
    expect(reopened.readText('OPS/chapter.xhtml'), updated);
    expect(await file.readAsBytes(), isNot(await output.readAsBytes()));
  });
}
