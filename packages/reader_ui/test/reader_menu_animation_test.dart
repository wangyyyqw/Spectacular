import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/menu/reader_menu_overlay.dart';
import 'package:reader_ui/theme/reader_frosted_surface.dart';
import 'package:reader_ui/theme/reader_panel_theme.dart';

Widget _menu({
  required bool open,
  bool drawer = false,
  bool reduce = false,
  bool ink = false,
  VoidCallback? onClose,
  ValueChanged<ReaderMenuEntry>? onEntry,
  ReaderMenuEntry entry = ReaderMenuEntry.settings,
  Widget? content,
  EdgeInsets padding = EdgeInsets.zero,
  double keyboard = 0,
  Size size = const Size(400, 800),
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(
      size: size,
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
      onEntry: onEntry ?? (_) {},
      drawerTitle: '设置',
      drawerEntry: entry,
      drawerChild: drawer ? content ?? const Text('面板内容') : null,
      onCloseDrawer: onClose ?? () {},
      inkMode: ink,
    ),
  ),
);

void main() {
  testWidgets('菜单入场末帧的磨砂背景保持连续，正文不会突然由清晰变模糊', (tester) async {
    // 真机 1080×2400、450 dpi 对应的逻辑视口。
    const size = Size(384, 2560 / 3);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final boundary = GlobalKey();
    Widget scene(bool open) => MaterialApp(
      home: RepaintBoundary(
        key: boundary,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _StripeBackground()),
            (_menu(open: open, size: size) as MaterialApp).home!,
          ],
        ),
      ),
    );
    Future<List<int>> backgroundSamples() async {
      final image = tester
          .renderObject<RenderRepaintBoundary>(find.byKey(boundary))
          .toImageSync();
      final bytes = (await tester.runAsync(image.toByteData))!;
      final samples = [
        for (final y in [8, size.height.floor() - 8])
          for (final x in [164, 172]) bytes.getUint8((y * image.width + x) * 4),
      ];
      image.dispose();
      return samples;
    }

    await tester.pumpWidget(scene(false));
    await tester.pumpAndSettle();
    final closed = await backgroundSamples();
    await tester.pumpWidget(scene(true));
    await tester.pump(const Duration(milliseconds: 260));
    final entering = await backgroundSamples();
    await tester.pump(const Duration(milliseconds: 20));
    final settled = await backgroundSamples();
    for (var i = 0; i < settled.length; i++) {
      expect(entering[i], closeTo(settled[i], 5), reason: '入场结束时底板不得突变');
    }
    await tester.pumpWidget(scene(false));
    await tester.pumpAndSettle();
    expect(await backgroundSamples(), closed, reason: '完全收起后不残留底板或阴影');
  });

  testWidgets('菜单中途反向开关连续移动，退出期间禁用点击，收起后隐藏', (tester) async {
    var entries = 0;
    final surface = find.byKey(const ValueKey('reader-menu-bottom-surface'));
    await tester.pumpWidget(_menu(open: false));
    expect(surface, findsNothing);
    await tester.pumpWidget(_menu(open: true));
    await tester.pump(const Duration(milliseconds: 80));
    final entering = tester.getRect(surface);
    await tester.pumpWidget(_menu(open: false, onEntry: (_) => entries++));
    expect(tester.getRect(surface), entering);
    await tester.tap(
      find.byKey(const ValueKey('menu-entry-settings')),
      warnIfMissed: false,
    );
    expect(entries, 0);
    await tester.pump(const Duration(milliseconds: 40));
    final exiting = tester.getRect(surface);
    expect(exiting.top, greaterThan(entering.top));
    await tester.pumpWidget(_menu(open: true));
    expect(tester.getRect(surface), exiting);
    await tester.pumpAndSettle();
    expect(tester.getRect(surface).top, lessThan(entering.top));
    await tester.pumpWidget(_menu(open: false));
    await tester.pumpAndSettle();
    expect(surface, findsNothing);
  });

  testWidgets('阅读菜单上下栏与目录抽屉使用同一不透明底板', (tester) async {
    await tester.pumpWidget(_menu(open: true));
    await tester.pumpAndSettle();
    final bars = tester.widgetList<GlassContainer>(find.byType(GlassContainer));
    expect(bars, hasLength(2));
    final settings = bars.first.settings!;
    expect(settings.glassColor.a, 1);
    expect(settings.blur, 0);
    for (final bar in bars) {
      expect(bar.quality, GlassQuality.minimal);
      expect(bar.settings, settings);
    }
    await tester.pumpWidget(_menu(open: true, drawer: true));
    await tester.pumpAndSettle();
    final drawer = tester.widget<GlassContainer>(
      find.descendant(
        of: find.byKey(const ValueKey('reader-drawer-surface')),
        matching: find.byType(GlassContainer),
      ),
    );
    expect(drawer.quality, GlassQuality.minimal);
    expect(drawer.settings, settings);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('阅读菜单和抽屉动画不连带重绘静止背景', (tester) async {
    var paints = 0;
    Widget scene({required bool open, bool drawer = false}) => MaterialApp(
      home: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _PaintProbe(() => paints++)),
          (_menu(open: open, drawer: drawer) as MaterialApp).home!,
        ],
      ),
    );
    await tester.pumpWidget(scene(open: false));
    await tester.pumpAndSettle();
    for (final (open, drawer) in [
      (true, false),
      (true, true),
      (true, false),
      (false, false),
    ]) {
      await tester.pumpWidget(scene(open: open, drawer: drawer));
      await tester.pump(const Duration(milliseconds: 40));
      final painted = paints;
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(paints, painted, reason: '菜单和抽屉自行重绘，静止背景复用');
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('抽屉动画复用主题和导航，静态内容不随动画逐帧重绘', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var paints = 0;
    await tester.pumpWidget(_menu(open: true));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _menu(
        open: true,
        drawer: true,
        content: CustomPaint(
          painter: _PaintProbe(() => paints++),
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));
    final painted = paints;
    expect(painted, greaterThan(0));
    final rebuilt = <Type>[];
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtBefore) {
      previous?.call(element, builtBefore);
      if (element.widget is ReaderPanelTheme ||
          element.widget is ReaderFrostedSurface ||
          element.widget.key == const ValueKey('drawer-entry-settings')) {
        rebuilt.add(element.widget.runtimeType);
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(rebuilt, isEmpty);
    expect(paints, painted, reason: '露出区域变化只合成已有内容');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('四入口位置以未展开时为准，再点当前项原位收起，进度条结束后恢复', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ReaderMenuEntry? selected;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _menu(
          open: true,
          drawer: selected != null,
          entry: selected ?? ReaderMenuEntry.settings,
          padding: const EdgeInsets.only(bottom: 24),
          onEntry: (entry) => setState(() => selected = entry),
          onClose: () => setState(() => selected = null),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final surface = find.byKey(const ValueKey('reader-drawer-surface'));
    final slider = find.byKey(const ValueKey('menu-progress-slider'));
    for (final entry in ReaderMenuEntry.values) {
      final menuButton = find.byKey(ValueKey('menu-entry-${entry.name}'));
      final origin = tester.getRect(menuButton);
      final iconOrigin = tester.getRect(
        find.descendant(of: menuButton, matching: find.byType(AppIcon)),
      );
      final labelOrigin = tester.getRect(
        find.descendant(of: menuButton, matching: find.byType(Text)),
      );
      expect(slider.hitTestable(), findsOneWidget);
      await tester.tap(menuButton);
      await tester.pump();
      final drawerButton = find.byKey(ValueKey('drawer-entry-${entry.name}'));
      expect(tester.getRect(surface).top, origin.top - 6);
      expect(tester.getRect(drawerButton), origin);
      expect(slider, findsNothing);
      final startTop = tester.getRect(surface).top;
      await tester.pump(const Duration(milliseconds: 70));
      expect(tester.getRect(surface).left, 0);
      expect(tester.getRect(surface).right, 400);
      expect(tester.getRect(surface).bottom, 800);
      expect(tester.getRect(surface).top, lessThan(startTop));
      expect(tester.getRect(surface).top, greaterThan(200));
      expect(tester.getRect(drawerButton), origin);
      expect(slider, findsNothing);
      await tester.pumpAndSettle();
      expect(tester.getRect(drawerButton), origin);
      expect(
        tester.getRect(
          find.descendant(of: drawerButton, matching: find.byType(AppIcon)),
        ),
        iconOrigin,
      );
      expect(
        tester.getRect(
          find.descendant(of: drawerButton, matching: find.byType(Text)),
        ),
        labelOrigin,
      );
      expect(tester.getRect(surface).top, 200);
      await tester.tap(drawerButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(slider, findsNothing, reason: '退出动画未结束时不显示进度条');
      expect(tester.getRect(surface).top, greaterThan(200));
      expect(tester.getRect(drawerButton), origin);
      await tester.pumpAndSettle();
      expect(slider.hitTestable(), findsOneWidget);
      expect(surface, findsNothing);
    }
  });

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

  testWidgets('从把手或内容下拉收起只折叠上方内容，导航在拖动、退出和回到菜单后保持原位', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var drawer = false;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _menu(
          open: true,
          drawer: drawer,
          content: ListView(children: const [Text('设置内容')]),
          onEntry: (_) => setState(() => drawer = true),
          onClose: () => setState(() => drawer = false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final menuButton = find.byKey(const ValueKey('menu-entry-settings'));
    final drawerButton = find.byKey(const ValueKey('drawer-entry-settings'));
    final surface = find.byKey(const ValueKey('reader-drawer-surface'));
    final slider = find.byKey(const ValueKey('menu-progress-slider'));
    final origin = tester.getRect(menuButton);
    for (final target in [
      find.byKey(const ValueKey('reader-drawer-handle')),
      find.byType(ListView),
    ]) {
      await tester.tap(menuButton);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(target));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 180));
      await tester.pump();
      expect(tester.getRect(drawerButton), origin);
      expect(tester.getRect(surface).bottom, 800);
      final draggedTop = tester.getRect(surface).top;
      expect(draggedTop, greaterThan(200));
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pump();
      expect(tester.getRect(surface).top, draggedTop, reason: '松手时不跳回完整高度');
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getRect(surface).top, greaterThan(draggedTop));
      expect(tester.getRect(surface).bottom, 800);
      expect(tester.getRect(drawerButton), origin);
      expect(slider, findsNothing);
      await tester.pumpAndSettle();
      expect(surface, findsNothing);
      expect(tester.getRect(menuButton), origin);
      expect(slider.hitTestable(), findsOneWidget);
    }
  });

  testWidgets('抽屉三边贴屏，键盘覆盖底栏时导航与面板保持原位', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Rect? originalSurface;
    Rect? originalNavigation;
    for (final keyboard in [0.0, 160.0, 320.0, 0.0]) {
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
      expect(surface.bottom, 800);
      final nav = find.byKey(const ValueKey('reader-drawer-navigation'));
      final navRect = tester.getRect(nav);
      originalSurface ??= surface;
      originalNavigation ??= navRect;
      expect(surface, originalSurface);
      expect(navRect, originalNavigation);
      if (keyboard > 0) {
        expect(navRect.top, greaterThan(800 - keyboard));
      }
      for (final entry in ReaderMenuEntry.values) {
        final button = find.byKey(ValueKey('drawer-entry-${entry.name}'));
        expect(button.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(button).bottom,
          lessThanOrEqualTo(surface.bottom - 28),
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

  testWidgets('顶部把手下拉跟手，小幅慢拉回弹，大幅慢拉收起', (tester) async {
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
    expect(surface, findsOneWidget);
    expect(find.byType(ReaderFrostedSurface), findsNWidgets(2));
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
      final bottom = find.byKey(const ValueKey('reader-menu-bottom-surface'));
      await tester.pumpWidget(_menu(open: true, reduce: !ink, ink: ink));
      await tester.pump();
      expect(bottom.hitTestable(), findsOneWidget);
      await tester.pumpWidget(_menu(open: false, reduce: !ink, ink: ink));
      await tester.pump();
      expect(bottom, findsNothing);
    });
  }
}

class _PaintProbe extends CustomPainter {
  _PaintProbe(this.onPaint);

  final VoidCallback onPaint;

  @override
  void paint(Canvas canvas, Size size) {
    onPaint();
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_PaintProbe oldDelegate) => false;
}

class _StripeBackground extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, 8, size.height),
        Paint()..color = (x ~/ 8).isEven ? Colors.black : Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_StripeBackground oldDelegate) => false;
}
