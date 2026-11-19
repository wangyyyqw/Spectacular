import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/menu/reader_menu_overlay.dart';
import 'package:reader_ui/theme/reader_frosted_surface.dart';

Widget _menu({
  required bool open,
  bool drawer = false,
  bool reduce = false,
  bool ink = false,
  VoidCallback? onClose,
  Widget? content,
  EdgeInsets padding = EdgeInsets.zero,
  double keyboard = 0,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(400, 800),
      disableAnimations: reduce,
      padding: padding,
      viewInsets: EdgeInsets.only(bottom: keyboard),
    ),
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
      drawerEntry: ReaderMenuEntry.settings,
      drawerChild: drawer ? content ?? const Text('面板内容') : null,
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

  testWidgets('抽屉三边贴屏，底部导航避让手势区和键盘并固定在内容之外', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final keyboard in [0.0, 320.0]) {
      await tester.pumpWidget(
        _menu(
          open: true,
          drawer: true,
          padding: const EdgeInsets.only(top: 30, bottom: 24),
          keyboard: keyboard,
          content: ListView(
            children: [for (var i = 0; i < 40; i++) Text('设置 $i')],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final surface = tester.getRect(
        find.byKey(const ValueKey('reader-drawer-surface')),
      );
      expect(surface.left, 0);
      expect(surface.right, 400);
      expect(surface.bottom, 800 - keyboard);
      final nav = find.byKey(const ValueKey('reader-drawer-navigation'));
      final navRect = tester.getRect(nav);
      for (final entry in ReaderMenuEntry.values) {
        final button = find.byKey(ValueKey('drawer-entry-${entry.name}'));
        expect(button.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(button).bottom,
          lessThanOrEqualTo(surface.bottom - 24),
        );
      }
      await tester.timedDrag(
        find.byType(ListView),
        const Offset(0, -120),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(nav), navRect);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('标题区下拉跟手，小幅慢拉回弹，大幅慢拉收起', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var closes = 0;
    await tester.pumpWidget(
      _menu(open: true, drawer: true, onClose: () => closes++),
    );
    await tester.pumpAndSettle();
    final surface = find.byKey(const ValueKey('reader-drawer-surface'));
    final handle = find.byKey(const ValueKey('reader-drawer-handle'));
    final origin = tester.getTopLeft(surface);
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    expect(tester.getTopLeft(surface).dy, greaterThan(origin.dy));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(closes, 0);
    expect(tester.getTopLeft(surface), origin);
    await tester.timedDrag(
      handle,
      const Offset(0, 180),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(closes, 1);
    expect(find.byType(ReaderFrostedSurface), findsOneWidget);
  });

  testWidgets('列表先滚动，顶部下拉才移动抽屉，短列表同样可收起', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var closes = 0;
    await tester.pumpWidget(
      _menu(
        open: true,
        drawer: true,
        onClose: () => closes++,
        content: ListView.builder(
          controller: controller,
          itemExtent: 44,
          itemCount: 80,
          itemBuilder: (_, index) => Text('目录项 $index'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final surface = find.byKey(const ValueKey('reader-drawer-surface'));
    final origin = tester.getTopLeft(surface);
    await tester.timedDrag(
      find.byType(ListView),
      const Offset(0, -180),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(100));
    expect(tester.getTopLeft(surface), origin);
    expect(closes, 0);
    controller.jumpTo(0);
    await tester.pump();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
    );
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    expect(controller.offset, 0);
    expect(tester.getTopLeft(surface).dy, greaterThan(origin.dy));
    await gesture.moveBy(const Offset(0, -90));
    await tester.pump();
    expect(tester.getTopLeft(surface), origin);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(closes, 0);
    await tester.pumpWidget(
      _menu(
        open: true,
        drawer: true,
        onClose: () => closes++,
        content: ListView(children: const [Text('一条内容')]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.timedDrag(
      find.byType(ListView),
      const Offset(0, 180),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(closes, 1);
  });

  testWidgets('横向滑杆不带动抽屉，横屏不溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var value = 0.2;
    var closes = 0;
    await tester.pumpWidget(
      _menu(
        open: true,
        drawer: true,
        onClose: () => closes++,
        content: StatefulBuilder(
          builder: (context, setState) => ListView(
            children: [
              Slider(
                value: value,
                onChanged: (next) => setState(() => value = next),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final surface = find.byKey(const ValueKey('reader-drawer-surface'));
    final before = tester.getRect(surface);
    await tester.drag(find.byType(Slider), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(value, greaterThan(0.2));
    expect(tester.getRect(surface), before);
    expect(closes, 0);
    expect(tester.takeException(), isNull);
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
