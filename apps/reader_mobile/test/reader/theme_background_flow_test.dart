import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/panels/settings_panel.dart';
import 'package:reader_ui/theme/reader_theme.dart';
import 'package:reader_ui/theme/reader_panel_theme.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_mobile/main.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_ui/menu/reader_menu_overlay.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

Uint8List _book() => File('../../test_corpus/basic.epub').readAsBytesSync();

Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const Color(0xFF557799), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(10, 10);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<void> _themeMenu(WidgetTester tester) async {
  await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('menu-entry-theme')));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pump();
}

void main() {
  testWidgets('正文与色块跟随软件和系统日夜模式，分别恢复配色且不重排', (tester) async {
    final dispatcher = tester.binding.platformDispatcher;
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    dispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(dispatcher.clearPlatformBrightnessTestValue);
    final mode = ValueNotifier(ThemeMode.system);
    addTearDown(mode.dispose);
    final changes = <ReaderSettings>[];
    var closed = false;
    await tester.pumpWidget(
      ValueListenableBuilder<ThemeMode>(
        valueListenable: mode,
        builder: (_, value, child) => MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: value,
          themeAnimationDuration: Duration.zero,
          builder: (_, child) => AppThemeScope(
            mode: value,
            onModeChanged: (next) async => mode.value = next,
            child: child!,
          ),
          home: child,
        ),
        child: EpubReaderPage(
          bytes: _book(),
          bookId: 'app-theme-flow',
          store: MemoryReaderProgressStore(),
          settings: ReaderSettings.defaults.copyWithTheme('sepia'),
          onSettingsChanged: changes.add,
          onClosed: () => closed = true,
        ),
      ),
    );
    await pumpReaderUntil(tester, find.byType(ReaderView));
    final session = tester
        .widget<PageTurnView>(find.byType(PageTurnView))
        .session;
    final fingerprint = session.layoutFingerprint;
    final position = session.progress;
    Color paper() => tester
        .widget<Scaffold>(find.byKey(const ValueKey('epub-reader-scaffold')))
        .backgroundColor!;
    Future<void> verify(ReaderTheme expected) async {
      await tester.pumpAndSettle();
      expect(paper(), expected.background);
      if (find.byType(SettingsPanel).evaluate().isEmpty) {
        await _themeMenu(tester);
      }
      final panel = find.byType(SettingsPanel);
      expect(
        Theme.of(tester.element(panel)).brightness,
        expected.isDark ? Brightness.dark : Brightness.light,
      );
      expect(tester.widget<SettingsPanel>(panel).themeId, expected.id);
      for (final theme in ReaderTheme.themes) {
        expect(
          find.byKey(ValueKey('settings-theme-${theme.id}')),
          theme.isDark == expected.isDark ? findsOneWidget : findsNothing,
        );
      }
      final themes = tester.widgetList<ReaderPanelTheme>(
        find.ancestor(of: panel, matching: find.byType(ReaderPanelTheme)),
      );
      expect(themes.first.theme, expected);
      expect(session.layoutFingerprint, fingerprint);
      expect(session.progress, position);
    }

    await verify(ReaderTheme.sepia);
    dispatcher.platformBrightnessTestValue = Brightness.dark;
    await verify(ReaderTheme.black);
    await _tap(tester, 'settings-theme-moss');
    await verify(ReaderTheme.moss);
    expect(mode.value, ThemeMode.system, reason: '同模式选色保留跟随系统');
    expect(changes.single.themeId, 'moss');
    mode.value = ThemeMode.light;
    await verify(ReaderTheme.sepia);
    dispatcher.platformBrightnessTestValue = Brightness.light;
    mode.value = ThemeMode.dark;
    await verify(ReaderTheme.moss);
    mode.value = ThemeMode.light;
    await verify(ReaderTheme.sepia);
    expect(changes, hasLength(1), reason: '环境变化不覆盖持久化的阅读配色');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpReaderUntilComplete(
      tester,
      () => closed,
      description: '界面主题阅读页释放',
    );
  });

  testWidgets('阅读页日夜按钮保存全局模式，色块按模式切换并记住各自选择', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dispatcher = tester.binding.platformDispatcher;
    dispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(dispatcher.clearPlatformBrightnessTestValue);
    final library = LibraryStore.memory();
    var closed = false;
    await tester.pumpWidget(
      ReaderApp(library: library, progressStore: MemoryReaderProgressStore()),
    );
    await pumpReaderUntil(tester, find.text('书架还是空的'));
    Navigator.of(tester.element(find.text('书架还是空的'))).push<void>(
      MaterialPageRoute(
        builder: (_) => EpubReaderPage(
          bytes: _book(),
          bookId: 'reader-global-theme',
          store: MemoryReaderProgressStore(),
          settings: ReaderSettings.defaults.copyWithTheme('sepia'),
          onClosed: () => closed = true,
        ),
      ),
    );
    await pumpReaderUntil(tester, find.byType(ReaderView));
    final session = tester
        .widget<PageTurnView>(find.byType(PageTurnView))
        .session;
    final position = session.progress;
    final fingerprint = session.layoutFingerprint;
    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    final initialMenu = tester.widget<ReaderMenuOverlay>(
      find.byType(ReaderMenuOverlay),
    );
    expect(initialMenu.nightMode, isTrue);
    Future<void> verify(ThemeMode expected, ReaderTheme expectedTheme) async {
      await pumpReaderUntilComplete(
        tester,
        () =>
            tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode ==
            expected,
      );
      await tester.pumpAndSettle();
      expect(await library.getSetting('app.themeMode'), expected.name);
      expect(
        tester
            .widget<Scaffold>(
              find.byKey(const ValueKey('epub-reader-scaffold')),
            )
            .backgroundColor,
        expectedTheme.background,
      );
      if (find.byType(SettingsPanel).evaluate().isNotEmpty) {
        expect(
          tester.widget<SettingsPanel>(find.byType(SettingsPanel)).themeId,
          expectedTheme.id,
        );
        expect(
          find.byKey(
            ValueKey(
              expected == ThemeMode.dark
                  ? 'settings-theme-white'
                  : 'settings-theme-black',
            ),
          ),
          findsNothing,
        );
      }
      expect(session.progress, position);
      expect(session.layoutFingerprint, fingerprint);
    }

    initialMenu.onToggleDayNight();
    await verify(ThemeMode.light, ReaderTheme.sepia);
    expect(
      tester
          .widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay))
          .nightMode,
      isFalse,
    );
    tester
        .widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay))
        .onToggleDayNight();
    await verify(ThemeMode.dark, ReaderTheme.black);
    await tester.tap(find.byKey(const ValueKey('menu-entry-theme')));
    await tester.pumpAndSettle();
    await _tap(tester, 'settings-theme-moss');
    await verify(ThemeMode.dark, ReaderTheme.moss);
    tester
        .widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay))
        .onToggleDayNight();
    await verify(ThemeMode.light, ReaderTheme.sepia);
    await _tap(tester, 'settings-theme-paper');
    await verify(ThemeMode.light, ReaderTheme.paper);
    tester
        .widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay))
        .onToggleDayNight();
    await verify(ThemeMode.dark, ReaderTheme.moss);
    await _tap(tester, 'settings-theme-plum');
    await verify(ThemeMode.dark, ReaderTheme.plum);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpReaderUntilComplete(
      tester,
      () => closed,
      description: '全局主题阅读页释放',
    );
  });

  testWidgets('连续切主题和背景保留前次设置', (tester) async {
    final changes = <ReaderSettings>[];
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderPage(
          bytes: _book(),
          bookId: 'theme-flow',
          store: MemoryReaderProgressStore(),
          settings: ReaderSettings.defaults,
          onSettingsChanged: changes.add,
          onClosed: () => closed = true,
        ),
      ),
    );
    await pumpReaderUntil(tester, find.byType(ReaderView));
    await _themeMenu(tester);
    await _tap(tester, 'settings-theme-sepia');
    await _tap(tester, 'settings-bg-paper');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(changes.last.themeId, 'sepia');
    expect(changes.last.backgroundId, 'paper');
    tester
        .widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay))
        .onToggleDayNight();
    await tester.pumpAndSettle();
    await _tap(tester, 'settings-theme-black');
    expect(changes.last.themeId, 'black');
    expect(changes.last.backgroundId, 'paper');
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpReaderUntilComplete(
      tester,
      () => closed,
      description: '主题测试阅读页释放',
    );
  });

  testWidgets('图片取消和加载失败不保存，旧异步请求不覆盖新背景', (tester) async {
    final source = await openTestChapterSource(_book());
    final bytes = (await tester.runAsync(_png))!;
    final oldLoad = Completer<Uint8List>();
    final changes = <String>[];
    late ReaderSession session;
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            bookId: 'image-race',
            store: MemoryReaderProgressStore(),
            backgroundId: 'image:old',
            onSessionReady: (value) => session = value,
            backgroundImageLoader: (id) => id == 'image:old'
                ? oldLoad.future
                : Future.value(Uint8List.fromList([1, 2, 3])),
            onPickBackgroundImage: () async => picked,
            onBackgroundChanged: changes.add,
          ),
        ),
      ),
    );
    await pumpReaderUntilComplete(
      tester,
      () => !session.loading && session.hasContent,
      description: '图片竞态首屏正文',
    );
    final fingerprint = session.layoutFingerprint;
    final position = session.progress;
    await _themeMenu(tester);
    await _tap(tester, 'settings-background-image');
    await tester.pumpAndSettle();
    expect(changes, isEmpty, reason: '取消不保存');
    picked = 'image:broken';
    await _tap(tester, 'settings-background-image');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(changes, isEmpty, reason: '损坏图片不保存');
    await _tap(tester, 'settings-bg-none');
    await tester.pumpAndSettle();
    oldLoad.complete(bytes);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(changes, ['none']);
    expect(find.text('图片背景已启用'), findsNothing, reason: '过期图片不回写');
    expect(session.layoutFingerprint, fingerprint);
    expect(session.progress, position);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    source.close();
    await tester.pump();
  });
  testWidgets('恢复缺失图片时回退纯色，不显示已启用图片', (tester) async {
    final source = await openTestChapterSource(_book());
    final changes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPage(
            source: source,
            bookId: 'missing-background',
            store: MemoryReaderProgressStore(),
            backgroundId: 'image:missing',
            backgroundImageLoader: (_) async =>
                throw const FormatException('文件缺失'),
            onBackgroundChanged: changes.add,
          ),
        ),
      ),
    );
    await pumpReaderUntil(tester, find.byType(ReaderView));
    expect(find.text('背景图片无法读取，请重新选择'), findsOneWidget);
    // 提示结束后再点底栏，确保测试确实进入主题抽屉。
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await _themeMenu(tester);
    expect(find.byType(SettingsPanel), findsOneWidget);
    expect(find.text('图片背景已启用'), findsNothing);
    expect(changes, isEmpty, reason: '恢复失败不会保存无效图片');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    source.close();
    await tester.pump();
  });
}
