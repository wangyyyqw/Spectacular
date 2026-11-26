import 'dart:ui' show SemanticsAction;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/menu/reader_menu_overlay.dart';
import 'package:reader_ui/icons/app_icon.dart';

final _slider = find.byKey(const ValueKey('menu-progress-slider'));

Future<void> _open(WidgetTester tester, List<double> seeks) async {
  await tester.binding.setSurfaceSize(const Size(360, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: ReaderMenuOverlay(
        open: true,
        theme: null,
        bookTitle: '进度拖动回归',
        progress: .2,
        chapterLabel: '第一章 · 2/10 页',
        onBack: () {},
        onToggleDayNight: () {},
        nightMode: false,
        onPreviousChapter: null,
        onNextChapter: null,
        onSeek: seeks.add,
        onEntry: (_) {},
        drawerTitle: '',
        drawerChild: null,
        onCloseDrawer: () {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('进度轨道到上方分隔线和下方入口图标的可见留白相等', (tester) async {
    await _open(tester, []);
    final entry = find.byKey(const ValueKey('menu-entry-toc'));
    final icon = tester.getRect(
      find.descendant(of: entry, matching: find.byType(AppIcon)),
    );
    final track = tester.getCenter(_slider).dy;
    final dividerBottom = tester
        .getRect(find.byKey(const ValueKey('menu-progress-divider')))
        .bottom;
    expect(track - dividerBottom, closeTo(icon.top - track, .01));
    expect(tester.getSize(entry).height, 48);
  });

  testWidgets('轨道上下留有触控区域，轻点松手后只跳转一次', (tester) async {
    final seeks = <double>[];
    await _open(tester, seeks);
    final bounds = tester.getRect(_slider);
    expect(bounds.height, greaterThanOrEqualTo(44));
    final gesture = await tester.startGesture(
      bounds.center + const Offset(0, 15),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(seeks, isEmpty, reason: '按住时只能预览，不能启动加载层');
    await gesture.up();
    await tester.pumpAndSettle();
    expect(seeks, hasLength(1));
    expect(seeks.single, closeTo(.5, .01));
  });

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('$kind 按住后连续拖动预览，松手提交最终进度并限制在首尾', (tester) async {
      final seeks = <double>[];
      await _open(tester, seeks);
      final bounds = tester.getRect(_slider);
      for (final (target, expected) in [
        (bounds.centerRight + const Offset(40, 0), 1.0),
        (bounds.centerLeft - const Offset(40, 0), 0.0),
      ]) {
        final gesture = await tester.startGesture(bounds.center, kind: kind);
        await tester.pump(const Duration(milliseconds: 250));
        expect(seeks, isEmpty, reason: '慢拖之前的按住不得提前跳转');
        await gesture.moveTo(Offset(target.dx, bounds.center.dy));
        await tester.pump();
        expect(seeks, isEmpty, reason: '拖动过程中不反复加载正文');
        final control = tester.widget<Slider>(find.byType(Slider));
        expect(control.value, expected);
        expect(control.label, '${(expected * 100).toStringAsFixed(1)}%');
        await gesture.up();
        await tester.pumpAndSettle();
        expect(seeks, [expected]);
        seeks.clear();
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('进度滑杆可聚焦并支持键盘与无障碍增减', (tester) async {
    final semantics = tester.ensureSemantics();
    final seeks = <double>[];
    await _open(tester, seeks);
    final node = tester.getSemantics(_slider);
    expect(node.label, contains('阅读进度'));
    expect(node.getSemanticsData().value, '20.0%');
    expect(node.hint, '当前第一章 · 2/10 页');
    final owner = node.owner!;
    owner.performAction(node.id, SemanticsAction.focus);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(seeks, [closeTo(.25, .001)]);
    seeks.clear();
    owner.performAction(node.id, SemanticsAction.decrease);
    await tester.pumpAndSettle();
    expect(seeks, [closeTo(.15, .001)]);
    semantics.dispose();
  });
}
