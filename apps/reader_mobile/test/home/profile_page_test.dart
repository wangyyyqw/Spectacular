import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_sort.dart';
import 'package:reader_mobile/home/profile_page.dart';
import 'package:reader_mobile/home/app_settings_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/rea_micro/rea_micro_controller.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';
import 'package:reader_mobile/reader/reader_font_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';

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

  testWidgets('设置页可查看诊断日志且不显示浮动提示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: AppSettingsPage(library: LibraryStore.memory())),
    );
    await tester.pumpAndSettle();
    expect(find.text('查看诊断日志'), findsOneWidget);

    await tester.tap(find.text('查看诊断日志'));
    await tester.pumpAndSettle();
    expect(find.text('诊断日志'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    await tester.binding.handlePopRoute();
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
      await tester.tap(find.text('界面主题'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(RadioListTile<ThemeMode>), findsNWidgets(3));
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
        (tester.widget<ListTile>(themeTile).subtitle! as Text).data,
        '夜间模式',
      );
      await tester.tap(themeTile);
      await tester.pumpAndSettle();
      final group = tester.widget<RadioGroup<ThemeMode>>(
        find.byType(RadioGroup<ThemeMode>),
      );
      expect(group.groupValue, ThemeMode.dark);
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
    '书架排序抽屉标记当前项，取消保留设置，选择保存原存储',
    (tester) async {
      final library = LibraryStore.memory();
      await library.setSetting(bookshelfSortKey, BookSortOrder.recent.value);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: AppSettingsPage(library: library),
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
      await tester.pageBack();
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

  testWidgets('清理日志保留后果确认，可取消返回设置', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: AppSettingsPage(library: LibraryStore.memory()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('logs-clear')));
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
