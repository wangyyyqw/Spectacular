import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/reader_view.dart';
import 'package:reader_ui/tap_zones.dart';

Future<void> _scrollWheel(WidgetTester tester, Offset delta) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      kind: PointerDeviceKind.mouse,
      position: tester.getCenter(find.byType(ReaderView)),
      scrollDelta: delta,
    ),
  );
  await tester.pump();
}

Future<void> _pumpGestureView(
  WidgetTester tester,
  Widget view, {
  double? touchSlop,
  Offset origin = Offset.zero,
}) async {
  Widget child = Align(
    alignment: Alignment.topLeft,
    child: Padding(
      padding: EdgeInsets.only(left: origin.dx, top: origin.dy),
      child: SizedBox(width: 300, height: 200, child: view),
    ),
  );
  if (touchSlop != null) {
    child = MediaQuery(
      data: MediaQueryData(
        gestureSettings: DeviceGestureSettings(touchSlop: touchSlop),
      ),
      child: child,
    );
  }
  await tester.pumpWidget(MaterialApp(home: child));
}

Future<void> _deceleratingDrag(
  WidgetTester tester,
  Offset start,
  double distance, {
  double? finalVelocity,
  double leadDistance = 0,
}) async {
  final gesture = await tester.startGesture(start);
  final curveStart = start + Offset(distance.sign * 50, 0);
  await _primeNativeDrag(tester, gesture, curveStart, distance.sign);
  final velocity = finalVelocity ?? distance.sign * 30;
  final initialVelocity = 20 * distance - velocity;
  await gesture.moveTo(
    curveStart + Offset(leadDistance, 0),
    timeStamp: const Duration(milliseconds: 200),
  );
  await tester.pump(const Duration(milliseconds: 20));
  // 最近 100 ms 用二次减速轨迹，同时覆盖系统最小快扫距离和末端速度。
  for (var step = 1; step <= 5; step++) {
    final t = step * 0.02;
    final dx = initialVelocity * t + (velocity - initialVelocity) * t * t / 0.2;
    await gesture.moveTo(
      curveStart + Offset(leadDistance + dx, 0),
      timeStamp: Duration(milliseconds: 200 + step * 20),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await gesture.up(timeStamp: const Duration(milliseconds: 300));
  await tester.pump();
}

Future<void> _primeNativeDrag(
  WidgetTester tester,
  TestGesture gesture,
  Offset end,
  double direction,
) async {
  await _moveSamples(tester, gesture, [
    for (final offset in [-49, -30, -20, -10, 0])
      end + Offset(offset * direction, 0),
  ]);
}

Future<void> _moveSamples(
  WidgetTester tester,
  TestGesture gesture,
  List<Offset> positions, {
  int firstTime = 20,
}) async {
  for (var index = 0; index < positions.length; index++) {
    await gesture.moveTo(
      positions[index],
      timeStamp: Duration(milliseconds: firstTime + index * 20),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void _expectNativeHandoff(List<Object> events, Offset origin) {
  expect(events, [isA<DragStartDetails>(), isA<DragUpdateDetails>()]);
  final start = events[0] as DragStartDetails;
  final update = events[1] as DragUpdateDetails;
  expect(start.localPosition, const Offset(180, 90));
  expect(start.globalPosition, origin + const Offset(180, 90));
  expect(start.sourceTimeStamp, const Duration(milliseconds: 40));
  expect(update.localPosition, const Offset(143, 92));
  expect(update.globalPosition, origin + const Offset(143, 92));
  expect(update.delta, const Offset(-37, 2));
  expect(update.primaryDelta, isNull);
  expect(update.sourceTimeStamp, start.sourceTimeStamp);
}

Future<double> _boundaryDragVelocity(
  WidgetTester tester,
  double minimumVelocity,
) async {
  final events = <String>[];
  final ends = <DragEndDetails>[];
  var updates = 0;
  await _pumpGestureView(
    tester,
    ReaderView(
      config: ReaderGestureConfig(minimumFlingVelocity: minimumVelocity),
      onDragStart: (_) => events.add('开始'),
      onDragUpdate: (_) => updates++,
      onDragEnd: (details) {
        events.add('结束');
        ends.add(details);
      },
      onDragCancel: () => events.add('取消'),
    ),
  );
  final start =
      tester.getTopLeft(find.byType(ReaderView)) + const Offset(150, 100);
  await _deceleratingDrag(tester, start, 20, finalVelocity: 20);
  expect(events, ['开始', '结束']);
  expect(updates, greaterThan(0));
  expect(ends, hasLength(1));
  expect(ends.single.velocity.pixelsPerSecond.dx, ends.single.primaryVelocity);
  return ends.single.primaryVelocity!;
}

Future<void> _twoPointerDrag(
  WidgetTester tester,
  Offset start, {
  required bool alreadyStarted,
}) async {
  final first = await tester.startGesture(start, pointer: 1);
  if (alreadyStarted) {
    await _primeNativeDrag(tester, first, start - const Offset(50, 0), -1);
  }
  final second = await tester.createGesture(pointer: 2);
  await second.down(
    start + const Offset(-20, 20),
    timeStamp: const Duration(milliseconds: 120),
  );
  await first.moveTo(
    start + const Offset(-80, 0),
    timeStamp: const Duration(milliseconds: 140),
  );
  await first.up(timeStamp: const Duration(milliseconds: 160));
  await second.up(timeStamp: const Duration(milliseconds: 160));
  await tester.pump();
}

void main() {
  for (final zones in [
    null,
    ReaderTapZones.defaults,
    ReaderTapZones.fullScreenNext,
  ]) {
    testWidgets('连续滚动忽略点击翻页，保留正文命中与菜单：${zones?.isFullScreenNext}', (
      tester,
    ) async {
      var turns = 0;
      var menus = 0;
      final taps = <Offset>[];
      await _pumpGestureView(
        tester,
        ReaderView(
          continuousScroll: true,
          config: ReaderGestureConfig(tapZones: zones),
          onPrevious: () => turns++,
          onNext: () => turns++,
          onToggleToolbar: () => menus++,
          onTapAt: (point) {
            taps.add(point);
            return false;
          },
        ),
      );
      final origin = tester.getTopLeft(find.byType(ReaderView));
      for (final point in [
        const Offset(30, 100),
        const Offset(270, 100),
        const Offset(150, 100),
      ]) {
        await tester.tapAt(origin + point);
        await tester.pumpAndSettle();
      }
      expect(turns, 0);
      expect(menus, 1);
      expect(taps, hasLength(3), reason: '正文链接和批注每次点击只命中一次');
    });
  }

  for (final minimumVelocity in <double?>[null, 20]) {
    testWidgets('连续滚动不响应横滑，斜向起手仍可上下滚动：$minimumVelocity', (tester) async {
      final scroll = ScrollController(initialScrollOffset: 300);
      addTearDown(scroll.dispose);
      final events = <Object>[];
      await _pumpGestureView(
        tester,
        ReaderView(
          continuousScroll: true,
          config: ReaderGestureConfig(minimumFlingVelocity: minimumVelocity),
          onPrevious: () => events.add('上一页'),
          onNext: () => events.add('下一页'),
          onGesture: events.add,
          onDragStart: events.add,
          onDragUpdate: events.add,
          onDragEnd: events.add,
          child: SingleChildScrollView(
            controller: scroll,
            child: const SizedBox(height: 1800),
          ),
        ),
      );
      await tester.drag(find.byType(ReaderView), const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(scroll.offset, 300);
      expect(events, isEmpty);
      final origin = tester.getTopLeft(find.byType(ReaderView));
      final drag = await tester.startGesture(origin + const Offset(260, 170));
      await _moveSamples(tester, drag, [
        for (var step = 1; step <= 5; step++)
          origin + Offset(260 - step * 25, 170 - step * 6),
        origin + const Offset(135, 80),
        origin + const Offset(135, 30),
      ]);
      expect(scroll.offset, greaterThan(300), reason: '拖动中正文跟随手指');
      await drag.up();
      await tester.pumpAndSettle();
      final forward = scroll.offset;
      await tester.drag(find.byType(ReaderView), const Offset(0, 100));
      await tester.pumpAndSettle();
      expect(scroll.offset, lessThan(forward));
      expect(events, isEmpty, reason: '滚动手势不能进入翻页动画生命周期');
    });
  }

  testWidgets('鼠标右键和中键不进入主键点击翻页路径', (tester) async {
    var turns = 0;
    var menus = 0;
    await _pumpGestureView(
      tester,
      ReaderView(
        onPrevious: () => turns++,
        onNext: () => turns++,
        onSecondaryTap: () => menus++,
      ),
    );
    final bounds = tester.getRect(find.byType(ReaderView));
    for (final buttons in [kSecondaryButton, kMiddleMouseButton]) {
      await tester.tapAt(
        bounds.centerRight - const Offset(10, 0),
        kind: PointerDeviceKind.mouse,
        buttons: buttons,
      );
      await tester.pump();
    }
    expect(turns, 0);
    expect(menus, 1);
    await tester.tapAt(
      bounds.centerRight - const Offset(10, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(turns, 1);
  });

  testWidgets('滚轮向下下一页、向上上一页，不受点击方向设置影响', (tester) async {
    final turns = <String>[];
    await _pumpGestureView(
      tester,
      ReaderView(
        config: const ReaderGestureConfig(
          verticalWriting: true,
          clickLeftNextPage: true,
        ),
        onPrevious: () => turns.add('上一页'),
        onNext: () => turns.add('下一页'),
      ),
    );
    await _scrollWheel(tester, const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 300));
    await _scrollWheel(tester, const Offset(0, -120));
    expect(turns, ['下一页', '上一页']);
  });

  testWidgets('滚轮密集事件节流，间隔后仍可继续翻页，横向滚动不翻页', (tester) async {
    var turns = 0;
    await _pumpGestureView(tester, ReaderView(onNext: () => turns++));
    await _scrollWheel(tester, const Offset(120, 0));
    expect(turns, 0);
    for (var index = 0; index < 5; index++) {
      await _scrollWheel(tester, const Offset(0, 120));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(turns, 1);
    await tester.pump(const Duration(milliseconds: 300));
    await _scrollWheel(tester, const Offset(0, 120));
    expect(turns, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('滚轮沿用首尾页边界', (tester) async {
    var turns = 0;
    for (final page in [0, 1]) {
      await _pumpGestureView(
        tester,
        ReaderView(
          pageIndex: page,
          pageCount: 2,
          onPrevious: () => turns++,
          onNext: () => turns++,
        ),
      );
      await _scrollWheel(tester, Offset(0, page == 0 ? -120 : 120));
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(turns, 0);
  });

  testWidgets('禁用滚轮翻页时不触发阅读回调', (tester) async {
    var turns = 0;
    await _pumpGestureView(
      tester,
      ReaderView(
        mouseWheelPaging: false,
        onPrevious: () => turns++,
        onNext: () => turns++,
      ),
    );
    await _scrollWheel(tester, const Offset(0, 120));
    await _scrollWheel(tester, const Offset(0, -120));
    expect(turns, 0);
  });

  testWidgets('滚轮实时读取忙碌状态，恢复后无需重建即可翻页', (tester) async {
    var busy = true;
    var turns = 0;
    await _pumpGestureView(
      tester,
      ReaderView(canMouseWheelPage: () => !busy, onNext: () => turns++),
    );
    await _scrollWheel(tester, const Offset(0, 120));
    expect(turns, 0);
    busy = false;
    await _scrollWheel(tester, const Offset(0, 120));
    expect(turns, 1);
    await tester.pump(const Duration(milliseconds: 300));
  });

  for (final continuous in [false, true]) {
    testWidgets('滚轮优先交给子滚动容器，连续滚动=$continuous', (tester) async {
      var turns = 0;
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pumpGestureView(
        tester,
        ReaderView(
          continuousScroll: continuous,
          onNext: () => turns++,
          child: SingleChildScrollView(
            controller: controller,
            child: const SizedBox(height: 900),
          ),
        ),
      );
      await _scrollWheel(tester, const Offset(0, 120));
      expect(controller.offset, 120);
      expect(turns, 0);
    });
  }

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
      bool Function(Offset position)? onTapAt,
      ValueChanged<DragStartDetails>? onDragStart,
      ValueChanged<Offset>? onDoubleTapAt,
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
                onTapAt: onTapAt,
                onDragStart: onDragStart,
                onDoubleTapAt: onDoubleTapAt,
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

    testWidgets('快速双击翻页区域按两次点击逐页翻页', (tester) async {
      final previous = ValueNotifier<int>(0);
      final next = ValueNotifier<int>(0);
      final toolbar = ValueNotifier<int>(0);
      var selected = 0;
      await pumpView(
        tester,
        pageIndex: 1,
        previous: previous,
        next: next,
        toolbar: toolbar,
        onDoubleTapAt: (_) => selected++,
      );
      final origin = tester.getTopLeft(find.byType(ReaderView));
      await tester.tapAt(origin + const Offset(270, 100));
      await tester.pump(kDoubleTapMinTime);
      await tester.tapAt(origin + const Offset(270, 100));
      await tester.pumpAndSettle();

      expect(next.value, 2);
      expect(selected, 0);
    });

    testWidgets('快速三击翻页区域按三次点击逐页翻页', (tester) async {
      final previous = ValueNotifier<int>(0);
      final next = ValueNotifier<int>(0);
      final toolbar = ValueNotifier<int>(0);
      var selected = 0;
      await pumpView(
        tester,
        pageIndex: 1,
        previous: previous,
        next: next,
        toolbar: toolbar,
        onDoubleTapAt: (_) => selected++,
      );
      final origin = tester.getTopLeft(find.byType(ReaderView));
      await tester.tapAt(origin + const Offset(270, 100));
      await tester.pump(kDoubleTapMinTime);
      await tester.tapAt(origin + const Offset(270, 100));
      await tester.pump(kDoubleTapMinTime);
      await tester.tapAt(origin + const Offset(270, 100));
      await tester.pumpAndSettle();

      expect(next.value, 3);
      expect(selected, 0);
    });

    testWidgets('单击回调消费手势后不再翻页或打开工具栏', (tester) async {
      final previous = ValueNotifier<int>(0);
      final next = ValueNotifier<int>(0);
      final toolbar = ValueNotifier<int>(0);
      final tapped = <Offset>[];
      await pumpView(
        tester,
        pageIndex: 1,
        previous: previous,
        next: next,
        toolbar: toolbar,
        onTapAt: (position) {
          tapped.add(position);
          return true;
        },
      );
      final origin = tester.getTopLeft(find.byType(ReaderView));
      await tester.tapAt(origin + const Offset(150, 100));
      await tester.pump();
      expect(tapped, hasLength(1));
      expect(previous.value, 0);
      expect(next.value, 0);
      expect(toolbar.value, 0);
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

    testWidgets('起点抖动未越过容差后横向滑动仍进入拖动', (tester) async {
      final previous = ValueNotifier<int>(0);
      final next = ValueNotifier<int>(0);
      final toolbar = ValueNotifier<int>(0);
      var started = false;
      await pumpView(
        tester,
        pageIndex: 1,
        previous: previous,
        next: next,
        toolbar: toolbar,
        onDragStart: (_) => started = true,
      );
      final origin = tester.getTopLeft(find.byType(ReaderView));
      final gesture = await tester.startGesture(
        origin + const Offset(150, 100),
      );
      await gesture.moveBy(const Offset(-12, 15));
      await gesture.moveBy(const Offset(-60, 0));
      await gesture.up();

      expect(started, isTrue);
    });

    for (final minimum in <double?>[null, 20]) {
      for (final slop in [18.0, 36.0]) {
        testWidgets('红线向上斜滑保留左右拖动，不被纵向观察抢走：$minimum / $slop', (tester) async {
          for (final direction in [-1.0, 1.0]) {
            var started = 0;
            var menus = 0;
            final ends = <DragEndDetails>[];
            final gestures = <ReaderGesture>[];
            await _pumpGestureView(
              tester,
              ReaderView(
                config: ReaderGestureConfig(minimumFlingVelocity: minimum),
                onDragStart: (_) => started++,
                onDragEnd: ends.add,
                onGesture: gestures.add,
                onToggleToolbar: () => menus++,
              ),
              touchSlop: slop,
            );
            final down =
                tester.getTopLeft(find.byType(ReaderView)) +
                Offset(direction < 0 ? 270 : 30, 180);
            final drag = await tester.startGesture(down);
            await _moveSamples(tester, drag, [
              for (var step = 1; step <= 20; step++)
                down + Offset(direction * 100, -170) * (step / 20),
            ]);
            await drag.up(timeStamp: const Duration(milliseconds: 400));
            await tester.pump();
            expect(started, 1);
            expect(ends, hasLength(1));
            expect(gestures, [
              direction < 0
                  ? ReaderGesture.swipeLeft
                  : ReaderGesture.swipeRight,
            ]);
            expect(menus, 0);
          }
        });
      }

      testWidgets('向上竖滑的横向抖动未过设备容差时不进入翻页：$minimum', (tester) async {
        var started = 0;
        var turns = 0;
        final gestures = <ReaderGesture>[];
        await _pumpGestureView(
          tester,
          ReaderView(
            config: ReaderGestureConfig(minimumFlingVelocity: minimum),
            onDragStart: (_) => started++,
            onNext: () => turns++,
            onPrevious: () => turns++,
            onGesture: gestures.add,
          ),
          touchSlop: 18,
        );
        final down =
            tester.getTopLeft(find.byType(ReaderView)) + const Offset(150, 180);
        final drag = await tester.startGesture(down);
        await _moveSamples(tester, drag, [
          for (var step = 1; step <= 20; step++)
            down + const Offset(8, -140) * (step / 20),
        ]);
        await drag.up(timeStamp: const Duration(milliseconds: 400));
        await tester.pump();
        expect(started, 0);
        expect(turns, 0);
        expect(gestures, [ReaderGesture.swipeUp]);
      });
    }

    for (final slop in [18.0, 40.0]) {
      testWidgets('普通分页斜拉交给纵向主方向，锁定后横移不翻页：$slop', (tester) async {
        final events = <String>[];
        await _pumpGestureView(
          tester,
          GestureDetector(
            onVerticalDragStart: (_) => events.add('纵向'),
            child: ReaderView(
              onDragStart: (_) => events.add('横向'),
              onNext: () => events.add('翻页'),
              onPrevious: () => events.add('翻页'),
              onToggleToolbar: () => events.add('菜单'),
            ),
          ),
          touchSlop: slop,
        );
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(ReaderView)),
        );
        await gesture.moveBy(Offset(slop + 4, slop + 20));
        await tester.pump();
        await gesture.moveBy(const Offset(-150, 0));
        await gesture.up();
        await tester.pump();
        expect(events, ['纵向']);
      });
    }

    testWidgets('普通分页水平主方向锁定后纵移仍保留拖动生命周期', (tester) async {
      final events = <String>[];
      await _pumpGestureView(
        tester,
        GestureDetector(
          onVerticalDragStart: (_) => events.add('纵向'),
          child: ReaderView(
            onDragStart: (_) => events.add('开始'),
            onDragEnd: (_) => events.add('结束'),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ReaderView)),
      );
      await gesture.moveBy(const Offset(-40, 24));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 80));
      await gesture.moveBy(const Offset(-50, 0));
      await gesture.up();
      await tester.pump();
      expect(events, ['开始', '结束']);
    });

    testWidgets('普通分页纵向主方向拒绝后回正不进入横向拖动', (tester) async {
      var started = 0;
      await _pumpGestureView(tester, ReaderView(onDragStart: (_) => started++));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ReaderView)),
      );
      for (final delta in [
        const Offset(-12, 15),
        const Offset(0, 30),
        const Offset(-150, 0),
      ]) {
        await gesture.moveBy(delta);
        await tester.pump();
      }
      await gesture.up();
      expect(started, 0);
    });

    testWidgets('普通分页按设备容差等待累计主方向，临界距离和同幅斜拉不锁定', (tester) async {
      var started = 0;
      await _pumpGestureView(
        tester,
        ReaderView(onDragStart: (_) => started++),
        touchSlop: 40,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ReaderView)),
      );
      for (final delta in [
        const Offset(40, 0),
        const Offset(0, 40),
        const Offset(1, 1),
      ]) {
        await gesture.moveBy(delta);
        await tester.pump();
        expect(started, 0);
      }
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      expect(started, 1);
      await gesture.up();
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

    for (final minimum in <double?>[null, 20]) {
      testWidgets('最低快扫速度 $minimum 保留左右低速及反向释放的原值', (tester) async {
        for (final direction in <double>[-1, 1]) {
          for (final reverse in [false, true]) {
            final ends = <DragEndDetails>[];
            await _pumpGestureView(
              tester,
              ReaderView(
                config: ReaderGestureConfig(minimumFlingVelocity: minimum),
                onDragEnd: ends.add,
              ),
            );
            final start =
                tester.getTopLeft(find.byType(ReaderView)) +
                const Offset(150, 100);
            final velocity = (reverse ? -direction : direction) * 30;
            await _deceleratingDrag(
              tester,
              start,
              direction * 20,
              finalVelocity: velocity,
            );
            expect(ends, hasLength(1));
            expect(
              ends.single.primaryVelocity,
              closeTo(minimum == null ? 0 : velocity, 0.01),
            );
            expect(ends.single.velocity.pixelsPerSecond.dy, 0);
            expect(
              ends.single.velocity.pixelsPerSecond.dx,
              ends.single.primaryVelocity,
            );
          }
        }
      });
    }

    testWidgets('快扫速度等于配置门槛时保留真实估计值', (tester) async {
      final estimate = await _boundaryDragVelocity(tester, 1);
      expect(estimate, closeTo(20, 0.01));
      // 重放同一轨迹，用真实估计值验证等号，避免把采样舍入当作速度规则。
      expect(await _boundaryDragVelocity(tester, estimate), estimate);
      expect(await _boundaryDragVelocity(tester, estimate + 0.01), 0);
    });

    for (final direction in [-1.0, 1.0]) {
      testWidgets('3D 短促横滑越过设备阈值立即起拖：$direction', (tester) async {
        final events = <Object>[];
        var taps = 0;
        await _pumpGestureView(
          tester,
          ReaderView(
            config: const ReaderGestureConfig(minimumFlingVelocity: 20),
            onDragStart: events.add,
            onDragUpdate: events.add,
            onDragEnd: events.add,
            onNext: () => taps++,
            onPrevious: () => taps++,
          ),
          touchSlop: 36,
        );
        final origin = tester.getTopLeft(find.byType(ReaderView));
        final down = origin + Offset(direction < 0 ? 270 : 30, 100);
        final gesture = await tester.startGesture(down);
        await gesture.moveBy(
          Offset(direction * 45, 0),
          timeStamp: const Duration(milliseconds: 30),
        );
        expect(events.whereType<DragStartDetails>(), hasLength(1));
        expect(
          events.whereType<DragStartDetails>().single.localPosition,
          down - origin,
        );
        expect(
          events.whereType<DragUpdateDetails>().single.delta,
          Offset(direction * 45, 0),
        );
        await gesture.moveBy(
          Offset(direction * 135, 0),
          timeStamp: const Duration(milliseconds: 60),
        );
        await gesture.up(timeStamp: const Duration(milliseconds: 70));
        expect(events.whereType<DragEndDetails>(), hasLength(1));
        expect(taps, 0, reason: '快扫不能退化成点击或被漏掉');
      });
    }

    testWidgets('起拖立即交付容差前锚点和实际位置，保留坐标与时间戳', (tester) async {
      final events = <Object>[];
      await _pumpGestureView(
        tester,
        ReaderView(
          config: const ReaderGestureConfig(minimumFlingVelocity: 20),
          onDragStart: events.add,
          onDragUpdate: events.add,
        ),
        touchSlop: 36,
        origin: const Offset(37, 29),
      );
      final origin = tester.getTopLeft(find.byType(ReaderView));
      final down = origin + const Offset(180, 90);
      final gesture = await tester.startGesture(down);
      await gesture.moveTo(
        down + const Offset(-1, 0),
        timeStamp: const Duration(milliseconds: 20),
      );
      expect(events, isEmpty);
      await gesture.moveTo(
        down + const Offset(-37, 2),
        timeStamp: const Duration(milliseconds: 40),
      );
      _expectNativeHandoff(events, origin);
      await gesture.moveTo(down + const Offset(-42, 8));
      expect(events, hasLength(3));
      final update = events.last as DragUpdateDetails;
      expect(update.delta, const Offset(-5, 0));
      expect(update.localPosition, const Offset(138, 98));
      await gesture.up();
    });

    for (final angle in [45.0, 49.9, 50.1]) {
      testWidgets('原生水平方向门槛 $angle 度使用径向系统 slop', (tester) async {
        for (final direction in [-1.0, 1.0]) {
          var started = 0;
          await _pumpGestureView(
            tester,
            ReaderView(
              config: const ReaderGestureConfig(minimumFlingVelocity: 20),
              onDragStart: (_) => started++,
            ),
            touchSlop: 24,
          );
          final down =
              tester.getTopLeft(find.byType(ReaderView)) +
              const Offset(150, 80);
          final radians = angle * math.pi / 180;
          final vector = Offset(
            direction * math.cos(radians),
            math.sin(radians),
          );
          final gesture = await tester.startGesture(down);
          await _moveSamples(tester, gesture, [
            for (final distance in [1, 26, 27, 28, 29])
              down + vector * distance.toDouble(),
          ]);
          expect(started, angle < 50 ? 1 : 0);
          await gesture.up();
          await tester.pump();
        }
      });
    }

    testWidgets('未过设备阈值时双指取消，第二指移动也不恢复翻页', (tester) async {
      final events = <String>[];
      await _pumpGestureView(
        tester,
        ReaderView(
          config: const ReaderGestureConfig(minimumFlingVelocity: 20),
          onDragStart: (_) => events.add('开始'),
          onDragEnd: (_) => events.add('结束'),
          onDragCancel: () => events.add('取消'),
          onNext: () => events.add('点击'),
        ),
      );
      final down =
          tester.getTopLeft(find.byType(ReaderView)) + const Offset(270, 100);
      final first = await tester.startGesture(down, pointer: 1);
      await _moveSamples(tester, first, [
        down + const Offset(-1, 0),
        down + const Offset(-12, 0),
      ]);
      expect(events, isEmpty);
      final second = await tester.startGesture(
        down + const Offset(-20, 20),
        pointer: 2,
      );
      await _moveSamples(tester, second, [
        for (final distance in [21, 60, 70, 80, 90])
          down + Offset(-distance.toDouble(), 20),
      ], firstTime: 60);
      await first.up();
      await second.up();
      await tester.pump();
      expect(events, isNotEmpty);
      expect(events.every((event) => event == '取消'), isTrue);
      events.clear();
      await _deceleratingDrag(tester, down, -80);
      expect(events, ['开始', '结束']);
    });

    for (final minimum in <double?>[null, 20]) {
      for (final alreadyStarted in [false, true]) {
        testWidgets('最低速度 $minimum 双指，已起拖 $alreadyStarted', (tester) async {
          final events = <String>[];
          var next = 0;
          await _pumpGestureView(
            tester,
            ReaderView(
              config: ReaderGestureConfig(minimumFlingVelocity: minimum),
              onDragStart: (_) => events.add('开始'),
              onDragEnd: (_) => events.add('结束'),
              onDragCancel: () => events.add('取消'),
              onNext: () => next++,
            ),
          );
          final start =
              tester.getTopLeft(find.byType(ReaderView)) +
              const Offset(270, 100);
          await _twoPointerDrag(tester, start, alreadyStarted: alreadyStarted);
          expect(
            events,
            minimum != null && !alreadyStarted ? ['取消'] : ['开始', '结束'],
          );
          expect(next, minimum == null ? 1 : 0);
          events.clear();
          await _deceleratingDrag(tester, start, -80);
          expect(events, ['开始', '结束']);
        });
      }
    }

    testWidgets('低速快扫沿用设备 slop 和最小距离，拖动不会补发边缘点击', (tester) async {
      var started = 0;
      var next = 0;
      final ends = <DragEndDetails>[];
      await _pumpGestureView(
        tester,
        ReaderView(
          config: const ReaderGestureConfig(minimumFlingVelocity: 20),
          onDragStart: (_) => started++,
          onDragEnd: ends.add,
          onNext: () => next++,
        ),
        touchSlop: 8,
      );
      final start =
          tester.getTopLeft(find.byType(ReaderView)) + const Offset(270, 100);
      await _deceleratingDrag(tester, start, -12);
      expect(started, 1);
      expect(ends, hasLength(1));
      expect(ends.single.primaryVelocity, closeTo(-30, 0.01));
      expect(next, 0);
    });

    testWidgets('最低速度 20 不改变系统 36 dp 的起拖距离', (tester) async {
      var started = 0;
      var next = 0;
      await _pumpGestureView(
        tester,
        ReaderView(
          config: const ReaderGestureConfig(minimumFlingVelocity: 20),
          onDragStart: (_) => started++,
          onNext: () => next++,
        ),
        touchSlop: 36,
      );
      final start =
          tester.getTopLeft(find.byType(ReaderView)) + const Offset(270, 100);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(
        const Offset(-20, 0),
        timeStamp: const Duration(milliseconds: 20),
      );
      expect(started, 0);
      await gesture.up(timeStamp: const Duration(milliseconds: 30));
      await tester.pump();
      expect(started, 0);
      expect(next, 1);
    });

    testWidgets('低速释放仍受设备最小快扫距离约束', (tester) async {
      final ends = <DragEndDetails>[];
      await _pumpGestureView(
        tester,
        ReaderView(
          config: const ReaderGestureConfig(minimumFlingVelocity: 20),
          onDragEnd: ends.add,
        ),
        touchSlop: 36,
      );
      final start =
          tester.getTopLeft(find.byType(ReaderView)) + const Offset(150, 100);
      await _deceleratingDrag(tester, start, 20, leadDistance: 60);
      expect(ends, hasLength(1));
      expect(ends.single.primaryVelocity, 0);
    });

    testWidgets('可配置快扫仍与单击消费及双击选择竞争', (tester) async {
      var tapped = 0;
      var next = 0;
      var selected = 0;
      var started = 0;
      await _pumpGestureView(
        tester,
        ReaderView(
          config: const ReaderGestureConfig(minimumFlingVelocity: 20),
          onTapAt: (_) {
            tapped++;
            return true;
          },
          onNext: () => next++,
          onDoubleTapAt: (_) => selected++,
          onDragStart: (_) => started++,
        ),
      );
      final origin = tester.getTopLeft(find.byType(ReaderView));
      await tester.tapAt(origin + const Offset(270, 100));
      await tester.pump(kDoubleTapTimeout);
      expect(tapped, 1);
      expect(next, 0);
      await tester.tapAt(origin + const Offset(150, 100));
      await tester.pump(kDoubleTapMinTime);
      await tester.tapAt(origin + const Offset(150, 100));
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(tapped, 1);
      expect(started, 0);
    });

    testWidgets('可配置快扫不会抢占长按选择', (tester) async {
      var selected = 0;
      var started = 0;
      var tapped = 0;
      await _pumpGestureView(
        tester,
        ReaderView(
          config: const ReaderGestureConfig(minimumFlingVelocity: 20),
          onLongPressAt: (_) => selected++,
          onDragStart: (_) => started++,
          onNext: () => tapped++,
          onToggleToolbar: () => tapped++,
        ),
      );
      final origin = tester.getTopLeft(find.byType(ReaderView));
      await tester.longPressAt(origin + const Offset(270, 100));
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(started, 0);
      expect(tapped, 0);
    });

    testWidgets('可配置水平快扫不拦截垂直及 50 度外的子视图滚动', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var started = 0;
      final gestures = <ReaderGesture>[];
      await _pumpGestureView(
        tester,
        ReaderView(
          config: const ReaderGestureConfig(minimumFlingVelocity: 20),
          continuousScroll: true,
          onGesture: gestures.add,
          onDragStart: (_) => started++,
          child: ListView(
            controller: scroll,
            children: [
              for (var row = 0; row < 20; row++) const SizedBox(height: 60),
            ],
          ),
        ),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      expect(started, 0);
      expect(gestures, isEmpty);
      scroll.jumpTo(0);
      final down =
          tester.getTopLeft(find.byType(ReaderView)) + const Offset(150, 150);
      final drag = await tester.startGesture(down);
      await _moveSamples(tester, drag, [
        for (var step = 1; step <= 5; step++)
          down + Offset(-70.0, -100.0) * (step / 5),
      ]);
      await drag.up();
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      expect(started, 0);
      expect(gestures, isEmpty);
    });

    testWidgets('可配置水平快扫保留纵向手势观察', (tester) async {
      final gestures = <ReaderGesture>[];
      var started = 0;
      await _pumpGestureView(
        tester,
        ReaderView(
          config: const ReaderGestureConfig(minimumFlingVelocity: 20),
          onGesture: gestures.add,
          onDragStart: (_) => started++,
        ),
      );
      await tester.fling(find.byType(ReaderView), const Offset(0, -80), 1000);
      await tester.pumpAndSettle();
      expect(gestures, [ReaderGesture.swipeUp]);
      expect(started, 0);
    });

    for (final minimum in <double?>[null, 20]) {
      testWidgets('水平手势保留辅助功能滚动生命周期：$minimum', (tester) async {
        final semantics = tester.ensureSemantics();
        final events = <Object>[];
        await _pumpGestureView(
          tester,
          ReaderView(
            config: ReaderGestureConfig(minimumFlingVelocity: minimum),
            onDragStart: events.add,
            onDragUpdate: events.add,
            onDragEnd: events.add,
          ),
        );
        tester.semantics.scrollLeft(
          scrollable: find.semantics.scrollable(axis: Axis.horizontal),
        );
        await tester.pump();
        expect(events, [
          isA<DragStartDetails>(),
          isA<DragUpdateDetails>(),
          isA<DragEndDetails>(),
        ]);
        expect(
          (events[0] as DragStartDetails).localPosition,
          const Offset(150, 100),
        );
        expect((events[1] as DragUpdateDetails).delta, const Offset(-240, 0));
        expect(
          (events[2] as DragEndDetails).localPosition,
          const Offset(-90, 100),
        );
        expect((events[2] as DragEndDetails).primaryVelocity, 0);
        semantics.dispose();
      });
    }
  });
}
