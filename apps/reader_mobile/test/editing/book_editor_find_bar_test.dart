import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/editing/book_editor_controller.dart';
import 'package:reader_mobile/editing/book_editor_find_bar.dart';

import '../support/reader_pump.dart';

Future<void> _show(
  WidgetTester tester,
  BookEditorDocument document, {
  bool readOnly = false,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: ValueListenableBuilder(
        valueListenable: document.find,
        builder: (_, _, _) => EditorFindBar(
          controller: document.find,
          editing: document.code,
          readOnly: readOnly,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('查找栏正则捕获组替换保留大小写选项，支持替换当前和全部', (tester) async {
    final document = BookEditorDocument('book.xhtml', 'Ab1 ab2 ab3');
    addTearDown(document.dispose);
    await _show(tester, document);
    document.find.toggleRegex();
    document.find.toggleCaseSensitive();
    await tester.enterText(
      find.widgetWithText(TextField, '文档内查找'),
      r'\b([a-z]+)(\d)\b',
    );
    await pumpReaderUntilComplete(
      tester,
      () => document.find.allMatchSelections?.length == 2,
    );
    expect(document.find.allMatchSelections, hasLength(2));
    await tester.enterText(find.widgetWithText(TextField, '替换为'), r'$2-$1');
    await tester.tap(find.widgetWithText(TextButton, '替换'));
    await pumpReaderUntilComplete(
      tester,
      () => document.find.allMatchSelections?.length == 1,
    );
    expect(document.code.text, 'Ab1 2-ab ab3');
    await tester.tap(find.text('全部替换'));
    await pumpReaderUntilComplete(
      tester,
      () =>
          document.find.value?.searching == false &&
          document.code.text == 'Ab1 2-ab 3-ab',
    );
    expect(document.code.text, 'Ab1 2-ab 3-ab');
    expect(document.find.replaceInputController.text, r'$2-$1');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('查找栏关闭循环后停在末项，只读状态禁用全部替换', (tester) async {
    final document = BookEditorDocument('book.xhtml', '甲 甲');
    addTearDown(document.dispose);
    await _show(tester, document, readOnly: true);
    await tester.enterText(find.widgetWithText(TextField, '文档内查找'), '甲');
    await pumpReaderUntilComplete(
      tester,
      () => document.find.allMatchSelections?.length == 2,
    );
    await tester.tap(find.text('循环匹配'));
    await tester.tap(find.byTooltip('下一处'));
    await tester.pumpAndSettle();
    expect(document.find.value!.result!.index, 1);
    await tester.tap(find.byTooltip('下一处'));
    await tester.pumpAndSettle();
    expect(document.find.value!.result!.index, 1);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '全部替换'))
          .onPressed,
      isNull,
    );
    expect(document.code.text, '甲 甲');
    await tester.pumpWidget(const SizedBox());
  });
}
