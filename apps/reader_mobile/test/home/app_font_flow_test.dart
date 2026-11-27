import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/main.dart';
import 'package:reader_mobile/reader/reader_font_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/reader_pump.dart';

void main() {
  testWidgets('设置页切换自定义应用字体，全局生效并在重启后恢复', (tester) async {
    final directory = Directory.systemTemp.createTempSync('app-font-flow');
    addTearDown(() => directory.delete(recursive: true));
    PackageInfo.setMockInitialValues(
      appName: 'Spectacular Reader',
      packageName: 'com.spectacular.reader_mobile',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      paths,
      (_) async => directory.path,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        paths,
        null,
      ),
    );

    final library = LibraryStore.memory();
    final fontStore = ReaderFontStore(
      library,
      directoryProvider: () async => directory,
    );
    final bytes = File('../../test_fonts/SourceHanSerifSC-Regular.otf')
        .readAsBytesSync();
    final font = (await tester.runAsync(
      () => fontStore.import(bytes, displayName: '自定义应用宋体.otf'),
    ))!;

    Future<void> openApp() async {
      await tester.pumpWidget(
        ReaderApp(library: library, progressStore: MemoryReaderProgressStore()),
      );
      await pumpReaderUntil(tester, find.text('书架还是空的'));
    }

    String? themeFont() => tester
        .widget<MaterialApp>(find.byType(MaterialApp))
        .theme
        ?.textTheme
        .bodyMedium
        ?.fontFamily;

    await openApp();
    expect(themeFont(), AppFonts.defaultFamily);
    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text('我的'),
      ),
    );
    await pumpReaderUntil(
      tester,
      find.byKey(const ValueKey('profile-settings-entry')),
    );
    await tester.tap(find.byKey(const ValueKey('profile-settings-entry')));
    await pumpReaderUntil(tester, find.text('应用字体'));
    await tester.tap(find.byKey(const ValueKey('app-font-setting')));
    await pumpReaderUntil(
      tester,
      find.byKey(ValueKey('app-font-${font.family}')),
    );
    final customFont = find.byKey(ValueKey('app-font-${font.family}'));
    await tester.ensureVisible(customFont);
    await tester.pumpAndSettle();
    await tester.tap(customFont);
    await pumpReaderUntilComplete(
      tester,
      () => themeFont() == font.family,
      description: '应用字体生效',
    );
    expect(await library.getSetting(AppFonts.settingKey), font.family);
    expect(
      find.descendant(of: find.byKey(const ValueKey('app-font-setting')), matching: find.text(font.displayName)),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await openApp();
    expect(themeFont(), font.family);
    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text('我的'),
      ),
    );
    await pumpReaderUntil(
      tester,
      find.byKey(const ValueKey('profile-settings-entry')),
    );
    await tester.tap(find.byKey(const ValueKey('profile-settings-entry')));
    await pumpReaderUntil(tester, find.text('应用字体'));
    final setting = tester.widget<ListTile>(
      find.byKey(const ValueKey('app-font-setting')),
    );
    expect(setting.subtitle, isNull);
    expect(find.descendant(of: find.byWidget(setting.trailing!), matching: find.text(font.displayName)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('缺失自定义应用字体时恢复思源宋体并清理偏好', (tester) async {
    final library = LibraryStore.memory();
    final missing = 'user_${'0' * 64}';
    await library.setSetting(AppFonts.settingKey, missing);
    await tester.pumpWidget(
      ReaderApp(library: library, progressStore: MemoryReaderProgressStore()),
    );
    await pumpReaderUntil(tester, find.text('书架还是空的'));
    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .theme
          ?.textTheme
          .bodyMedium
          ?.fontFamily,
      AppFonts.defaultFamily,
    );
    expect(
      await library.getSetting(AppFonts.settingKey),
      AppFonts.defaultFamily,
    );
    expect(tester.takeException(), isNull);
  });
}
