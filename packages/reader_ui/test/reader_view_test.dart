import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/tap_zones.dart';

void main() {
  group('ReaderGestureInterpreter', () {
    const config = ReaderGestureConfig();
    const interpreter = ReaderGestureInterpreter(config);

    test('左右中三区覆盖整个宽度', () {
      expect(
        interpreter.tapAt(const Offset(30, 10), width: 300),
        ReaderGesture.tapLeft,
      );
      expect(
        interpreter.tapAt(const Offset(150, 10), width: 300),
        ReaderGesture.tapCenter,
      );
      expect(
        interpreter.tapAt(const Offset(270, 10), width: 300),
        ReaderGesture.tapRight,
      );
      expect(interpreter.tapAt(Offset.zero, width: 300), ReaderGesture.tapLeft);
      expect(
        interpreter.tapAt(const Offset(299, 10), width: 300),
        ReaderGesture.tapRight,
      );
    });

    test('九宫格坐标分类', () {
      const size = Size(300, 300);
      final positions = <Offset>[
        for (var row = 0; row < 3; row++)
          for (var column = 0; column < 3; column++)
            Offset(50 + column * 100, 50 + row * 100),
      ];
      expect(<ReaderTapZone>[
        for (final position in positions)
          interpreter.tapZoneAt(position, size: size),
      ], ReaderTapZone.values);
    });

    test('点击意图与左利手/竖排反转', () {
      expect(
        interpreter.tapIntent(ReaderGesture.tapLeft),
        PageTurnIntent.previous,
      );
      expect(
        interpreter.tapIntent(ReaderGesture.tapRight),
        PageTurnIntent.next,
      );
      const leftHand = ReaderGestureInterpreter(
        ReaderGestureConfig(clickLeftNextPage: true),
      );
      expect(leftHand.tapIntent(ReaderGesture.tapLeft), PageTurnIntent.next);
      expect(
        leftHand.tapIntent(ReaderGesture.tapRight),
        PageTurnIntent.previous,
      );
      const vertical = ReaderGestureInterpreter(
        ReaderGestureConfig(verticalWriting: true),
      );
      expect(vertical.tapIntent(ReaderGesture.tapLeft), PageTurnIntent.next);
      expect(
        vertical.tapIntent(ReaderGesture.tapRight),
        PageTurnIntent.previous,
      );
    });

    test('上下左右四类滑动方向', () {
      expect(interpreter.swipeDirection(-10, 0), ReaderGesture.swipeLeft);
      expect(interpreter.swipeDirection(10, 0), ReaderGesture.swipeRight);
      expect(interpreter.swipeDirection(0, -10), ReaderGesture.swipeUp);
      expect(interpreter.swipeDirection(0, 10), ReaderGesture.swipeDown);
      expect(interpreter.swipeDirection(0, 0), ReaderGesture.none);
    });

    test('距离/速度阈值', () {
      expect(interpreter.shouldTurnPage(dx: -90, dy: 0, width: 300), isTrue);
      expect(interpreter.shouldTurnPage(dx: -89, dy: 0, width: 300), isFalse);
      expect(
        interpreter.shouldTurnPage(dx: -20, dy: 0, width: 300, velocityX: 800),
        isTrue,
      );
      expect(interpreter.shouldTurnPage(dx: 0, dy: -100, width: 300), isFalse);
    });
  });

  group('ReaderView', () {
    Future<void> pumpView(
      WidgetTester tester, {
      required int pageIndex,
      required ValueNotifier<int> previous,
      required ValueNotifier<int> next,
      required ValueNotifier<int> toolbar,
      ReaderTapZones tapZones = ReaderTapZones.defaults,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              height: 200,
              child: ReaderView(
                config: ReaderGestureConfig(tapZones: tapZones),
                pageIndex: pageIndex,
                pageCount: 3,
                onPrevious: () => previous.value += 1,
                onNext: () => next.value += 1,
                onToggleToolbar: () => toolbar.value += 1,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('点击左/中/右区域触发对应动作', (tester) async {
      final previous = ValueNotifier<int>(0);
      final next = ValueNotifier<int>(0);
      final toolbar = ValueNotifier<int>(0);
      await pumpView(
        tester,
        pageIndex: 1,
        previous: previous,
        next: next,
        toolbar: toolbar,
      );
      final origin = tester.getTopLeft(find.byType(ReaderView));
      await tester.tapAt(origin + const Offset(30, 100));
      await tester.pump();
      expect(previous.value, 1);
      await tester.tapAt(origin + const Offset(150, 100));
      await tester.pump();
      expect(toolbar.value, 1);
      await tester.tapAt(origin + const Offset(270, 100));
      await tester.pump();
      expect(next.value, 1);
    });

    testWidgets('点击屏幕最左和最右边缘仍可翻页', (tester) async {
      final previous = ValueNotifier<int>(0);
      final next = ValueNotifier<int>(0);
      final toolbar = ValueNotifier<int>(0);
      await pumpView(
        tester,
        pageIndex: 1,
        previous: previous,
        next: next,
        toolbar: toolbar,
      );
      final origin = tester.getTopLeft(find.byType(ReaderView));
      await tester.tapAt(origin + const Offset(1, 100));
      await tester.pump();
      expect(previous.value, 1);
      await tester.tapAt(origin + const Offset(299, 100));
      await tester.pump();
      expect(next.value, 1);
    });

    testWidgets('九宫格动作可配置且更新后立即生效', (tester) async {
      final previous = ValueNotifier<int>(0);
      final next = ValueNotifier<int>(0);
      final toolbar = ValueNotifier<int>(0);
      await pumpView(
        tester,
        pageIndex: 1,
        previous: previous,
        next: next,
        toolbar: toolbar,
      );
      final origin = tester.getTopLeft(find.byType(ReaderView));
      await tester.tapAt(origin + const Offset(30, 100));
      await tester.pump();
      expect(previous.value, 1);

      final changed = ReaderTapZones.defaults
          .withAction(ReaderTapZone.middleLeft, ReaderTapAction.nextPage)
          .withAction(ReaderTapZone.middleRight, ReaderTapAction.none);
      await pumpView(
        tester,
        pageIndex: 1,
        previous: previous,
        next: next,
        toolbar: toolbar,
        tapZones: changed,
      );
      await tester.tapAt(origin + const Offset(30, 100));
      await tester.pump();
      expect(next.value, 1);
      await tester.tapAt(origin + const Offset(270, 100));
      await tester.pump();
      expect(next.value, 1);
      expect(toolbar.value, 0);
    });

    testWidgets('水平滑动翻页，竖向滑动不翻页', (tester) async {
      final previous = ValueNotifier<int>(0);
      final next = ValueNotifier<int>(0);
      final toolbar = ValueNotifier<int>(0);
      await pumpView(
        tester,
        pageIndex: 1,
        previous: previous,
        next: next,
        toolbar: toolbar,
      );
      await tester.fling(find.byType(ReaderView), const Offset(-160, 0), 1000);
      await tester.pumpAndSettle();
      expect(next.value, 1);

      await tester.fling(find.byType(ReaderView), const Offset(160, 0), 1000);
      await tester.pumpAndSettle();
      expect(previous.value, 1);

      await tester.fling(find.byType(ReaderView), const Offset(0, -120), 1000);
      await tester.pumpAndSettle();
      expect(next.value, 1);
      expect(previous.value, 1);
    });

    testWidgets('首尾边界不回调、不抛异常', (tester) async {
      final previous = ValueNotifier<int>(0);
      final next = ValueNotifier<int>(0);
      final toolbar = ValueNotifier<int>(0);
      await pumpView(
        tester,
        pageIndex: 0,
        previous: previous,
        next: next,
        toolbar: toolbar,
      );
      await tester.fling(find.byType(ReaderView), const Offset(160, 0), 1000);
      await tester.pumpAndSettle();
      expect(previous.value, 0);
      expect(tester.takeException(), isNull);

      await pumpView(
        tester,
        pageIndex: 2,
        previous: previous,
        next: next,
        toolbar: toolbar,
      );
      await tester.fling(find.byType(ReaderView), const Offset(-160, 0), 1000);
      await tester.pumpAndSettle();
      expect(next.value, 0);
      expect(tester.takeException(), isNull);
    });
  });
}
