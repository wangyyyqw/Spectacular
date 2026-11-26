import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/theme/reader_environment.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_frosted_surface.dart';
import 'package:reader_ui/theme/reader_panel_theme.dart';
import 'package:reader_ui/theme/reader_theme.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

void main() {
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets('${platform.name}抽屉捕获主题、返回结果并在退场后释放控制器', (tester) async {
      final input = TextEditingController();
      final focus = FocusNode();
      final origin = FocusNode();
      addTearDown(focus.dispose);
      addTearDown(origin.dispose);
      final desktop = platform != TargetPlatform.android;
      var completed = false;
      var backgroundShortcut = false;
      String? result;
      BuildContext? drawerContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform, fontFamily: '内置测试字体'),
          builder: (context, child) => CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.f2): () =>
                  backgroundShortcut = true,
            },
            child: child!,
          ),
          home: ReaderPanelTheme(
            theme: ReaderTheme.sepia,
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  focusNode: origin,
                  onPressed: () async {
                    result = await showReaderDrawer<String>(
                      context: context,
                      waitForDismissal: true,
                      maxWidth: 420,
                      isDismissible: false,
                      enableDrag: false,
                      builder: (context) {
                        drawerContext = context;
                        return ReaderSheetForm(
                          title: const Text('编辑名称'),
                          content: TextField(
                            controller: input,
                            focusNode: focus,
                            autofocus: true,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(context, input.text),
                              child: const Text('保存'),
                            ),
                          ],
                        );
                      },
                    );
                    input.dispose();
                    completed = true;
                  },
                  child: const Text('打开抽屉'),
                ),
              ),
            ),
          ),
        ),
      );
      origin.requestFocus();
      await tester.pump();
      await tester.tap(find.text('打开抽屉'));
      await tester.pumpAndSettle();
      final surface = find.byType(ReaderFrostedSurface);
      expect(tester.getSize(surface).width, 420);
      expect(
        Theme.of(drawerContext!).textTheme.bodyMedium?.fontFamily,
        '内置测试字体',
      );
      expect(
        Theme.of(drawerContext!).colorScheme.surface,
        Theme.of(tester.element(find.text('打开抽屉'))).colorScheme.surface,
      );
      expect(focus.hasFocus, isTrue);
      expect(find.byType(BottomSheet), desktop ? findsNothing : findsOneWidget);
      expect(ModalRoute.of(drawerContext!)!.barrierColor, Colors.black54);
      if (desktop) {
        expect(tester.getRect(surface).right, 800);
        final route = ModalRoute.of(drawerContext!)!;
        expect(route.traversalEdgeBehavior, TraversalEdgeBehavior.closedLoop);
        expect(
          route.reverseTransitionDuration,
          lessThan(route.transitionDuration),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        expect(backgroundShortcut, isFalse);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(focus.hasFocus, isTrue, reason: '焦点遍历不能进入被遮罩的页面');
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderSheetForm), findsOneWidget);
      await tester.enterText(find.byType(TextField), '真实结果');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(completed, isFalse);
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(result, '真实结果');
      expect(drawerContext!.mounted, isFalse);
      expect(origin.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      expect(backgroundShortcut, isTrue, reason: '抽屉关闭后恢复原页面快捷键');
      expect(tester.takeException(), isNull);
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('${platform.name}减少动态效果即时显示，关闭按钮和系统返回保留', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showReaderDrawer<void>(
                  context: context,
                  builder: (_) => const ReaderSheetForm(title: Text('选项')),
                ),
                child: const Text('打开抽屉'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开抽屉'));
      await tester.pump();
      final route = ModalRoute.of(
        tester.element(find.byType(ReaderSheetForm)),
      )!;
      expect(route.animation!.value, 1);
      expect(route.animation!.isAnimating, isFalse);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pump();
      expect(find.byType(ReaderSheetForm), findsNothing);
      await tester.tap(find.text('打开抽屉'));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(ReaderSheetForm), findsNothing);
      if (platform == TargetPlatform.windows) {
        await tester.tap(find.text('打开抽屉'));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(find.byType(ReaderSheetForm), findsNothing);
      }
      await tester.tap(find.text('打开抽屉'));
      await tester.pump();
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      expect(find.byType(ReaderSheetForm), findsNothing);
    });
  }

  testWidgets('弹窗保持焦点循环、遮罩关闭约定与返回值，退场结束后释放输入控制器', (tester) async {
    final input = TextEditingController();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var dismissible = false;
    var completed = false;
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showReaderDialog<String>(
                  context: context,
                  barrierDismissible: dismissible,
                  waitForDismissal: true,
                  builder: (context) => ReaderFrostedAlertDialog(
                    title: const Text('输入名称'),
                    content: TextField(
                      controller: input,
                      focusNode: focus,
                      autofocus: true,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, input.text),
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                );
                completed = true;
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(focus.hasFocus, isTrue, reason: '键盘焦点留在对话框内');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderFrostedDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), '新名字');
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(completed, isFalse);
    expect(find.byType(ReaderFrostedDialog), findsOneWidget);
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(result, '新名字');
    expect(find.byType(ReaderFrostedDialog), findsNothing);
    dismissible = true;
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.byType(ReaderFrostedDialog), findsNothing);
    input.dispose();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final ink in [false, true]) {
    testWidgets('${ink ? '墨水屏' : '减少动态效果'}即时打开和关闭居中弹窗', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: !ink),
            child: child!,
          ),
          home: ReaderPanelTheme(
            theme: ink ? ReaderEnvironment.inkTheme : ReaderTheme.white,
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showReaderDialog<void>(
                    context: context,
                    builder: (context) => ReaderFrostedSimpleDialog(
                      title: const Text('选项'),
                      children: [
                        SimpleDialogOption(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('关闭'),
                        ),
                      ],
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
      await tester.pump();
      final route = ModalRoute.of(
        tester.element(find.byType(ReaderFrostedDialog)),
      )!;
      expect(route.animation!.value, 1);
      expect(route.animation!.isAnimating, isFalse);
      await tester.tap(find.text('关闭'));
      await tester.pump();
      expect(find.byType(ReaderFrostedDialog), findsNothing);
    });
  }

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
    expect(find.byType(ReaderFrostedSurface), findsOneWidget);
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

  testWidgets('表单抽屉可从顶部下拉关闭', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showReaderDrawer<void>(
                context: context,
                builder: (_) => ReaderSheetForm(
                  title: const Text('界面主题'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      ListTile(title: Text('跟随系统')),
                      ListTile(title: Text('日间模式')),
                    ],
                  ),
                ),
              ),
              child: const Text('打开抽屉'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开抽屉'));
    await tester.pumpAndSettle();
    final dragHandle = find.byKey(
      const ValueKey<String>('reader-drawer-drag-handle'),
    );
    expect(dragHandle, findsOneWidget);
    await tester.fling(dragHandle, const Offset(0, 400), 1200);
    await tester.pumpAndSettle();
    expect(find.text('界面主题'), findsNothing);
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
                  result = await showReaderDialog<String>(
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
    expect(find.byType(ReaderFrostedSurface), findsOneWidget);
    final surface =
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: find.byType(ReaderFrostedSurface),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(
      surface.color,
      Theme.of(tester.element(find.byType(ReaderFrostedDialog)))
          .colorScheme
          .surface,
      reason: '弹窗使用软件主题底色，独立于正文颜色',
    );
    expect(surface.color!.a, 1);
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
                      onPressed: () => showReaderDialog<void>(
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
      expect(find.byType(ReaderFrostedSurface), findsNWidgets(2));
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
