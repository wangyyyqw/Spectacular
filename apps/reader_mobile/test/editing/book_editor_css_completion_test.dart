import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:reader_mobile/editing/css_completion.dart';
import 'package:reader_mobile/editing/css_completion_input.dart';
import 'package:reader_mobile/theme/app_theme.dart';

final _platforms = TargetPlatformVariant({
  TargetPlatform.macOS,
  TargetPlatform.windows,
});
const _menu = ValueKey('css-completion-menu');

Future<void> _settleCompletion(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80));
}

Future<(CodeLineEditingController, FocusNode, ValueNotifier<bool>)> _showCode(
  WidgetTester tester,
  String marked, {
  CssCompletionMode mode = CssCompletionMode.stylesheet,
}) async {
  final offset = marked.indexOf('|');
  final controller = CodeLineEditingController.fromText(
    marked.replaceFirst('|', ''),
  );
  final focus = FocusNode();
  final readonly = ValueNotifier(false);
  addTearDown(() {
    controller.dispose();
    focus.dispose();
    readonly.dispose();
  });
  tester.view
    ..physicalSize = const Size(760, 600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: ValueListenableBuilder(
          valueListenable: readonly,
          builder: (_, value, _) => CssCodeCompletion(
            controller: controller,
            focusNode: focus,
            mode: mode,
            readOnly: value,
            builder: (indicator) => CodeEditor(
              controller: controller,
              focusNode: focus,
              readOnly: value,
              autofocus: false,
              indicatorBuilder: indicator,
              style: const CodeEditorStyle(
                fontFamily: 'monospace',
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  final prefix = controller.text.substring(0, offset).split('\n');
  controller.selection = CodeLineSelection.collapsed(
    index: prefix.length - 1,
    offset: prefix.last.length,
  );
  focus.requestFocus();
  await _settleCompletion(tester);
  return (controller, focus, readonly);
}

Future<void> _manual(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.space);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await _settleCompletion(tester);
}

Future<void> _close(WidgetTester tester, FocusNode focus) async {
  focus.unfocus();
  await tester.pump(const Duration(milliseconds: 160));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 160));
}

void main() {
  testWidgets('源码输入属性后 Tab 补全并继续给值，方向键与 Enter 接受且可撤销', (tester) async {
    final (code, focus, _) = await _showCode(tester, '.body { font-s| }');
    code.replaceSelection('i');
    await _settleCompletion(tester);
    expect(find.byKey(_menu), findsOneWidget);
    expect(
      find.byKey(const ValueKey('css-completion-font-size')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await _settleCompletion(tester);
    expect(code.text, '.body { font-size: ; }');
    expect(code.extentLine.text[code.selection.extentOffset], ';');
    expect(find.byKey(_menu), findsOneWidget);
    final choices = completeCss(
      code.text,
      code.selection.extentOffset,
      explicit: true,
    )!.items;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settleCompletion(tester);
    expect(code.text, contains('font-size: ${choices[1].insertText};'));
    expect(code.text, isNot(contains('\n')));
    expect(focus.hasFocus, isTrue);
    code.undo();
    expect(code.text, '.body { font-size: ; }');
    await _close(tester, focus);
  }, variant: _platforms);

  testWidgets('手动补全替换光标后的完整 token，Esc 不改源码，关闭后 Tab 正常缩进', (tester) async {
    final (code, focus, _) = await _showCode(
      tester,
      'p { text-a|lign: center; color: red; }',
    );
    await _manual(tester);
    expect(find.byKey(_menu), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('css-completion-text-align')));
    await _settleCompletion(tester);
    expect(code.text, 'p { text-align: center; color: red; }');
    final original = code.text;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(code.text, original);
    expect(find.byKey(_menu), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(code.text, isNot(original));
    await _close(tester, focus);
  }, variant: _platforms);

  testWidgets('组合输入和只读状态不显示补全，失焦与卸载清理候选浮层', (tester) async {
    final (code, focus, readonly) = await _showCode(tester, 'p { col| }');
    code.composing = const TextRange(start: 4, end: 7);
    await _manual(tester);
    expect(find.byKey(_menu), findsNothing);
    code.clearComposing();
    await _manual(tester);
    expect(find.byKey(_menu), findsOneWidget);
    readonly.value = true;
    await _settleCompletion(tester);
    expect(find.byKey(_menu), findsNothing);
    await _manual(tester);
    expect(find.byKey(_menu), findsNothing);
    readonly.value = false;
    await tester.pump();
    await _manual(tester);
    expect(find.byKey(_menu), findsOneWidget);
    await _close(tester, focus);
    expect(find.byKey(_menu), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: _platforms);

  testWidgets('XHTML 仅在 style 属性内补全，正文输入不弹候选', (tester) async {
    final (code, focus, _) = await _showCode(
      tester,
      '<p style="text-a|">正文</p>',
      mode: CssCompletionMode.xhtml,
    );
    await _manual(tester);
    await tester.tap(find.byKey(const ValueKey('css-completion-text-align')));
    await _settleCompletion(tester);
    expect(code.text, '<p style="text-align: ;">正文</p>');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    code.selection = CodeLineSelection.collapsed(
      index: 0,
      offset: code.text.indexOf('正文') + 2,
    );
    code.replaceSelection('font-s');
    await _settleCompletion(tester);
    expect(find.byKey(_menu), findsNothing);
    await _close(tester, focus);
  });

  testWidgets('样式 TextField 同一套补全支持属性值、鼠标选择与保留焦点', (tester) async {
    final input = TextEditingController(text: 'p { text-align: le; }');
    addTearDown(input.dispose);
    var applied = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: CssTextCompletion(
            controller: input,
            onAccepted: () => applied++,
            builder: (focus) =>
                TextField(controller: input, focusNode: focus, maxLines: 5),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    input.selection = TextSelection.collapsed(
      offset: input.text.indexOf('le;') + 2,
    );
    await _manual(tester);
    expect(find.byKey(const ValueKey('css-completion-left')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('css-completion-left')));
    await _settleCompletion(tester);
    expect(input.text, 'p { text-align: left; }');
    expect(applied, 1);
    final focus = tester.widget<TextField>(find.byType(TextField)).focusNode!;
    expect(focus.hasFocus, isTrue);
    await _close(tester, focus);
  });

  testWidgets('属性名单字段只补名称，值字段按指定属性筛选且可键盘撤销', (tester) async {
    final input = TextEditingController();
    addTearDown(input.dispose);
    Future<void> show(CssCompletionMode mode, {String? property}) =>
        tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: CssTextCompletion(
                key: ValueKey(mode),
                controller: input,
                mode: mode,
                property: property,
                builder: (focus) =>
                    TextField(controller: input, focusNode: focus),
              ),
            ),
          ),
        );
    await show(CssCompletionMode.property);
    await tester.enterText(find.byType(TextField), 'font-s');
    await _settleCompletion(tester);
    await tester.tap(find.byKey(const ValueKey('css-completion-font-size')));
    await _settleCompletion(tester);
    expect(input.text, 'font-size');
    expect(find.byKey(_menu), findsNothing);
    await show(CssCompletionMode.value, property: 'text-align');
    await tester.enterText(find.byType(TextField), 'ce');
    await _settleCompletion(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await _settleCompletion(tester);
    expect(input.text, 'center');
    await tester.pump(const Duration(milliseconds: 600));
    final mac =
        Theme.of(tester.element(find.byType(TextField))).platform ==
        TargetPlatform.macOS;
    await tester.sendKeyDownEvent(
      mac ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(
      mac ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft,
    );
    await _settleCompletion(tester);
    expect(input.text, 'ce');
    await _close(
      tester,
      tester.widget<TextField>(find.byType(TextField)).focusNode!,
    );
  }, variant: _platforms);
}
