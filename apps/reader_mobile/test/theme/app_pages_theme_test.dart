import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:reader_mobile/home/home_shell.dart';
import 'package:reader_mobile/home/navigation_settings.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/icons/app_icon.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final font = FontLoader(AppFonts.defaultFamily)
      ..addFont(rootBundle.load('assets/fonts/MoyuSerif-Regular.otf'));
    await font.load();
    PackageInfo.setMockInitialValues(
      appName: '阅微 Extend',
      packageName: 'com.spectacular.reamicro',
      version: '1.0.0',
      buildNumber: '19',
      buildSignature: '',
    );
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final style in AppUiStyle.values) {
      for (final brightness in Brightness.values) {
        testWidgets(
          '${platform.name}/${style.name}/${brightness.name} 首页各入口及设置无溢出并保留主题',
          (tester) async {
            tester.view
              ..devicePixelRatio = 1
              ..physicalSize = platform == TargetPlatform.android
                  ? const Size(360, 800)
                  : const Size(1280, 900);
            addTearDown(tester.view.reset);
            final library = LibraryStore.memory();
            await pumpReaderTask(
              tester,
              library.setSetting(
                NavigationSettings.storageKey,
                jsonEncode(
                  HomeDestination.values.map((value) => value.name).toList(),
                ),
              ),
            );
            await pumpReaderTask(
              tester,
              library.importBytes(buildTestEpub(title: '山海之间')),
            );
            final boundary = GlobalKey();
            final theme = buildAppTheme(
              uiStyle: style,
              brightness: brightness,
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.teal,
                brightness: brightness,
              ),
            ).copyWith(platform: platform);
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                themeAnimationDuration: Duration.zero,
                builder: (context, child) =>
                    RepaintBoundary(key: boundary, child: child),
                home: HomeShell(
                  library: library,
                  progressStore: MemoryReaderProgressStore(),
                  uiStyle: style,
                  themeMode: brightness == Brightness.dark
                      ? ThemeMode.dark
                      : ThemeMode.light,
                  onUiStyleChanged: (_) async {},
                  onThemeModeChanged: (_) async {},
                ),
              ),
            );
            await pumpReaderUntil(tester, find.text('山海之间'));
            await tester.pumpAndSettle();
            final nav = find.byWidgetPredicate(
              (widget) =>
                  widget is NavigationBar ||
                  widget is BottomNavigationBar ||
                  widget is NavigationRail,
            );
            expect(nav, findsOneWidget);
            expect(
              find.byType(NavigationRail),
              platform == TargetPlatform.windows
                  ? findsOneWidget
                  : findsNothing,
            );
            if (platform == TargetPlatform.android) {
              expect(
                find.byType(NavigationBar),
                style == AppUiStyle.material3 ? findsOneWidget : findsNothing,
              );
            }
            for (final label in ['书架', '发现', '统计', '笔记', '我的']) {
              await tester.tap(
                find.descendant(of: nav, matching: find.text(label)),
              );
              await tester.pumpAndSettle();
              final context = tester.element(nav);
              expect(Theme.of(context).colorScheme, theme.colorScheme);
              expect(
                Theme.of(context).useMaterial3,
                style == AppUiStyle.material3,
              );
              expect(tester.takeException(), isNull, reason: '$label 页面');
              if (label == '我的') {
                final selectedProfile = find.descendant(
                  of: nav,
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is AppIcon &&
                        widget.glyph == AppGlyph.profile &&
                        widget.filled,
                  ),
                );
                expect(selectedProfile, findsOneWidget);
              }
              if (Platform.environment['READER_THEME_PREVIEWS'] == '1') {
                await _preview(
                  tester,
                  boundary,
                  '${platform.name}-${style.name}-${brightness.name}-$label',
                );
              }
            }
            await tester.tap(
              find.byKey(const ValueKey('profile-settings-entry')),
            );
            await pumpReaderUntil(
              tester,
              find.byKey(const ValueKey('app-ui-style-setting')),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '应用设置');
            if (Platform.environment['READER_THEME_PREVIEWS'] == '1') {
              await _preview(
                tester,
                boundary,
                '${platform.name}-${style.name}-${brightness.name}-设置',
              );
            }
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
}

Future<void> _preview(WidgetTester tester, GlobalKey key, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('dist/ui-themes-20261125/previews')
        ..createSync(recursive: true);
      File('${directory.path}/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
