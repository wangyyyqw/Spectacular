import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/theme/reader_dropdown.dart';
import 'package:reader_ui/theme/reader_panel_theme.dart';
import 'package:reader_ui/theme/reader_theme.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final dark in [false, true]) {
      testWidgets('${platform.name}选择浮层沿用菜单主题，取消与选择保留正确值，夜间=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var value = 'first';
        final form = GlobalKey<FormState>();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              platform: platform,
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            home: ReaderPanelTheme(
              theme: dark ? ReaderTheme.black : ReaderTheme.white,
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: StatefulBuilder(
                    builder: (context, setState) => Form(
                      key: form,
                      child: ReaderDropdownButtonFormField<String>(
                        initialValue: value,
                        decoration: const InputDecoration(labelText: '选择类型'),
                        items: const [
                          DropdownMenuItem(value: 'first', child: Text('第一项')),
                          DropdownMenuItem(value: 'second', child: Text('第二项')),
                          DropdownMenuItem(
                            value: 'disabled',
                            enabled: false,
                            child: Text('不可选项'),
                          ),
                        ],
                        onChanged: (next) => setState(() => value = next!),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final field = find.byType(ReaderDropdownButtonFormField<String>);
        await tester.tap(field);
        await tester.pumpAndSettle();
        final menu = find.byType(PopupMenuItem<String>);
        expect(tester.getSize(menu.first), const Size(144, 52));
        expect(tester.getRect(menu.first).right, tester.getRect(field).right);
        final selectedText = find.descendant(
          of: menu.first,
          matching: find.text('第一项'),
        );
        expect(
          tester.getCenter(selectedText).dx,
          tester.getCenter(menu.first).dx,
        );
        expect(
          DefaultTextStyle.of(tester.element(selectedText)).style.color,
          Theme.of(tester.element(field)).colorScheme.primary,
        );
        final surface = tester
            .widgetList<Material>(
              find.ancestor(of: menu.first, matching: find.byType(Material)),
            )
            .firstWhere((m) => m.shape is RoundedRectangleBorder);
        expect(
          surface.shape,
          Theme.of(tester.element(field)).popupMenuTheme.shape,
        );
        expect(
          surface.color,
          Theme.of(tester.element(field)).colorScheme.surface,
        );
        final bounds = tester.getRect(find.text('第二项'));
        expect(bounds.left, greaterThanOrEqualTo(8));
        expect(bounds.right, lessThanOrEqualTo(312));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(value, 'first');
        await tester.tap(field);
        await tester.pumpAndSettle();
        await tester.tap(find.text('第二项'));
        await tester.pumpAndSettle();
        expect(value, 'second');
        expect(form.currentState!.validate(), isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('长列表在浮层内滚动，字段变化后同步选中值', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var value = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Padding(
              padding: const EdgeInsets.all(16),
              child: ReaderDropdownButtonFormField<int>(
                initialValue: value,
                decoration: const InputDecoration(labelText: '模型'),
                items: [
                  for (var i = 0; i < 40; i++)
                    DropdownMenuItem(value: i, child: Text('模型 $i')),
                ],
                onChanged: (next) => setState(() => value = next!),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(ReaderDropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('模型 39'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('模型 39'));
    await tester.pumpAndSettle();
    expect(value, 39);
    expect(find.text('模型 39'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('紧凑选择框可在查找栏换行，表单验证与禁用仍有效', (tester) async {
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            child: Form(
              key: form,
              child: Column(
                children: [
                  Wrap(
                    children: [
                      ReaderDropdownButton<bool>(
                        value: false,
                        isDense: true,
                        items: const [
                          DropdownMenuItem(value: false, child: Text('普通模式')),
                          DropdownMenuItem(value: true, child: Text('正则模式')),
                        ],
                        onChanged: (_) {},
                      ),
                      const Text('查找选项'),
                    ],
                  ),
                  ReaderDropdownButtonFormField<String>(
                    key: const ValueKey('required-select'),
                    decoration: const InputDecoration(labelText: '必选字段'),
                    items: const [
                      DropdownMenuItem(value: 'one', child: Text('一')),
                    ],
                    validator: (value) => value == null ? '请选择一项' : null,
                    onChanged: (_) {},
                  ),
                  ReaderDropdownButtonFormField<String>(
                    key: const ValueKey('disabled-select'),
                    initialValue: 'one',
                    items: const [
                      DropdownMenuItem(value: 'one', child: Text('禁用字段')),
                    ],
                    onChanged: null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('普通模式'));
    await tester.pumpAndSettle();
    expect(find.text('正则模式'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('请选择一项'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('disabled-select')));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
