import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_frosted_surface.dart';
import 'package:reader_ui/theme/reader_panel_theme.dart';
import 'package:reader_ui/theme/reader_theme.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';

void main() {
  for (final md3 in [false, true]) {
    for (final brightness in Brightness.values) {
      for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
        testWidgets(
          '凝光弹层 $md3/${brightness.name}/${platform.name} 捕获取色、圆角与输入状态',
          (tester) async {
            final scheme = ColorScheme.fromSeed(
              seedColor: Colors.purple,
              brightness: brightness,
            );
            late BuildContext drawerContext;
            await tester.pumpWidget(
              MaterialApp(
                theme: applyReaderUiStyle(
                  ThemeData(useMaterial3: md3, platform: platform),
                ),
                home: ReaderPanelColorScope(
                  scheme: scheme,
                  child: ReaderPanelTheme(
                    theme: ReaderTheme.white,
                    child: Scaffold(
                      body: Builder(
                        builder: (context) => TextButton(
                          onPressed: () => showReaderDrawer<void>(
                            context: context,
                            readerTheme: ReaderTheme.white,
                            builder: (context) {
                              drawerContext = context;
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const TextField(
                                    decoration: InputDecoration(
                                      labelText: '名称',
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => showReaderDialog<void>(
                                      context: context,
                                      builder: (_) =>
                                          const ReaderFrostedAlertDialog(
                                            title: Text('二级弹窗'),
                                            content: Text('主题保持'),
                                          ),
                                    ),
                                    child: const Text('打开弹窗'),
                                  ),
                                ],
                              );
                            },
                          ),
                          child: const Text('打开抽屉'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('打开抽屉'));
            await tester.pumpAndSettle();
            final radius = md3 ? 28.0 : 24.0;
            final surface = tester.widget<ReaderFrostedSurface>(
              find.byType(ReaderFrostedSurface),
            );
            expect(surface.radius, radius);
            expect(
              surface.bottomRadius,
              platform == TargetPlatform.android ? 0 : radius,
            );
            expect(Theme.of(drawerContext).colorScheme, scheme);
            final input = tester.widget<InputDecorator>(
              find.byType(InputDecorator),
            );
            expect(
              (input.decoration.focusedBorder! as OutlineInputBorder)
                  .borderRadius,
              BorderRadius.circular(md3 ? 12 : 4),
            );
            await tester.tap(find.text('打开弹窗'));
            await tester.pumpAndSettle();
            final dialog = find.byType(ReaderFrostedAlertDialog);
            expect(Theme.of(tester.element(dialog)).colorScheme, scheme);
            final clip = tester.widget<ClipRRect>(
              find
                  .descendant(
                    of: find.byType(ReaderFrostedDialog),
                    matching: find.byType(ClipRRect),
                  )
                  .first,
            );
            expect(clip.borderRadius, BorderRadius.circular(radius));
            Navigator.of(tester.element(dialog)).pop();
            await tester.pumpAndSettle();
            expect(find.byType(TextField), findsOneWidget);
            Navigator.of(drawerContext).pop();
            await tester.pumpAndSettle();
            expect(find.byType(ReaderFrostedSurface), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
