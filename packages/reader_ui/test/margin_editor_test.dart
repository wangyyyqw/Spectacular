import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/page_furniture/page_furniture.dart';
import 'package:reader_ui/panels/margin_editor.dart';
import 'package:reader_ui/theme/reader_margins.dart';

ReaderMargins _defaults() =>
    ReaderMargins.defaults(safeTop: 41, safeBottom: 16, side: 20, inner: 12);

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
    testWidgets('小数边距未修改确认保留原始值，显示与输入不会舍入为整数', (tester) async {
      final margins = _defaults().copyWith(left: 8.799999999999997);
      final previews = <ReaderMargins>[];
      final applied = <ReaderMargins>[];
      await _showEditor(
        tester,
        margins: margins,
        onPreview: previews.add,
        onApply: applied.add,
      );
      expect(find.text('左 8.8'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('margin-value-左')));
      await tester.pumpAndSettle();
      final input = tester.widget<TextField>(
        find.byKey(const ValueKey('margin-value-input')),
      );
      expect(input.controller!.text, '8.8');
      await tester.tap(find.byKey(const ValueKey('margin-value-confirm')));
      await tester.pumpAndSettle();
      expect(previews, isEmpty, reason: '未编辑数值不得产生重排或改变实际精度');
      await tester.tap(find.byKey(const ValueKey('margin-apply')));
      await tester.pumpAndSettle();
      expect(applied.single, margins);
    });

    testWidgets('数值精调校验范围并实时预览，取消编辑器不保存', (tester) async {
      final previews = <ReaderMargins>[];
      await _showEditor(tester, onPreview: previews.add);
      await tester.tap(find.byKey(const ValueKey('margin-value-左')));
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('margin-value-input'));
      await tester.enterText(input, '49');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('margin-value-confirm')),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(input, '12.5');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('margin-value-confirm')));
      await tester.pumpAndSettle();
      expect(previews.single.left, 12.5);
      expect(previews.single.right, 20);
      expect(find.text('左 12.5'), findsOneWidget);
    });

    testWidgets('点箭头步进并移动按钮、保存回传草稿', (tester) async {
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
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.glyph == AppGlyph.chevronUp,
        ),
      );
      final initialTop = tester.getTopLeft(upArrow).dy;
      await tester.tap(upArrow);
      await tester.pump();
      await tester.tap(upArrow);
      await tester.pump();
      await tester.tap(upArrow);
      await tester.pump();
      expect(find.text('上内 15'), findsOneWidget);
      expect(tester.getTopLeft(upArrow).dy, initialTop + 3);

      // 上外减小后，上内按钮也随正文边界上移。
      final downArrow = find.descendant(
        of: find.byKey(const ValueKey<String>('margin-top-outer')),
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.glyph == AppGlyph.chevronDown,
        ),
      );
      await tester.tap(downArrow);
      await tester.pump();
      await tester.tap(downArrow);
      await tester.pump();
      expect(find.text('上外 39'), findsOneWidget);
      expect(tester.getTopLeft(upArrow).dy, initialTop + 1);

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
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      final beforeMoves = previews.length;
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(0, 3));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        previews.length - beforeMoves,
        greaterThanOrEqualTo(5),
        reason: '整颗胶囊都可直接拖动，且过程连续',
      );
      expect(
        previews.last.topInner,
        closeTo(12 + 35, 0.1),
        reason: '先移动 20px 越过手势阈值，再连续移动 15px，按 1:1 调节',
      );
      expect(find.text('上内 ${previews.last.topInner.round()}'), findsOneWidget);

      // 点箭头同样触发预览。
      final before = previews.length;
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('margin-top-inner')),
          matching: find.byWidgetPredicate(
            (widget) => widget is AppIcon && widget.glyph == AppGlyph.chevronUp,
          ),
        ),
      );
      await tester.pump();
      expect(previews.length, greaterThan(before));
      expect(applied, isNull, reason: '没点保存不应回传');
    });

    testWidgets('上层随预览重建时拖动不会中断', (tester) async {
      final previews = <ReaderMargins>[];
      var parentMargins = _defaults();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => MarginEditor(
                margins: parentMargins,
                defaults: _defaults(),
                onCancel: () {},
                onApply: (_) {},
                onPreview: (value) {
                  previews.add(value);
                  setState(() => parentMargins = value);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const ValueKey<String>('margin-top-inner')),
        ),
      );
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      final beforeMoves = previews.length;
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(0, 3));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        previews.length - beforeMoves,
        greaterThanOrEqualTo(5),
        reason: '父级实时预览重建后，同一次拖动仍应持续回调',
      );
      expect(previews.last.topInner, closeTo(12 + 35, 0.1));
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
        final pill = find.byKey(ValueKey<String>(key));
        final position = tester.getCenter(pill);
        await tester.drag(pill, offset);
        await tester.pumpAndSettle();
        final change = read(previews.last) - before;
        expect(change, greaterThan(0), reason: '$key 应随拖动变大');
        expect(
          tester.getCenter(pill) - position,
          offset / offset.distance * change,
          reason: '$key 的位置变化必须等于边距变化，方向与手指一致',
        );
      }

      // 每条正文边界都沿着手指移动：上侧向下、下侧向上，左边界向右、
      // 右边界向左时边距变大。
      await expectDragGrows(
        'margin-top-outer',
        const Offset(0, 48),
        (value) => value.topOuter,
      );
      await expectDragGrows(
        'margin-top-inner',
        const Offset(0, 48),
        (value) => value.topInner,
      );
      await expectDragGrows(
        'margin-bottom-inner',
        const Offset(0, -48),
        (value) => value.bottomInner,
      );
      await expectDragGrows(
        'margin-bottom-outer',
        const Offset(0, -48),
        (value) => value.bottomOuter,
      );
      await expectDragGrows(
        'margin-left',
        const Offset(48, 0),
        (value) => value.left,
      );
      await expectDragGrows(
        'margin-right',
        const Offset(-48, 0),
        (value) => value.right,
      );
    });

    final controls = <(String, Offset, double, double Function(ReaderMargins))>[
      ('top-outer', const Offset(0, 1), 96, (value) => value.topOuter),
      ('top-inner', const Offset(0, 1), 60, (value) => value.topInner),
      ('bottom-inner', const Offset(0, -1), 60, (value) => value.bottomInner),
      ('bottom-outer', const Offset(0, -1), 96, (value) => value.bottomOuter),
      ('left', const Offset(1, 0), 48, (value) => value.left),
      ('right', const Offset(-1, 0), 48, (value) => value.right),
    ];
    for (final (key, direction, max, read) in controls) {
      testWidgets('$key 从零小幅拖动即可起步，随后每移动 1 数值与按钮都增加 1', (tester) async {
        final previews = <ReaderMargins>[];
        final zero = _defaults().copyWith(
          topOuter: 0,
          topInner: 0,
          bottomInner: 0,
          bottomOuter: 0,
          left: 0,
          right: 0,
        );
        await _showEditor(tester, margins: zero, onPreview: previews.add);
        final pill = find.byKey(ValueKey<String>('margin-$key'));
        final origin = tester.getCenter(pill);
        final gesture = await tester.startGesture(origin);
        for (var value = 1; value <= 7; value++) {
          await gesture.moveBy(direction);
          await tester.pump();
          if (value <= 2) {
            expect(previews, isEmpty, reason: '保留 2px 的轻微触摸容差');
          } else {
            expect(read(previews.last), value);
            expect(
              tester.getCenter(pill) - origin,
              direction * value.toDouble(),
            );
          }
        }
        await gesture.up();
        await tester.pumpAndSettle();
      });

      testWidgets('$key 达到上下限不越界，反向移动 3 时数值与按钮同步移动 3', (tester) async {
        final previews = <ReaderMargins>[];
        await _showEditor(tester, onPreview: previews.add);
        final pill = find.byKey(ValueKey<String>('margin-$key'));
        final origin = tester.getCenter(pill);
        final initial = read(_defaults());
        final gesture = await tester.startGesture(origin);
        await gesture.moveBy(direction * 200);
        await tester.pump();
        expect(read(previews.last), max);
        expect(tester.getCenter(pill) - origin, direction * (max - initial));
        final calls = previews.length;
        await gesture.moveBy(direction * 20);
        await tester.pump();
        expect(previews.length, calls, reason: '上限处不重复触发无变化的预览');
        await gesture.moveBy(direction * -3);
        await tester.pump();
        expect(read(previews.last), max - 3);
        expect(
          tester.getCenter(pill) - origin,
          direction * (max - 3 - initial),
        );
        await gesture.moveBy(direction * -200);
        await tester.pump();
        expect(read(previews.last), 0);
        expect(tester.getCenter(pill) - origin, direction * -initial);
        await gesture.moveBy(direction * 3);
        await tester.pump();
        expect(read(previews.last), 3);
        expect(tester.getCenter(pill) - origin, direction * (3 - initial));
        await gesture.up();
        await tester.pumpAndSettle();
      });
    }

    testWidgets('同一帧内多次移动累计，不因未重建而丢失增量', (tester) async {
      final previews = <ReaderMargins>[];
      await _showEditor(tester, onPreview: previews.add);
      final pill = find.byKey(const ValueKey<String>('margin-top-inner'));
      final origin = tester.getCenter(pill);
      final gesture = await tester.startGesture(origin);
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 3));
      await gesture.moveBy(const Offset(0, 3));
      await tester.pump();
      expect(previews.last.topInner, 38);
      expect(tester.getCenter(pill) - origin, const Offset(0, 26));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('从箭头拖动不误触步进，取消手势后仍可点击新位置', (tester) async {
      final previews = <ReaderMargins>[];
      await _showEditor(tester, onPreview: previews.add);
      final arrow = find.descendant(
        of: find.byKey(const ValueKey<String>('margin-top-inner')),
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.glyph == AppGlyph.chevronUp,
        ),
      );
      await tester.drag(arrow, const Offset(0, 24));
      await tester.pumpAndSettle();
      expect(previews.last.topInner, 36, reason: '松手不能额外增加 1');
      final gesture = await tester.startGesture(tester.getCenter(arrow));
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(previews.last.topInner, 16);
      await tester.tap(arrow);
      await tester.pumpAndSettle();
      expect(previews.last.topInner, 17);
      final tap = await tester.startGesture(tester.getCenter(arrow));
      await tap.moveBy(const Offset(0, 1));
      await tap.up();
      await tester.pumpAndSettle();
      expect(previews.last.topInner, 18, reason: '轻微抖动仍按点击步进一次');
    });

    testWidgets('页眉与正文间距非 0 时在间隙绘制阴影', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(400, 800));

      Future<List<Rect>> shadowRects({
        required double topInner,
        double bottomInner = 12,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarginEditor(
                key: ValueKey<double>(topInner * 100 + bottomInner),
                margins: _defaults().copyWith(
                  topInner: topInner,
                  bottomInner: bottomInner,
                ),
                defaults: _defaults(),
                onCancel: () {},
                onApply: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final painter = tester
            .widget<CustomPaint>(
              find.byKey(const ValueKey<String>('margin-zone-painter')),
            )
            .painter!;
        final canvas = _RecordingCanvas();
        painter.paint(canvas, const Size(400, 800));
        return canvas.shadowRects;
      }

      final defaults = _defaults();
      final withGap = await shadowRects(topInner: 12);
      final withoutGap = await shadowRects(topInner: 0, bottomInner: 0);
      expect(
        withGap.any(
          (rect) =>
              rect.top == defaults.topOuter + PageFurniture.headerHeight &&
              rect.bottom ==
                  defaults.topOuter +
                      PageFurniture.headerHeight +
                      defaults.topInner,
        ),
        isTrue,
        reason: '页眉底边到正文顶边之间应画阴影',
      );
      expect(
        withGap.any(
          (rect) =>
              rect.top ==
                  800 -
                      defaults.bottomOuter -
                      PageFurniture.footerHeight -
                      defaults.bottomInner &&
              rect.bottom ==
                  800 - defaults.bottomOuter - PageFurniture.footerHeight,
        ),
        isTrue,
        reason: '正文底边到页脚顶边之间应画阴影',
      );
      expect(withoutGap, isEmpty, reason: '间隙为 0 时不画内段阴影');
    });

    testWidgets('取消、恢复默认、保存并排位于底部，不遮挡下边距调节', (tester) async {
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
      final cancel = tester.getRect(
        find.byKey(const ValueKey<String>('margin-cancel')),
      );
      final reset = tester.getRect(
        find.byKey(const ValueKey<String>('margin-reset')),
      );
      expect(cancel.top, rect.top);
      expect(reset.top, rect.top);
      expect(cancel.right, lessThan(reset.left));
      expect(reset.right, lessThan(rect.left));
      expect(rect.bottom, closeTo(792, 0.5), reason: '操作栏距底部 8px');
      expect(rect.height, lessThanOrEqualTo(36));
      expect(rect.width, lessThanOrEqualTo(80));
      expect(find.text('保存'), findsOneWidget);
      for (final key in ['margin-bottom-inner', 'margin-bottom-outer']) {
        expect(
          tester.getRect(find.byKey(ValueKey<String>(key))).bottom,
          lessThan(rect.top),
        );
      }

      final material = tester.widget<Material>(
        find.descendant(of: apply, matching: find.byType(Material)),
      );
      final shape = material.shape;
      expect(shape, isA<RoundedRectangleBorder>());
      expect(
        (shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(4),
      );
    });

    for (final size in [const Size(320, 640), const Size(800, 400)]) {
      testWidgets('窄屏或横屏 $size 安全区内显示操作栏，放大文字无溢出', (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: MediaQuery(
              data: const MediaQueryData(
                padding: EdgeInsets.fromLTRB(24, 24, 24, 24),
                textScaler: TextScaler.linear(1.5),
              ),
              child: Scaffold(
                body: MarginEditor(
                  margins: _defaults().copyWith(left: 48, right: 48),
                  defaults: _defaults(),
                  onCancel: () {},
                  onApply: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final left = tester.getRect(
          find.byKey(const ValueKey<String>('margin-left')),
        );
        final right = tester.getRect(
          find.byKey(const ValueKey<String>('margin-right')),
        );
        expect(left.right, lessThanOrEqualTo(right.left));
        for (final key in ['margin-cancel', 'margin-reset', 'margin-apply']) {
          final rect = tester.getRect(find.byKey(ValueKey<String>(key)));
          expect(rect.left, greaterThanOrEqualTo(24));
          expect(rect.right, lessThanOrEqualTo(size.width - 24));
          expect(rect.bottom, lessThanOrEqualTo(size.height - 24));
          for (final control in [
            'margin-bottom-inner',
            'margin-bottom-outer',
          ]) {
            expect(
              tester.getRect(find.byKey(ValueKey<String>(control))).bottom,
              lessThan(rect.top),
            );
          }
        }
      });
    }

    testWidgets('恢复默认同步数值、位置和预览，取消不保存', (tester) async {
      final defaults = _defaults();
      final previews = <ReaderMargins>[];
      final applied = <ReaderMargins>[];
      var cancelled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarginEditor(
              margins: defaults.copyWith(topInner: 30),
              defaults: defaults,
              onCancel: () => cancelled = true,
              onApply: applied.add,
              onPreview: previews.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('上内 30'), findsOneWidget);
      final pill = find.byKey(const ValueKey<String>('margin-top-inner'));
      final top = tester.getTopLeft(pill).dy;
      await tester.tap(find.byKey(const ValueKey<String>('margin-reset')));
      await tester.pumpAndSettle();
      expect(find.text('上内 12'), findsOneWidget);
      expect(tester.getTopLeft(pill).dy, top - 18);
      expect(previews, [defaults]);
      await tester.tap(find.byKey(const ValueKey<String>('margin-cancel')));
      await tester.pumpAndSettle();
      expect(cancelled, isTrue);
      expect(applied, isEmpty);
    });
  });
}

Future<void> _showEditor(
  WidgetTester tester, {
  required ValueChanged<ReaderMargins> onPreview,
  ReaderMargins? margins,
  ValueChanged<ReaderMargins>? onApply,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        // 模拟阅读页上点击与拖动竞争，防止单一识别器提前获胜掩盖阈值问题。
        body: GestureDetector(
          onTap: () {},
          child: MarginEditor(
            margins: margins ?? _defaults(),
            defaults: _defaults(),
            onCancel: () {},
            onApply: onApply ?? (_) {},
            onPreview: onPreview,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 只记录带渐变的矩形，用来确认页眉/正文和正文/页脚间隙的阴影。
class _RecordingCanvas implements ui.Canvas {
  final List<Rect> shadowRects = <Rect>[];

  @override
  void drawRect(Rect rect, Paint paint) {
    if (paint.shader != null) {
      shadowRects.add(rect);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
