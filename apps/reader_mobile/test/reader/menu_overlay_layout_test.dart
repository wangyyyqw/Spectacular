import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/menu/reader_menu_overlay.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

void main() {
  for (final mode in [PageTurnMode.simulation3d, PageTurnMode.scroll]) {
    testWidgets('$mode 拖动菜单进度在松手后定位 EPUB 并保存位置', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.reset);
      final source = await openTestChapterSource(
        buildMultiChapterEpub(
          chapters: List.generate(3, (index) => '第${index + 1}章的进度测试。' * 200),
        ),
      );
      addTearDown(source.close);
      final store = MemoryReaderProgressStore();
      late ReaderSession session;
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderPage(
            source: source,
            store: store,
            bookId: 'progress-drag',
            contentRevision: '进度拖动回归版本',
            pageTurnMode: mode,
            onSessionReady: (value) => session = value,
          ),
        ),
      );
      await pumpReaderUntilComplete(
        tester,
        () => !session.loading && session.hasContent,
      );
      await tester.tapAt(tester.getCenter(find.byType(ReaderView).first));
      await tester.pumpAndSettle();
      final before = session.currentCfi;
      final bounds = tester.getRect(
        find.byKey(const ValueKey('menu-progress-slider')),
      );
      final gesture = await tester.startGesture(bounds.center);
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveTo(
        Offset(bounds.left + bounds.width * .75, bounds.center.dy + 12),
      );
      await tester.pump();
      expect(session.currentCfi, before);
      expect(session.jumpLoadingTitle, isNull);
      await gesture.up();
      await pumpReaderUntilComplete(
        tester,
        () => session.jumpLoadingTitle == null && session.currentCfi != before,
        description: '进度拖动跳转完成',
      );
      expect(session.progress?.spineIndex, 2);
      expect(session.readingPercent, closeTo(.75, .04));
      await pumpReaderTask(tester, session.flushProgress());
      expect((await store.load('progress-drag'))?.cfi, session.readingCfi);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets('菜单与抽屉开关是浮层：排版指纹不变（不重排）', (tester) async {
    final bars = <Object?>[];
    const channel = MethodChannel('com.spectacular.reader_mobile/reader');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'setSystemBars') bars.add(call.arguments);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    final bytes = buildTestEpub(
      title: '浮层菜单',
      paragraphs: const <String>['第一段内容足够长以便分页显示多行。', '第二段内容。'],
    );
    final source = await openTestChapterSource(bytes);
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
                bookId: 'overlay-menu',
                onSessionReady: (value) => session = value,
              ),
            ),
          ),
        ),
      ),
    );
    await pumpReaderUntilComplete(
      tester,
      () => !session.loading && session.hasContent,
      description: '浮层菜单首屏正文',
    );
    final fingerprint = session.layoutFingerprint;
    final pageBefore = session.page;
    expect(bars.last, {'statusBar': false, 'navigationBar': false});

    // 打开菜单。
    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    tester.view.viewPadding = const FakeViewPadding(top: 30);
    await tester.pumpAndSettle();
    expect(bars.last, {'statusBar': true, 'navigationBar': false});

    // 四个入口共用下拉抽屉；下拉收起直接退出阅读菜单，不翻页、不重排。
    for (final entry in ['toc', 'theme', 'type', 'settings']) {
      if (!tester
          .widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay))
          .open) {
        await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(ValueKey('menu-entry-$entry')));
      await tester.pumpAndSettle();
      final surface = find.byKey(const ValueKey('reader-drawer-surface'));
      expect(surface, findsOneWidget);
      expect(tester.getRect(surface).top, greaterThanOrEqualTo(140));
      await tester.timedDrag(
        find.byKey(const ValueKey('reader-drawer-handle')),
        const Offset(0, 160),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(surface, findsNothing);
      expect(
        tester.widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay)).open,
        isFalse,
        reason: '下拉收起抽屉应直接退出阅读菜单',
      );
      expect(session.layoutFingerprint, fingerprint);
      expect(session.page, same(pageBefore));
    }
    // 重新打开菜单继续验证浮层位置。
    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    expect(session.layoutFingerprint, fingerprint, reason: '开菜单不重排');
    expect(session.page, same(pageBefore), reason: '页码与内容不变');

    // 打开主题抽屉（浮层叠加）。
    await tester.tap(find.byKey(const ValueKey<String>('menu-entry-theme')));
    await tester.pumpAndSettle();
    expect(session.layoutFingerprint, fingerprint, reason: '开抽屉不重排');
    expect(bars.last, {'statusBar': true, 'navigationBar': false});

    // 关闭抽屉 → 关闭菜单。
    final drawerBounds = tester.getRect(
      find.byKey(const ValueKey('reader-drawer-surface')),
    );
    final pageBounds = tester.getRect(find.byType(ReaderView));
    expect(drawerBounds.left, pageBounds.left);
    expect(drawerBounds.right, pageBounds.right);
    expect(drawerBounds.bottom, pageBounds.bottom);
    final navigation = tester.getRect(
      find.byKey(const ValueKey('reader-drawer-navigation')),
    );
    for (final entry in ReaderMenuEntry.values) {
      await tester.tap(find.byKey(ValueKey('drawer-entry-${entry.name}')));
      await tester.pumpAndSettle();
      final overlay = tester.widget<ReaderMenuOverlay>(
        find.byType(ReaderMenuOverlay),
      );
      expect(overlay.drawerEntry, entry);
      expect(overlay.drawerChild, isNotNull);
      expect(
        tester.getRect(find.byKey(const ValueKey('reader-drawer-navigation'))),
        navigation,
      );
      expect(session.layoutFingerprint, fingerprint);
      expect(session.page, same(pageBefore));
    }
    // 再点当前入口同样退出阅读菜单，阅读位置不变。
    await tester.tap(find.byKey(const ValueKey('drawer-entry-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-drawer-surface')), findsNothing);
    expect(
      tester.widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay)).open,
      isFalse,
    );
    expect(session.page, same(pageBefore));
    expect(session.layoutFingerprint, fingerprint);
    await tester.binding.handlePopRoute();
    tester.view.viewPadding = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(bars.last, {'statusBar': false, 'navigationBar': false});
    expect(session.layoutFingerprint, fingerprint, reason: '收菜单不重排');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(bars.last, {'statusBar': true, 'navigationBar': true});
    source.close();
    await tester.pump();
  });
}
