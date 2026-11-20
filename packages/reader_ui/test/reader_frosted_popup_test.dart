import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:reader_ui/theme/reader_environment.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_frosted_surface.dart';
import 'package:reader_ui/theme/reader_panel_theme.dart';
import 'package:reader_ui/theme/reader_theme.dart';

void main() {
  testWidgets('短抽屉只使用一层磨砂，保留返回值和拖动关闭', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showReaderBottomSheet<String>(
                  context: context,
                  showDragHandle: true,
                  builder: (context) => Material(
                    key: const ValueKey('内容底板'),
                    color: ReaderFrostedSurface.panelColorOf(context),
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, '已选择'),
                      child: const Text('选择'),
                    ),
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
    expect(find.byType(GlassContainer), findsOneWidget);
    expect(
      tester.getSize(find.byType(ReaderFrostedSurface)).height,
      lessThan(150),
    );
    expect(
      tester.widget<Material>(find.byKey(const ValueKey('内容底板'))).color,
      Colors.transparent,
    );
    await tester.tap(find.text('选择'));
    await tester.pumpAndSettle();
    expect(result, '已选择');
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.fling(
      find.byType(ReaderFrostedSurface),
      const Offset(0, 350),
      1200,
    );
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(result, isNull);
  });

  testWidgets('确认弹窗局部磨砂，深色主题和键盘避让保留', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPanelTheme(
          theme: ReaderTheme.black,
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: context,
                    builder: (context) => ReaderFrostedAlertDialog(
                      title: const Text('重命名'),
                      content: const TextField(),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, '保存'),
                          child: const Text('保存'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byType(GlassContainer), findsOneWidget);
    final glass = tester.widget<GlassContainer>(find.byType(GlassContainer));
    expect(glass.color, ReaderTheme.black.background);
    expect(glass.quality, GlassQuality.minimal);
    expect(
      tester.getRect(find.byType(ReaderFrostedSurface)).bottom,
      lessThan(660),
    );
    expect(
      tester.getSize(find.byType(ReaderFrostedSurface)).width,
      lessThan(400),
    );
    await tester.enterText(find.byType(TextField), '新名字');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(result, '保存');
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('墨水屏和高对比模式的二级弹层不使用模糊', (tester) async {
    for (final ink in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(highContrast: !ink),
            child: child!,
          ),
          home: ReaderPanelTheme(
            theme: ink ? ReaderEnvironment.inkTheme : ReaderTheme.white,
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showReaderBottomSheet<void>(
                    context: context,
                    builder: (context) => TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) =>
                            const ReaderFrostedAlertDialog(title: Text('确认')),
                      ),
                      child: const Text('二级弹窗'),
                    ),
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('二级弹窗'));
      await tester.pumpAndSettle();
      expect(find.byType(GlassContainer), findsNWidgets(2));
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
