import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/diagnostics/reader_log.dart';
import 'package:reader_mobile/dictionary/dictionary_settings_page.dart';
import 'package:reader_mobile/home/bookshelf_sort.dart';
import 'package:reader_mobile/home/profile_page.dart';
import 'package:reader_mobile/home/app_settings_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/rea_micro/rea_micro_controller.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';
import 'package:reader_mobile/reader/reader_font_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/panels/reader_settings_sheet.dart';
import 'package:reader_ui/theme/reader_section_slider.dart';
import 'package:reader_ui/theme/reader_ui_components.dart';
import 'package:reader_ui/theme/reader_switch.dart';

class _AccountController extends ReaMicroController {
  _AccountController()
    : super(library: LibraryStore.memory(), enableLanLoginServer: false);
  ReaMicroUser? account = const ReaMicroUser(
    id: 123,
    nickName: '测试读者',
    avatar: 'https://example.test/avatar.png',
    totalReadTimeSeconds: 7260,
  );
  @override
  bool get signedIn => account != null;
  @override
  ReaMicroUser? get user => account;
  void clearAccount() {
    account = null;
    notifyListeners();
  }
}

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
    testWidgets('${scenario.label}词典设置独立成页，滚动时固定三分栏', (tester) async {
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
      await tester.tap(find.byKey(const ValueKey('profile-settings-entry')));
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('dictionary-settings-entry'));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      final page = find.byType(DictionarySettingsPage);
      final tabs = find.byType(ReaderSectionSlider);
      final tabsRect = tester.getRect(tabs);
      void checkHeader(String title, String addKey, [String? sortKey]) {
        final add = find.byKey(ValueKey(addKey));
        final heading = find.descendant(of: page, matching: find.text(title)).last;
        final button = tester.widget<IconButton>(add);
        expect(button.tooltip, isNotEmpty);
        expect(tester.widget<Text>(heading).style?.fontSize, 16);
        expect(tester.getRect(add).top - tabsRect.bottom, closeTo(4, .01));
        expect(tester.getCenter(add).dy, closeTo(tester.getCenter(heading).dy, .01));
        expect(tester.getSize(add).shortestSide, greaterThanOrEqualTo(48));
        if (sortKey != null) {
          final sort = find.byKey(ValueKey(sortKey));
          expect(tester.getSize(sort), tester.getSize(add));
          expect((tester.widget<IconButton>(sort).icon as AppIcon).size,
              (button.icon as AppIcon).size);
        }
      }
      checkHeader('释义服务', 'dictionary-api-add');
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(ReaderSettingsSheet), findsNothing);
      expect(find.widgetWithText(AppBar, '词典设置'), findsOneWidget);
      expect(tester.getSize(page).height, scenario.size.height);
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
          of: page,
          matching: find.byType(ListView),
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
      checkHeader('在线词典规则', 'dictionary-rule-add', 'dictionary-online-sort');
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
      checkHeader('本地词典', 'dictionary-local-import', 'dictionary-local-sort');
      expect(find.text('下载词典'), findsNWidgets(2));
      expect(find.byKey(const ValueKey('dictionary-rule-add')), findsNothing);
      expect(tester.getRect(tabs), tabsRect);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(page, findsNothing);
      expect(entry.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('我的页仅显示五个入口标题，头像进入账号', (tester) async {
    final controller = _AccountController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePage(
          library: LibraryStore.memory(),
          reaMicro: controller,
          onThemeModeChanged: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('外观'), findsNothing);
    expect(find.text('阅读'), findsNothing);
    expect(find.text('帮助与诊断'), findsNothing);
    expect(find.text('关于'), findsNothing);
    expect(find.byKey(const ValueKey('reamicro-entry')), findsNothing);
    for (final title in ['野社', '社区', '互联', '同步', '设置']) {
      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, title),
      );
      expect(tile.subtitle, isNull);
    }
    await tester.ensureVisible(
      find.byKey(const ValueKey('profile-settings-entry')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-settings-entry')));
    await tester.pumpAndSettle();
    expect(find.byType(AppSettingsPage), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('阅读'), findsOneWidget);
    expect(find.text('词典设置'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('帮助与诊断'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('帮助与诊断'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('关于'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('关于'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-account-entry')),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-account-entry')));
    await tester.pumpAndSettle();
    expect(find.text('账号'), findsOneWidget);
  });

  testWidgets('我的页展示登录账号头像昵称时长与ID并响应退出', (tester) async {
    final controller = _AccountController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePage(library: LibraryStore.memory(), reaMicro: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('测试读者'), findsOneWidget);
    expect(find.text('累计阅读 2 小时 1 分\n阅微 ID：123'), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image).first);
    expect(
      (image.image as ResizeImage).imageProvider,
      const NetworkImage('https://example.test/avatar.png'),
    );
    controller.clearAccount();
    await tester.pumpAndSettle();
    expect(find.text('测试读者'), findsNothing);
    expect(find.text('登录后查看阅读时长与阅微 ID'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('查看日志独立成页且不显示浮动提示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: AppSettingsPage(library: LibraryStore.memory())),
    );
    await tester.pumpAndSettle();
    expect(find.text('查看诊断日志'), findsNothing);

    await tester.tap(find.text('查看日志'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '查看日志'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '设置'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '查看日志'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '主题选项菜单关闭保留原设置，选择后等待真实保存回调',
    (tester) async {
      final saved = <ThemeMode>[];
      final pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: AppSettingsPage(
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
      expect(find.text('界面主题'), findsNothing);
      await tester.tap(find.text('主题外观'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('界面主题'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(PopupMenuItem<ThemeMode>), findsNWidgets(3));
      await tester.binding.handlePopRoute();
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
      expect(
        find.descendant(of: themeTile, matching: find.text('夜间模式')),
        findsOneWidget,
      );
      await tester.tap(themeTile);
      await tester.pumpAndSettle();
      final option = find.widgetWithText(PopupMenuItem<ThemeMode>, '夜间模式');
      expect(find.descendant(of: option, matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.selected == true,
      )), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    '书架管理恢复新书置顶偏好，关闭不改值，切换后持久化且不改旧排序',
    (tester) async {
      final library = LibraryStore.memory();
      await library.setSetting(bookshelfSortKey, BookSortOrder.title.value);
      await library.setSetting(bookshelfNewestFirstKey, 'true');
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: AppSettingsPage(library: library),
        ),
      );
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('bookshelf-management-entry'));
      final toggle = find.byKey(
        const ValueKey('bookshelf-newest-first-setting'),
      );
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, '书架管理'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.descendant(of: find.byType(ReaderSectionGroup), matching: find.byType(ReaderSwitchListTile)), findsNWidgets(7));
      expect(tester.widget<ReaderSwitchListTile>(toggle).value, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(toggle, findsNothing);
      expect(await library.getSetting(bookshelfNewestFirstKey), 'true');
      await tester.tap(entry);
      await tester.pumpAndSettle();
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<ReaderSwitchListTile>(toggle).value, isFalse);
      expect(await library.getSetting(bookshelfNewestFirstKey), 'false');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(tester.widget<ReaderSwitchListTile>(toggle).value, isFalse);
      expect(
        await library.getSetting(bookshelfSortKey),
        BookSortOrder.title.value,
      );
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
        home: AppSettingsPage(
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
    expect(find.descendant(of: entry, matching: find.text('思源宋体')), findsOneWidget);

    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '应用字体'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
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
        home: AppSettingsPage(
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
    final importedTile = find.byKey(const ValueKey('app-font-user_imported'));
    await tester.ensureVisible(importedTile);
    await tester.tap(
      find.byKey(const ValueKey('app-font-actions-user_imported')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除字体'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-font-remove-confirm')));
    await tester.pumpAndSettle();

    expect(store.removed, [imported.family]);
    expect(selected.last, AppFonts.defaultFamily);
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('app-font-default')))
          .selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置行去掉副标题，日志操作移至查看页并在确认清理后刷新', (tester) async {
    await tester.runAsync(() => ReaderLog.instance.log('settings_log_clear_test'));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: AppSettingsPage(library: LibraryStore.memory()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('logs-clear')), findsNothing);
    expect(find.byTooltip('导出日志'), findsNothing);
    expect(tester.widgetList<ListTile>(find.byType(ListTile)).every((tile) => tile.subtitle == null), isTrue);
    final about = find.byKey(const ValueKey('about-entry'));
    await tester.ensureVisible(about);
    expect((tester.widget<ListTile>(about).leading! as AppIcon).glyph, AppGlyph.info);
    final view = find.text('查看日志');
    await tester.ensureVisible(view);
    await tester.tap(view);
    await tester.pumpAndSettle();
    final bar = find.byType(AppBar);
    expect(find.descendant(of: bar, matching: find.byTooltip('导出日志')), findsOneWidget);
    expect(find.descendant(of: bar, matching: find.byTooltip('清理日志')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('logs-clear')));
    await tester.pumpAndSettle();
    final confirmation = find.byWidgetPredicate(
      (widget) => widget is AlertDialog,
    );
    expect(confirmation, findsOneWidget);
    expect(find.byKey(const ValueKey('logs-clear-confirm')), findsOneWidget);
    expect(find.textContaining('保留上传失败记录'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(confirmation, findsNothing);
    expect(find.byKey(const ValueKey('logs-clear')), findsOneWidget);
    String text() => tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(text(), contains('settings_log_clear_test'));
    await tester.tap(find.byTooltip('清理日志'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('logs-clear-confirm')));
    await tester.pumpAndSettle();
    expect(text(), isNot(contains('settings_log_clear_test')));
    expect(find.text('日志清理失败'), findsNothing);
  });

  testWidgets('账号与同步中社区入口位于野社入口下方', (tester) async {
    final library = LibraryStore.memory();
    final controller = ReaMicroController(
      library: library,
      enableLanLoginServer: false,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePage(library: library, reaMicro: controller),
      ),
    );
    await tester.pumpAndSettle();

    final community = find.byKey(const ValueKey<String>('community-entry'));
    await tester.scrollUntilVisible(
      community,
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(community, findsOneWidget);
    expect(find.byKey(const ValueKey<String>('ye-she-entry')), findsOneWidget);
    expect(
      tester.getTopLeft(community).dy,
      greaterThan(
        tester
            .getTopLeft(find.byKey(const ValueKey<String>('ye-she-entry')))
            .dy,
      ),
    );
  });
}
