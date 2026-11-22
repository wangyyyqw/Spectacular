import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/main.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/theme/reader_panel_theme.dart';
import 'package:reader_ui/theme/reader_theme.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import '../support/test_epub.dart';

import 'package:reader_ui/reader_session.dart';

Future<void> _pumpFrames(WidgetTester tester, {int frames = 30}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _savePreview(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('界面预览')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('/tmp/spectacular-ui-preview')
        ..createSync(recursive: true);
      File('${directory.path}/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('窄屏四页导航与排序保留，界面采用中性小圆角并可生成预览', (tester) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final font = FontLoader('builtin_hei')
      ..addFont(rootBundle.load('assets/fonts/SourceHanSansSC-Regular.otf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    PackageInfo.setMockInitialValues(
      appName: 'Spectacular Reader',
      packageName: 'com.spectacular.reamicro',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    final library = LibraryStore.memory();
    for (final title in ['山海之间', '长日阅读', '人间草木']) {
      await library.importBytes(buildTestEpub(title: title));
    }
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('界面预览'),
        child: ReaderApp(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await _pumpFrames(tester);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(find.text('山海之间'), findsWidgets);
    await _savePreview(tester, '书架');
    for (final label in ['统计', '书评', '我的']) {
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text(label),
        ),
      );
      await _pumpFrames(tester);
      expect(tester.takeException(), isNull);
      await _savePreview(tester, label);
    }
    await tester.tap(find.byKey(const ValueKey('bookshelf-sort-setting')));
    await _pumpFrames(tester, frames: 8);
    expect(find.text('书架排序'), findsWidgets);
    expect(find.byType(ReaderSheetForm), findsOneWidget);
    final theme = buildAppTheme();
    expect(theme.useMaterial3, isFalse);
    expect(theme.colorScheme.surfaceTint, Colors.transparent);
    final shape = theme.cardTheme.shape! as RoundedRectangleBorder;
    expect(
      shape.borderRadius.resolve(TextDirection.ltr).topLeft.x,
      lessThanOrEqualTo(4),
    );
  });

  testWidgets('日夜阅读面板的按钮文字与表面跟随正文主题', (tester) async {
    for (final theme in [
      ReaderTheme.white,
      ReaderTheme.black,
      ReaderTheme.black,
    ]) {
      ThemeData? panel;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: ReaderPanelTheme(
            theme: theme,
            child: Builder(
              builder: (context) {
                panel = Theme.of(context);
                return Scaffold(
                  body: Column(
                    children: [
                      const Card(child: Text('阅读面板')),
                      TextButton(onPressed: () {}, child: const Text('保存')),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      await _pumpFrames(tester, frames: 8);
      expect(panel!.colorScheme.surface, theme.background);
      expect(panel!.colorScheme.inverseSurface, theme.text);
      expect(panel!.colorScheme.onInverseSurface, theme.background);
      expect(panel!.cardTheme.color, theme.background);
      expect(
        panel!.textButtonTheme.style!.foregroundColor!.resolve({}),
        theme.text,
      );
      expect(
        panel!.filledButtonTheme.style!.foregroundColor!.resolve({}),
        theme.background,
      );
      expect(theme.luminance, greaterThanOrEqualTo(4.5));
      expect(tester.takeException(), isNull);
    }
  });
}
