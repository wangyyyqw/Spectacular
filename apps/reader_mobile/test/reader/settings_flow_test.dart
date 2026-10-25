import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/panels/settings_panel.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

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
    await tester.tap(find.byKey(const ValueKey<String>('menu-settings')));
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

    // 切主题：不重排但主题落库（主题在列表下方，先滚动到可见）。
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
}
