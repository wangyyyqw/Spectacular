import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/menu/reader_menu_overlay.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/tap_zones.dart';

class _Source implements ReaderChapterSource {
  _Source(this.chapterCount);

  @override
  final int chapterCount;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => [
    for (var page = 0; page < 3; page++)
      PageContent(
        spineIndex: spineIndex,
        pageIndex: page,
        slices: const [],
        usedHeight: 0,
        pageHeight: 300,
        topPadding: 0,
      ),
  ];
}

Future<ReaderSession> _open(
  WidgetTester tester,
  int chapters, {
  ReaderTapZones tapZones = ReaderTapZones.defaults,
  bool inkMode = false,
}) async {
  late ReaderSession session;
  await tester.pumpWidget(
    MaterialApp(
      home: ReaderPage(
        source: _Source(chapters),
        store: MemoryReaderProgressStore(),
        bookId: 'menu',
        tapZones: tapZones,
        inkMode: inkMode,
        onSessionReady: (value) => session = value,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byType(ReaderView));
  await tester.pumpAndSettle();
  return session;
}

Finder _button(String direction) =>
    find.byKey(ValueKey('menu-$direction-chapter'));

void main() {
  testWidgets('菜单外九宫格点击只关闭菜单，不改变阅读页', (tester) async {
    final session = await _open(tester, 3);
    await session.next();
    await tester.pumpAndSettle();
    final page = session.page;
    final bounds = tester.getRect(find.byType(ReaderView));

    // 上下行选在菜单栏之外，同时覆盖九宫格的全部点击动作。
    for (final y in [0.32, 0.5, 0.67]) {
      for (final x in [1 / 6, 0.5, 5 / 6]) {
        await tester.tapAt(
          bounds.topLeft + Offset(bounds.width * x, bounds.height * y),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay)).open,
          isFalse,
        );
        expect(session.page, same(page));
        expect(
          session.progress,
          const ReaderProgress(spineIndex: 0, pageIndex: 1),
        );

        await tester.tapAt(bounds.center);
        await tester.pumpAndSettle();
        expect(
          tester.widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay)).open,
          isTrue,
        );
      }
    }
  });

  testWidgets('关闭菜单的点击不翻页，下次点击恢复左右翻页', (tester) async {
    final session = await _open(tester, 3);
    await session.next();
    await tester.pumpAndSettle();
    final bounds = tester.getRect(find.byType(ReaderView));
    final right = bounds.centerRight - const Offset(20, 0);

    await tester.tapAt(right);
    await tester.pumpAndSettle();
    expect(session.progress, const ReaderProgress(spineIndex: 0, pageIndex: 1));
    await tester.tapAt(right);
    await tester.pumpAndSettle();
    expect(session.progress, const ReaderProgress(spineIndex: 0, pageIndex: 2));
    await tester.tapAt(bounds.centerLeft + const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(session.progress, const ReaderProgress(spineIndex: 0, pageIndex: 1));
  });

  testWidgets('自定义无动作区域也能关闭菜单', (tester) async {
    final session = await _open(
      tester,
      3,
      tapZones: ReaderTapZones.defaults.withAction(
        ReaderTapZone.middleRight,
        ReaderTapAction.none,
      ),
    );
    final page = session.page;
    final bounds = tester.getRect(find.byType(ReaderView));
    await tester.tapAt(bounds.centerRight - const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay)).open,
      isFalse,
    );
    expect(session.page, same(page));
  });

  testWidgets('进度按钮跳到相邻章首页，滑块仍按全书进度跳转', (tester) async {
    final semantics = tester.ensureSemantics();
    final session = await _open(tester, 3);
    expect(find.bySemanticsLabel('上一章'), findsOneWidget);
    expect(find.bySemanticsLabel('下一章'), findsOneWidget);
    expect(tester.widget<InkResponse>(_button('prev')).onTap, isNull);

    await session.next();
    await tester.pumpAndSettle();
    expect(session.progress, const ReaderProgress(spineIndex: 0, pageIndex: 1));
    await tester.tap(_button('next'));
    await tester.pumpAndSettle();
    expect(session.progress, const ReaderProgress(spineIndex: 1, pageIndex: 0));
    await tester.tap(_button('prev'));
    await tester.pumpAndSettle();
    expect(session.progress, const ReaderProgress(spineIndex: 0, pageIndex: 0));

    final slider = find.byKey(const ValueKey('menu-progress-slider'));
    final bounds = tester.getRect(slider);
    await tester.tapAt(
      Offset(bounds.left + bounds.width * 0.9, bounds.center.dy),
    );
    await tester.pumpAndSettle();
    expect(session.progress, const ReaderProgress(spineIndex: 2, pageIndex: 0));
    expect(tester.widget<InkResponse>(_button('next')).onTap, isNull);
    await tester.tap(_button('next'));
    await tester.pumpAndSettle();
    expect(session.progress, const ReaderProgress(spineIndex: 2, pageIndex: 0));
    semantics.dispose();
  });

  testWidgets('单章书两侧章节按钮均禁用', (tester) async {
    final session = await _open(tester, 1);
    expect(tester.widget<InkResponse>(_button('prev')).onTap, isNull);
    expect(tester.widget<InkResponse>(_button('next')).onTap, isNull);
    expect(session.progress, const ReaderProgress(spineIndex: 0, pageIndex: 0));
  });

  testWidgets('墨水屏模式禁用日夜切换', (tester) async {
    await _open(tester, 3, inkMode: true);
    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('menu-daynight')),
    );
    expect(button.onPressed, isNull);
    expect(button.tooltip, '墨水屏模式固定纯黑白');
  });
}
