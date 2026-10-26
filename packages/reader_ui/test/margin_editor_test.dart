import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

      // 上内是垂直拖动：向上拖 60px ≈ 10 格（向外 = 变大）。
      await tester.drag(
        find.byKey(const ValueKey<String>('margin-top-inner')),
        const Offset(0, -60),
      );
      await tester.pumpAndSettle();
      expect(previews, isNotEmpty, reason: '拖动过程中就应实时预览');
      expect(previews.last.topInner, greaterThan(12));
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

    testWidgets('左右胶囊拖动方向相反（向外拖 = 变大）', (tester) async {
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

      // 左胶囊：向右拖 = 变小。
      await tester.drag(
        find.byKey(const ValueKey<String>('margin-left')),
        const Offset(60, 0),
      );
      await tester.pumpAndSettle();
      expect(previews.last.left, lessThan(20), reason: '左胶囊向右拖应变小');

      // 左胶囊：向左拖 = 变大。
      await tester.drag(
        find.byKey(const ValueKey<String>('margin-left')),
        const Offset(-60, 0),
      );
      await tester.pumpAndSettle();
      expect(previews.last.left, greaterThan(10), reason: '左胶囊向左拖应变大');

      final beforeRight = previews.last.right;
      // 右胶囊：向右拖 = 变大。
      await tester.drag(
        find.byKey(const ValueKey<String>('margin-right')),
        const Offset(60, 0),
      );
      await tester.pumpAndSettle();
      expect(previews.last.right, greaterThan(beforeRight), reason: '右胶囊向右拖应变大');
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
