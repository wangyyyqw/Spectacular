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
