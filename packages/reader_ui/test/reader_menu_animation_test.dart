import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/menu/reader_menu_overlay.dart';

Widget _menu({
  required bool open,
  bool drawer = false,
  bool reduce = false,
  bool ink = false,
  VoidCallback? onClose,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(size: const Size(400, 800), disableAnimations: reduce),
    child: ReaderMenuOverlay(
      open: open,
      theme: null,
      bookTitle: '测试书',
      progress: .2,
      chapterLabel: '第 1 章',
      onBack: () {},
      onToggleDayNight: () {},
      nightMode: false,
      onPreviousChapter: null,
      onNextChapter: null,
      onSeek: (_) {},
      onEntry: (_) {},
      drawerTitle: '设置',
      drawerChild: drawer ? const Text('面板内容') : null,
      onCloseDrawer: onClose ?? () {},
      inkMode: ink,
    ),
  ),
);

void main() {
  testWidgets('抽屉进入与退出保留过渡，退出期间不接受点击', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var closes = 0;
    final surface = find.byKey(const ValueKey('reader-drawer-surface'));
    await tester.pumpWidget(_menu(open: false));
    await tester.pumpWidget(
      _menu(open: true, drawer: true, onClose: () => closes++),
    );
    await tester.pump(const Duration(milliseconds: 70));
    expect(tester.getTopLeft(surface).dy, greaterThan(200));
    expect(tester.getTopLeft(surface).dy, lessThan(800));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(surface).dy, 200);
    await tester.pumpWidget(_menu(open: false, onClose: () => closes++));
    expect(surface, findsOneWidget, reason: '关闭时保留内容直到退出动画完成');
    await tester.tapAt(const Offset(10, 10));
    expect(closes, 0, reason: '正在退出的遮罩不得接受输入');
    await tester.pump(const Duration(milliseconds: 201));
    expect(surface, findsNothing);
  });

  for (final ink in [false, true]) {
    testWidgets('${ink ? '墨水屏' : '减少动态效果'}即时显示和关闭抽屉', (tester) async {
      await tester.pumpWidget(_menu(open: false, reduce: !ink, ink: ink));
      await tester.pumpWidget(
        _menu(open: true, drawer: true, reduce: !ink, ink: ink),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('reader-drawer-surface')),
        findsOneWidget,
      );
      await tester.pumpWidget(_menu(open: false, reduce: !ink, ink: ink));
      await tester.pump();
      expect(find.byKey(const ValueKey('reader-drawer-surface')), findsNothing);
    });
  }
}
