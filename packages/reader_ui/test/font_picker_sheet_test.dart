import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/panels/font_picker_sheet.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

void main() {
  testWidgets('字体加载中禁用标题关闭，失败后保留弹层并恢复关闭', (tester) async {
    final pending = Completer<void>();
    ReaderFontSelection? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await showReaderDrawer<ReaderFontSelection>(
                  context: context,
                  builder: (_) => ReaderFontPickerSheet(
                    fonts: const [
                      ReaderFontOption(family: 'user_demo', label: '演示字体'),
                    ],
                    selected: null,
                    onLoad: (_) => pending.future,
                  ),
                );
              },
              child: const Text('打开字体'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开字体'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('演示字体'));
    await tester.pump();
    final close = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == '关闭',
    );
    final disabled = tester.widget<IconButton>(close).onPressed == null;
    await tester.tap(close);
    await tester.pump(const Duration(milliseconds: 200));
    final stayedOpen = find.byType(ReaderFontPickerSheet).evaluate().isNotEmpty;
    pending.completeError(const FormatException('字体文件无法读取'));
    await tester.pumpAndSettle();
    expect(disabled, isTrue);
    expect(stayedOpen, isTrue);
    expect(selected, isNull);
    expect(find.text('字体文件无法读取'), findsOneWidget);
    expect(tester.widget<IconButton>(close).onPressed, isNotNull);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byType(ReaderFontPickerSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
