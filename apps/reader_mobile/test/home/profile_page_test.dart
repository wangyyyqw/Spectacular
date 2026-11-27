import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_sort.dart';
import 'package:reader_mobile/home/profile_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/reader_font_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/panels/reader_settings_sheet.dart';
import 'package:reader_ui/theme/reader_section_slider.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';

class _FakeAppFontStore extends ReaderFontStore {
  _FakeAppFontStore(
    super.library, {
    List<ReaderFontEntry> fonts = const [],
    this.picked,
  }) : _fonts = List.of(fonts);

  final List<ReaderFontEntry> _fonts;
  final ReaderFontEntry? picked;
  final List<String> removed = <String>[];

  @override
  Future<List<ReaderFontEntry>> list() async => List.of(_fonts);

  @override
  Future<ReaderFontEntry?> pick() async {
    final font = picked;
    if (font != null) _fonts.add(font);
    return font;
  }

  @override
  Future<void> remove(String family) async {
    removed.add(family);
    _fonts.removeWhere((font) => font.family == family);
  }
}

void main() {
  for (final scenario in [
    (label: '320dp 窄屏', size: const Size(320, 600), scale: 1.0),
    (label: '大字', size: const Size(400, 800), scale: 1.3),
  ]) {
    testWidgets('${scenario.label}我的页词典设置使用弹窗与固定三分栏', (tester) async {
      tester.view.physicalSize = scenario.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scenario.scale)),
            child: child!,
          ),
          home: ProfilePage(library: LibraryStore.memory()),
        ),
      );
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('dictionary-settings-entry'));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      final sheet = find.byType(ReaderSettingsSheet);
      final tabs = find.byType(ReaderSectionSlider);
      final tabsRect = tester.getRect(tabs);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(tester.widget<ReaderSettingsSheet>(sheet).title, isNull);
      expect(find.byTooltip('关闭'), findsNothing);
      expect(
        tester.getSize(sheet).height,
        closeTo(
          scenario.size.height * ReaderUiStyle.settingsSheetHeightFraction,
          .1,
        ),
      );
      expect(
        tester
            .widget<ReaderSectionSlider>(tabs)
            .sections
            .map((item) => item.label),
        ['AI 查词', '在线词典', '本地词典'],
      );
      expect(find.byKey(const ValueKey('dictionary-api-add')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('dictionary-preset-add')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('dictionary-rule-add')), findsNothing);
      await tester.drag(
        find.descendant(
          of: sheet,
          matching: find.byType(SingleChildScrollView),
        ),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(tabs), tabsRect);
      await tester.tap(
        find.byKey(const ValueKey('dictionary-settings-online')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('dictionary-rule-add')).hitTestable(),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('dictionary-api-add')), findsNothing);
      expect(find.byKey(const ValueKey('dictionary-preset-add')), findsNothing);
      expect(tester.getRect(tabs), tabsRect);
      await tester.tap(find.byKey(const ValueKey('dictionary-settings-local')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('dictionary-local-import')).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('新世纪汉英大词典'), findsOneWidget);
      expect(find.text('大辞海'), findsOneWidget);
      expect(find.text('下载词典'), findsNWidgets(2));
      expect(find.byKey(const ValueKey('dictionary-rule-add')), findsNothing);
      expect(tester.getRect(tabs), tabsRect);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(entry.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('我的页可查看诊断日志且不显示浮动提示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfilePage(library: LibraryStore.memory())),
    );
    await tester.pumpAndSettle();
    expect(find.text('查看诊断日志'), findsOneWidget);

    await tester.tap(find.text('查看诊断日志'));
    await tester.pumpAndSettle();
    expect(find.text('诊断日志'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('诊断日志'), findsNothing);
    expect(find.text('查看诊断日志'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '主题抽屉关闭保留原设置，选择后等待真实保存回调',
    (tester) async {
      final saved = <ThemeMode>[];
      final pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: ProfilePage(
            library: LibraryStore.memory(),
            themeMode: ThemeMode.light,
            onThemeModeChanged: (mode) async {
              saved.add(mode);
              await pending.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('界面主题'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('跟随系统'), findsOneWidget);
      expect(find.text('日间模式'), findsAtLeastNWidgets(1));
      expect(find.text('夜间模式'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);

      await tester.tap(find.text('界面主题'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('夜间模式'));
      await tester.pumpAndSettle();
      expect(saved, [ThemeMode.dark]);
      final themeTile = find.widgetWithText(ListTile, '界面主题');
      expect(tester.widget<ListTile>(themeTile).onTap, isNull);
      pending.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<ListTile>(themeTile).onTap, isNotNull);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    '书架排序抽屉标记当前项，取消保留设置，选择保存原存储',
    (tester) async {
      final library = LibraryStore.memory();
      await library.setSetting(bookshelfSortKey, BookSortOrder.recent.value);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: ProfilePage(library: library),
        ),
      );
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('bookshelf-sort-setting'));
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('bookshelf-sort-recent')),
            )
            .selected,
        isTrue,
      );
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(await library.getSetting(bookshelfSortKey), 'recent');
      await tester.tap(entry);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bookshelf-sort-title')));
      await tester.pumpAndSettle();
      expect(await library.getSetting(bookshelfSortKey), 'title');
      expect((tester.widget<ListTile>(entry).subtitle! as Text).data, '书名');
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );

  testWidgets('应用字体默认思源宋体，可切换已导入的自定义字体', (tester) async {
    final library = LibraryStore.memory();
    const custom = ReaderFontEntry(
      family: 'user_demo',
      filePath: '/测试/演示字体.otf',
      displayName: '演示字体',
    );
    await library.saveUserFont(custom);
    final selected = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ProfilePage(
          library: library,
          themeMode: ThemeMode.light,
          onThemeModeChanged: (_) async {},
          appFontStore: ReaderFontStore(library),
          onAppFontFamilyChanged: (family) async => selected.add(family),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('app-font-setting'));
    expect(entry, findsOneWidget);
    expect((tester.widget<ListTile>(entry).subtitle! as Text).data, '思源宋体');

    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-font-default')), findsOneWidget);
    expect(find.text('演示字体'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('app-font-user_demo')));
    await tester.pumpAndSettle();

    expect(selected, ['user_demo']);
    expect(find.byKey(const ValueKey('app-font-default')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('应用字体可导入并移除，移除当前字体恢复思源宋体', (tester) async {
    const existing = ReaderFontEntry(
      family: 'user_existing',
      filePath: '/测试/已有字体.otf',
      displayName: '已有字体',
    );
    const imported = ReaderFontEntry(
      family: 'user_imported',
      filePath: '/测试/导入字体.otf',
      displayName: '导入字体',
    );
    final store = _FakeAppFontStore(
      LibraryStore.memory(),
      fonts: const [existing],
      picked: imported,
    );
    final selected = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ProfilePage(
          library: LibraryStore.memory(),
          themeMode: ThemeMode.light,
          onThemeModeChanged: (_) async {},
          appFontFamily: existing.family,
          appFontStore: store,
          onAppFontFamilyChanged: (family) async => selected.add(family),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-font-setting')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-font-import')));
    await tester.pumpAndSettle();
    expect(selected, [imported.family]);

    await tester.tap(find.byKey(const ValueKey('app-font-setting')));
    await tester.pumpAndSettle();
    final existingTile = find.byKey(const ValueKey('app-font-user_existing'));
    await tester.ensureVisible(existingTile);
    await tester.tap(
      find.byKey(const ValueKey('app-font-actions-user_existing')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除字体'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-font-remove-confirm')));
    await tester.pumpAndSettle();

    expect(store.removed, [existing.family]);
    expect(selected.last, AppFonts.defaultFamily);
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('app-font-default')))
          .selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('清理日志保留后果确认，可取消返回设置', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ProfilePage(library: LibraryStore.memory()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('logs-clear')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('logs-clear')));
    await tester.pumpAndSettle();
    final confirmation = find.byWidgetPredicate(
      (widget) => widget is AlertDialog,
    );
    expect(confirmation, findsOneWidget);
    expect(find.byKey(const ValueKey('logs-clear-confirm')), findsOneWidget);
    expect(find.text('将删除本机保存的全部诊断日志（含历史会话），确定吗？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(confirmation, findsNothing);
    expect(find.byKey(const ValueKey('logs-clear')), findsOneWidget);
  });

  testWidgets(
    '配色方案抽屉展示全部预设，取消保留原设置，选择后触发真实保存回调',
    (tester) async {
      final saved = <AppThemePreset>[];
      final pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: ProfilePage(
            library: LibraryStore.memory(),
            themePreset: AppThemePreset.clearBlue,
            onThemePresetChanged: (preset) async {
              saved.add(preset);
              await pending.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('theme-preset-setting'));
      expect(entry, findsOneWidget);
      expect((tester.widget<ListTile>(entry).subtitle! as Text).data, '清蓝');

      await tester.tap(entry);
      await tester.pumpAndSettle();
      for (final preset in AppThemePreset.presets) {
        expect(
          find.byKey(ValueKey('theme-preset-${preset.id}')),
          findsOneWidget,
        );
      }
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);

      await tester.tap(entry);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('theme-preset-bamboo_green')));
      await tester.pumpAndSettle();
      expect(saved, [AppThemePreset.bambooGreen]);
      expect(tester.widget<ListTile>(entry).onTap, isNull);
      pending.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<ListTile>(entry).onTap, isNotNull);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );
}
