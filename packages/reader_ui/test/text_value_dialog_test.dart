import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/annotations/text_value_dialog.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

void main() {
  testWidgets('名称输入禁用空值，完成键提交去除空白的名称且安全退场', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showReaderDialog<String>(
                  context: context,
                  builder: (_) => ReaderTextValueDialog(
                    title: '新建分组',
                    label: '分组名称',
                    initialValue: '',
                    disableWhenEmpty: true,
                    submitOnEnter: true,
                    validate: (value) => value.isEmpty ? '请输入分组名称' : null,
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('新建分组'), findsOneWidget);
    expect(result, isNull);
    await tester.enterText(find.byType(TextField), '  小说  ');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(result, '小说');
    expect(find.byType(ReaderTextValueDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('普通输入保留提交校验，编辑清除错误且取消不返回草稿', (tester) async {
    String? result = '尚未返回';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showReaderDialog<String>(
                  context: context,
                  builder: (_) => ReaderTextValueDialog(
                    title: '自定义颜色',
                    label: '颜色',
                    initialValue: '',
                    validate: (value) => value == 'FFFFFF' ? null : '颜色无效',
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('颜色无效'), findsOneWidget);
    expect(result, '尚未返回');
    await tester.enterText(find.byType(TextField), 'FFFFFF');
    await tester.pumpAndSettle();
    expect(find.text('颜色无效'), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
}
