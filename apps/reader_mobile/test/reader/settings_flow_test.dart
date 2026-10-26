import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/panels/settings_panel.dart';
import 'package:drift/native.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/theme/reader_margins.dart';

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
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-margin-editor')),
    );
    await tester.pumpAndSettle();

    final pagesBefore = session.chapterPageCount;
    final heightBefore = session.contentHeight ?? 0;

    // 拖「上内」胶囊：数值随手走，但只重绘当前页 —— 不重排。
    await tester.drag(
      find.byKey(const ValueKey<String>('margin-top-inner')),
      const Offset(120, 0),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining(RegExp(r'^上内 \d+$')),
      findsOneWidget,
      reason: '拖动时数值实时变化',
    );
    expect(
      find.text('上内 12'),
      findsNothing,
      reason: '数值已随拖动改变',
    );
    expect(
      session.layoutFingerprint,
      before,
      reason: '拖动阶段不重新分页（只调当前页）',
    );

    // 取消：不应用，边距回到原样。
    await tester.tap(find.byKey(const ValueKey<String>('margin-cancel')));
    await tester.pumpAndSettle();
    expect(applied, isEmpty, reason: '取消不应用');
    expect(
      session.chapterPageCount,
      pagesBefore,
      reason: '取消后分页不变',
    );
    expect(session.layoutFingerprint, before, reason: '取消后排版指纹不变');

    // 再进一次：这次点「保留」→ 立即按新边距重排（不用重开阅读页）。
    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-entry-type')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('settings-margin-editor')),
      80,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-margin-editor')),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey<String>('margin-top-inner')),
      const Offset(120, 0),
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
}
