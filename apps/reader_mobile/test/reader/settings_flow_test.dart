import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_ui/panels/settings_panel.dart';
import 'package:drift/native.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/panels/tap_zone_editor.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/theme/reader_margins.dart';
import 'package:reader_ui/tap_zones.dart';

import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/reader_settings.dart';

import '../support/test_epub.dart';

Uint8List _corpusBook(String name) {
  var directory = Directory.current;
  while (true) {
    final candidate = Directory('${directory.path}/test_corpus');
    if (candidate.existsSync()) {
      return File('${candidate.path}/$name').readAsBytesSync();
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('缺少 test_corpus/$name');
    }
    directory = parent;
  }
}

void main() {
  testWidgets('菜单进设置改字号：即时重排并持久化（P4-21）', (tester) async {
    final library = LibraryStore.memory();
    final store = ReaderSettingsStore(library);
    var settings = await store.load();
    expect(settings.fontSize, ReaderSettingsDefaults.fontSize);

    final source = await openTestChapterSource(_corpusBook('basic.epub'));
    late ReaderSession session;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 520,
              child: ReaderPage(
                source: source,
                store: MemoryReaderProgressStore(),
                bookId: 'settings-flow',
                overrides: settings.overrides,
                theme: settings.theme,
                onSessionReady: (value) => session = value,
                onOverridesChanged: (overrides) {
                  settings = ReaderSettings.fromOverrides(
                    overrides,
                    themeId: settings.themeId,
                  );
                  store.save(settings);
                },
                onThemeChanged: (themeId) {
                  settings = settings.copyWithTheme(themeId);
                  store.save(settings);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final fingerprintBefore = session.layoutFingerprint;

    // 点中央 → 菜单 → 设置。
    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-entry-type')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPanel), findsOneWidget);

    // 拖字号滑块。
    await tester.drag(
      find.byKey(const ValueKey<String>('settings-font-size')),
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();

    // 即时重排：布局指纹变化。
    expect(session.layoutFingerprint, isNot(fingerprintBefore));
    // 持久化：重新读取到新字号。
    final reloaded = await store.load();
    expect(reloaded.fontSize, greaterThan(ReaderSettingsDefaults.fontSize));

    // 切主题：关掉排版抽屉 → 主题入口 → 选米黄（设计稿四入口把主题独立成面板）。
    await tester.tap(find.byKey(const ValueKey<String>('menu-drawer-close')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPanel), findsNothing, reason: '关闭排版抽屉');
    await tester.tap(find.byKey(const ValueKey<String>('menu-entry-theme')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPanel), findsOneWidget, reason: '主题抽屉打开');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('settings-theme-sepia')),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-theme-sepia')),
    );
    await tester.pumpAndSettle();
    expect((await store.load()).themeId, 'sepia');
  });

  test('页边距（含上下外/内段）持久化往返（P8-10）', () async {
    final dir = Directory.systemTemp.createTempSync('margin-settings');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => dir,
    );
    final store = ReaderSettingsStore(library);

    expect((await store.load()).margins, isNull, reason: '默认没有自定义边距');

    final margins = ReaderMargins.defaults(
      safeTop: 41,
      safeBottom: 16,
      side: 22,
      inner: 14,
    ).copyWith(topOuter: 0, bottomOuter: 0);
    await store.save(ReaderSettings.defaults.copyWithMargins(margins));

    final reloaded = await store.load();
    expect(reloaded.margins, margins);
    expect(reloaded.margins!.top, 14, reason: '外段归零后只剩内段');
  });

  test('正文字体持久化，损坏值回落书籍字体', () async {
    final library = LibraryStore.memory();
    final store = ReaderSettingsStore(library);

    expect((await store.load()).fontFamily, isNull);
    final settings = ReaderSettings.fromOverrides(
      ReaderSettings.defaults.overrides.copyWith(
        fontFamily: FontFamilyAliases.song,
      ),
      themeId: ReaderSettings.defaults.themeId,
    );
    await store.save(settings);
    expect((await store.load()).fontFamily, FontFamilyAliases.song);

    await store.save(
      ReaderSettings.fromOverrides(
        settings.overrides.copyWith(
          fontFamily: ReaderSettingsDefaults.fontSans,
        ),
        themeId: settings.themeId,
      ),
    );
    expect((await store.load()).fontFamily, ReaderSettingsDefaults.fontSans);

    await library.setSetting(ReaderSettingsStore.keyFontFamily, 'missing-font');
    expect((await store.load()).fontFamily, isNull);
  });

  test('九宫格点击区域持久化往返，损坏数据回落默认', () async {
    final library = LibraryStore.memory();
    final store = ReaderSettingsStore(library);

    expect((await store.load()).tapZones, ReaderTapZones.defaults);
    final zones = ReaderTapZones.defaults
        .withAction(ReaderTapZone.middleLeft, ReaderTapAction.nextPage)
        .withAction(ReaderTapZone.middleRight, ReaderTapAction.openMenu);
    await store.save(ReaderSettings.defaults.copyWithTapZones(zones));
    expect((await store.load()).tapZones, zones);

    await library.setSetting(ReaderSettingsStore.keyTapZones, '{bad json');
    expect((await store.load()).tapZones, ReaderTapZones.defaults);
  });

  test('翻页方式持久化往返，损坏值回落覆盖翻页', () async {
    final library = LibraryStore.memory();
    final store = ReaderSettingsStore(library);

    expect((await store.load()).pageTurnMode, PageTurnMode.cover);
    await store.save(
      ReaderSettings.defaults.copyWithPageTurnMode(
        PageTurnMode.simulationBessel,
      ),
    );
    expect((await store.load()).pageTurnMode, PageTurnMode.simulationBessel);

    await library.setSetting(
      ReaderSettingsStore.keyPageTurnMode,
      'removed-mode',
    );
    expect((await store.load()).pageTurnMode, PageTurnMode.cover);
  });

  test('修改排版不会重置九宫格点击区域', () {
    final zones = ReaderTapZones.defaults.withAction(
      ReaderTapZone.center,
      ReaderTapAction.none,
    );
    final settings = ReaderSettings.defaults.copyWithTapZones(zones);
    final changed = settings.copyWithOverrides(
      settings.overrides.copyWith(fontSize: 21),
    );
    expect(changed.tapZones, zones);
    expect(changed.fontSize, 21);
  });

  testWidgets('设置入口可编辑九宫格并立即生效', (tester) async {
    final source = await openTestChapterSource(_corpusBook('basic.epub'));
    late ReaderSession session;
    ReaderTapZones? applied;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 520,
              child: ReaderPage(
                source: source,
                store: MemoryReaderProgressStore(),
                bookId: 'tap-zones',
                onSessionReady: (value) => session = value,
                onTapZonesChanged: (zones) => applied = zones,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(await session.next(), isTrue);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-entry-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('settings-tap-zones')));
    await tester.pumpAndSettle();
    expect(find.byType(TapZoneEditor), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('tap-zone-topLeft')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('tap-zone-topLeft')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('tap-zone-apply')));
    await tester.pumpAndSettle();
    expect(applied?.actionAt(ReaderTapZone.topLeft), ReaderTapAction.openMenu);

    final rect = tester.getRect(find.byType(ReaderView));
    await tester.tapAt(Offset(rect.left + 4, rect.top + rect.height * 0.15));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-entry-settings')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPanel), findsOneWidget);
  });

  testWidgets('边距调节器拖动实时预览，取消后恢复（P8-10）', (tester) async {
    final bytes = buildTestEpub(
      title: '边距预览',
      paragraphs: const <String>['第一段内容足够长以便分页。', '第二段内容。'],
    );
    final source = await openTestChapterSource(bytes);
    late ReaderSession session;
    final applied = <ReaderMargins>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 520,
              child: ReaderPage(
                source: source,
                store: MemoryReaderProgressStore(),
                bookId: 'margin-preview',
                onSessionReady: (value) => session = value,
                onMarginsChanged: applied.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = session.layoutFingerprint;

    // 菜单 → 排版 → 边距调节器。
    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-entry-type')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('settings-margin-editor')),
      80,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-margin-editor')),
    );
    await tester.pumpAndSettle();

    final pagesBefore = session.chapterPageCount;
    final heightBefore = session.contentHeight ?? 0;

    // 向下拖「上内」胶囊：留白向下扩张，当前章同步重新分页。
    await tester.drag(
      find.byKey(const ValueKey<String>('margin-top-inner')),
      const Offset(0, 120),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining(RegExp(r'^上内 \d+$')),
      findsOneWidget,
      reason: '拖动时数值实时变化',
    );
    expect(find.text('上内 12'), findsNothing, reason: '数值已随拖动改变');
    expect(
      session.layoutFingerprint,
      before,
      reason: '边距只改变正文区尺寸，不改变字号等排版设置指纹',
    );
    expect(session.contentHeight, lessThan(heightBefore));
    expect(session.page!.pageHeight, session.contentHeight);

    // 取消：不应用，边距回到原样。
    await tester.tap(find.byKey(const ValueKey<String>('margin-cancel')));
    await tester.pumpAndSettle();
    expect(applied, isEmpty, reason: '取消不应用');
    expect(session.chapterPageCount, pagesBefore, reason: '取消后分页不变');
    expect(session.layoutFingerprint, before, reason: '取消后排版指纹不变');
    expect(session.contentHeight, heightBefore, reason: '取消恢复原分页尺寸');

    // 再进一次：保存保留实时重排结果，无需重开阅读页。
    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-entry-type')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('settings-margin-editor')),
      80,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-margin-editor')),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey<String>('margin-top-inner')),
      const Offset(0, 120),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('margin-apply')));
    await tester.pumpAndSettle();
    expect(applied, hasLength(1), reason: '保留回传一次');
    expect(applied.single.topInner, greaterThan(12));
    expect(
      session.contentHeight ?? 0,
      lessThan(heightBefore),
      reason: '保留后正文区立即变小（按新边距重排），无需重开页面',
    );
  });

  testWidgets('恢复默认同时重置墨水屏、边距、点击区域和翻页方式', (tester) async {
    final source = await openTestChapterSource(
      buildTestEpub(
        title: '恢复默认',
        paragraphs: const <String>['第一段内容足够长以便分页。', '第二段内容。'],
      ),
    );
    final inkValues = <bool>[];
    final marginsValues = <ReaderMargins>[];
    final tapZonesValues = <ReaderTapZones>[];
    final pageTurnValues = <PageTurnMode>[];
    final customMargins = ReaderMargins.defaults(
      safeTop: 20,
      safeBottom: 20,
      side: 48,
      inner: 30,
    );
    final customZones = ReaderTapZones.defaults.withAction(
      ReaderTapZone.topLeft,
      ReaderTapAction.openMenu,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 520,
              child: ReaderPage(
                source: source,
                store: MemoryReaderProgressStore(),
                bookId: 'reset-all-settings',
                inkMode: true,
                margins: customMargins,
                tapZones: customZones,
                pageTurnMode: PageTurnMode.scroll,
                onInkModeChanged: inkValues.add,
                onMarginsChanged: marginsValues.add,
                onTapZonesChanged: tapZonesValues.add,
                onPageTurnModeChanged: pageTurnValues.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('menu-entry-settings')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('settings-reset')));
    await tester.pumpAndSettle();

    expect(inkValues, <bool>[false]);
    expect(marginsValues, hasLength(1));
    expect(
      marginsValues.single.left,
      ReaderSettingsDefaults.horizontalPadding,
    );
    expect(tapZonesValues.single, ReaderTapZones.defaults);
    expect(pageTurnValues.single, PageTurnMode.cover);
  });
}
