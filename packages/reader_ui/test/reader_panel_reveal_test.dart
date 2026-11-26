import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/theme/reader_panel_reveal.dart';

void main() {
  testWidgets('按露出范围创建条目，视口尺寸固定，完成后可滚动到末项', (tester) async {
    final animation = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 280),
    );
    final scroll = ScrollController();
    addTearDown(animation.dispose);
    addTearDown(scroll.dispose);
    final built = <int>{};
    animation.forward();
    await tester.pumpWidget(_scene(animation, scroll, built));
    final viewport = find.byType(CustomScrollView);
    final size = tester.getSize(viewport);
    expect(size.height, 400);
    expect(built, everyElement(lessThan(2)), reason: '首帧只创建即将露出的一行');
    await tester.pump(const Duration(milliseconds: 70));
    expect(built, contains(2));
    expect(built, everyElement(lessThan(4)));
    expect(tester.getSize(viewport), size);
    expect(scroll.offset, 0);
    await tester.pumpAndSettle();
    expect(find.text('条目 7'), findsOneWidget);
    expect(tester.getSize(viewport), size);
    await tester.scrollUntilVisible(find.text('条目 19'), 200);
    expect(find.text('条目 19').hitTestable(), findsOneWidget);
    final position = scroll.offset;
    animation.reverse();
    await tester.pump(const Duration(milliseconds: 60));
    expect(scroll.offset, position, reason: '退场不缩小滚动视口或改变位置');
    animation.stop();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('入场中途关闭不补建整屏条目，反向打开继续创建', (tester) async {
    final animation = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 280),
    );
    final scroll = ScrollController();
    addTearDown(animation.dispose);
    addTearDown(scroll.dispose);
    final built = <int>{};
    animation.forward();
    await tester.pumpWidget(_scene(animation, scroll, built));
    await tester.pump(const Duration(milliseconds: 40));
    final beforeClose = Set.of(built);
    animation.reverse();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(built, beforeClose);
    await tester.pumpAndSettle();
    expect(built, beforeClose, reason: '完全收起也不补建屏外内容');
    animation.forward();
    await tester.pumpAndSettle();
    expect(find.text('条目 7'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('无入场动画时立即创建完整可见内容，已开始滚动不再限制范围', (tester) async {
    final animation = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 280),
      value: 1,
    );
    final scroll = ScrollController();
    addTearDown(animation.dispose);
    addTearDown(scroll.dispose);
    final built = <int>{};
    await tester.pumpWidget(_scene(animation, scroll, built));
    expect(find.text('条目 7'), findsOneWidget);
    animation.value = .1;
    animation.forward();
    await tester.pump();
    scroll.jumpTo(300);
    await tester.pump();
    expect(find.text('条目 13'), findsOneWidget);
    expect(scroll.offset, 300);
    animation.stop();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}

Widget _scene(
  Animation<double> animation,
  ScrollController scroll,
  Set<int> built,
) => MaterialApp(
  home: Center(
    child: SizedBox(
      width: 300,
      height: 400,
      child: ReaderPanelReveal(
        animation: animation,
        extent: 400,
        child: CustomScrollView(
          controller: scroll,
          scrollCacheExtent: const ScrollCacheExtent.pixels(0),
          slivers: [
            ReaderPanelSliver(
              sliver: SliverList.builder(
                itemCount: 20,
                itemBuilder: (context, index) {
                  built.add(index);
                  return SizedBox(height: 50, child: Text('条目 $index'));
                },
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);
