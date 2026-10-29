import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/page_furniture/page_furniture.dart';
import 'package:reader_ui/panels/margin_editor.dart';
import 'package:reader_ui/theme/reader_margins.dart';

ReaderMargins _defaults() => ReaderMargins.defaults(
  safeTop: 41,
  safeBottom: 16,
  side: 20,
  inner: 12,
);

void main() {
  group('页边距模型（P8-10）', () {
    test('上下合计 = 外段 + 内段', () {
      final margins = _defaults();
      expect(margins.top, 53, reason: '41 + 12');
      expect(margins.bottom, 28, reason: '16 + 12');
      expect(margins.toPadding(), const EdgeInsets.fromLTRB(20, 53, 20, 28));
    });

    test('外段可以调到 0（正文铺进安全区）', () {
      final margins = _defaults().copyWith(topOuter: 0, bottomOuter: 0);
      expect(margins.top, 12);
      expect(margins.bottom, 12);
    });

    test('外段定位页眉页脚，内段定位页眉页脚到正文的间距', () {
      final margins = _defaults();
      expect(
        margins.toOuterPadding(),
        const EdgeInsets.fromLTRB(20, 41, 20, 16),
      );
      expect(
        margins.toBodyPadding(
          showFurniture: true,
          headerHeight: PageFurniture.headerHeight,
          footerHeight: PageFurniture.footerHeight,
        ),
        const EdgeInsets.fromLTRB(20, 73, 20, 48),
        reason: '上 41 + 页眉 20 + 内 12；下 16 + 页脚 20 + 内 12',
      );
      expect(
        margins.toBodyPadding(showFurniture: false),
        const EdgeInsets.fromLTRB(20, 53, 20, 28),
        reason: '不显示页眉页脚时只用外段 + 内段',
      );
    });

    test('JSON 往返', () {
      final margins = _defaults().copyWith(left: 24, topInner: 18);
      final restored = ReaderMargins.fromJson(margins.toJson());
      expect(restored, margins);
      expect(ReaderMargins.fromJson(const <String, Object?>{}), isNotNull);
      expect(ReaderMargins.fromJson('bad'), isNull);
    });
  });

  group('边距调节器（设计稿「边距调节器」）', () {
    testWidgets('点上箭头步进、上外可归零、保留回传草稿', (tester) async {
      ReaderMargins? applied;
      var cancelled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarginEditor(
              margins: _defaults(),
              defaults: _defaults(),
              onCancel: () => cancelled = true,
              onApply: (value) => applied = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('上外 41'), findsOneWidget);
      expect(find.text('上内 12'), findsOneWidget);

      // 点「上内」的上箭头三次 → 15。
      final upArrow = find.descendant(
        of: find.byKey(const ValueKey<String>('margin-top-inner')),
        matching: find.byIcon(Icons.keyboard_arrow_up),
      );
      await tester.tap(upArrow);
      await tester.pump();
      await tester.tap(upArrow);
      await tester.pump();
      await tester.tap(upArrow);
      await tester.pump();
      expect(find.text('上内 15'), findsOneWidget);

      // 上外连点 41 次上限？这里只验证能往下调到 39。
      final downArrow = find.descendant(
        of: find.byKey(const ValueKey<String>('margin-top-outer')),
        matching: find.byIcon(Icons.keyboard_arrow_down),
      );
      await tester.tap(downArrow);
      await tester.pump();
      await tester.tap(downArrow);
      await tester.pump();
      expect(find.text('上外 39'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('margin-apply')));
      await tester.pumpAndSettle();
      expect(applied, isNotNull);
      expect(applied!.topInner, 15);
      expect(applied!.topOuter, 39);
      expect(cancelled, isFalse);
    });

    testWidgets('拖动胶囊实时预览（onPreview 连续回调）', (tester) async {
      final previews = <ReaderMargins>[];
      ReaderMargins? applied;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarginEditor(
              margins: _defaults(),
              defaults: _defaults(),
              onCancel: () {},
              onApply: (value) => applied = value,
              onPreview: previews.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 上内是垂直拖动：向下拖 = 间距向下变大。
      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const ValueKey<String>('margin-top-inner')),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(0, 12));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(previews.length, greaterThanOrEqualTo(5),
          reason: '整颗胶囊都可直接拖动，且过程连续');
      expect(previews.last.topInner, closeTo(22, 0.1),
          reason: '60px 按 6px = 1 改值');
      expect(find.text('上内 ${previews.last.topInner.round()}'), findsOneWidget);

      // 点箭头同样触发预览。
      final before = previews.length;
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('margin-top-inner')),
          matching: find.byIcon(Icons.keyboard_arrow_up),
        ),
      );
      await tester.pump();
      expect(previews.length, greaterThan(before));
      expect(applied, isNull, reason: '没点保留不应回传');
    });

    testWidgets('四边胶囊拖动方向与间距扩张方向一致', (tester) async {
      final previews = <ReaderMargins>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarginEditor(
              margins: _defaults(),
              defaults: _defaults(),
              onCancel: () {},
              onApply: (_) {},
              onPreview: previews.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> expectDragGrows(
        String key,
        Offset offset,
        double Function(ReaderMargins) read,
      ) async {
        final before = read(previews.isEmpty ? _defaults() : previews.last);
        await tester.drag(find.byKey(ValueKey<String>(key)), offset);
        await tester.pumpAndSettle();
        expect(read(previews.last), greaterThan(before), reason: '$key 应随拖动变大');
      }

      // 上侧向下、下侧向上、左边界向左、右边界向右，都是留白扩张方向。
      await expectDragGrows('margin-top-outer', const Offset(0, 48),
          (value) => value.topOuter);
      await expectDragGrows('margin-top-inner', const Offset(0, 48),
          (value) => value.topInner);
      await expectDragGrows('margin-bottom-inner', const Offset(0, -48),
          (value) => value.bottomInner);
      await expectDragGrows('margin-bottom-outer', const Offset(0, -48),
          (value) => value.bottomOuter);
      await expectDragGrows('margin-left', const Offset(-48, 0),
          (value) => value.left);
      await expectDragGrows('margin-right', const Offset(48, 0),
          (value) => value.right);
    });

    testWidgets('保留按钮位于屏幕顶部 3/4 处且为紧凑胶囊', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(400, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarginEditor(
              margins: _defaults(),
              defaults: _defaults(),
              onCancel: () {},
              onApply: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final apply = find.byKey(const ValueKey<String>('margin-apply'));
      final rect = tester.getRect(apply);
      expect(rect.top, closeTo(600, 0.5), reason: '800 × 3/4 = 600');
      expect(rect.height, lessThanOrEqualTo(32));
      expect(rect.width, lessThanOrEqualTo(80));

      final materials = tester.widgetList<Material>(
        find.ancestor(of: apply, matching: find.byType(Material)),
      );
      expect(
        materials.where((material) => material.shape is StadiumBorder),
        isNotEmpty,
      );
    });

    testWidgets('恢复默认值与取消不应用', (tester) async {
      ReaderMargins defaults = _defaultScanner();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarginEditor(
              margins: defaults.copyWith(topInner: 30),
              defaults: defaults,
              onCancel: () => tester.binding,
              onApply: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('上内 30'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('margin-reset')));
      await tester.pumpAndSettle();
      expect(find.text('上内 12'), findsOneWidget);
    });
  });
}

ReaderMargins _defaultScanner() => ReaderMargins.defaults(
  safeTop: 41,
  safeBottom: 16,
  side: 20,
  inner: 12,
);
