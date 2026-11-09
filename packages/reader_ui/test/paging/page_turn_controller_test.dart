import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/paging/page_turn_controller.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/reader_session.dart';

class _Source implements ReaderChapterSource {
  _Source(this.pageCount);

  final int pageCount;

  @override
  int get chapterCount => 1;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => [
    for (var page = 0; page < pageCount; page++)
      PageContent(
        spineIndex: spineIndex,
        pageIndex: page,
        slices: const [],
        usedHeight: 0,
        pageHeight: 480,
        topPadding: 0,
      ),
  ];
}

Future<PageTurnController> _controller(
  WidgetTester tester, {
  bool rtl = false,
  Future<void>? imageGate,
  Future<void>? targetImageGate,
  int pageCount = 3,
}) async {
  final store = MemoryReaderProgressStore();
  await store.save('curl', const ReaderProgress(spineIndex: 0, pageIndex: 1));
  final session = ReaderSession(
    source: _Source(pageCount),
    store: store,
    bookId: 'curl',
  );
  await session.open();
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(1, 1);
  picture.dispose();
  final controller =
      PageTurnController(
          session: session,
          vsync: tester,
          acquireImage: (page) async {
            await imageGate;
            if (page.pageIndex != 1) await targetImageGate;
            return image;
          },
        )
        ..size = const ui.Size(320, 480)
        ..mode = PageTurnMode.simulationBessel
        ..rtl = rtl;
  addTearDown(() {
    controller.dispose();
    session.dispose();
    image.dispose();
  });
  return controller;
}

void _move(PageTurnController controller, ui.Offset canonical) {
  final point = ui.Offset(
    controller.rtl ? controller.size.width - canonical.dx : canonical.dx,
    canonical.dy,
  );
  controller.updateDrag(
    DragUpdateDetails(globalPosition: point, localPosition: point),
  );
}

Future<void> _startDrag(
  WidgetTester tester,
  PageTurnController controller,
) async {
  final down = ui.Offset(controller.rtl ? 10 : 310, 430);
  controller.pointerDown(down);
  controller.beginDrag(DragStartDetails(localPosition: down));
  _move(controller, const ui.Offset(220, 380));
  for (var frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(controller.phase, PageTurnPhase.dragging);
  expect(controller.point, const ui.Offset(220, 380));
}

void _drag(
  PageTurnController controller,
  ui.Offset point, {
  bool start = false,
}) {
  final physical = ui.Offset(
    controller.fromRight ? point.dx : controller.size.width - point.dx,
    point.dy,
  );
  if (start) {
    controller.pointerDown(physical);
    controller.beginDrag(DragStartDetails(localPosition: physical));
  } else {
    controller.updateDrag(
      DragUpdateDetails(globalPosition: physical, localPosition: physical),
    );
  }
}

void _swipeDuringTurn(
  PageTurnController controller, {
  bool next = true,
  bool complete = true,
  bool release = true,
}) {
  final fromRight = next != controller.rtl;
  final down = ui.Offset(fromRight ? 310 : 10, 240);
  final distance = complete ? 220.0 : 10.0;
  final latest = down.translate(fromRight ? -distance : distance, 0);
  controller.pointerDown(down);
  controller.beginDrag(DragStartDetails(localPosition: down));
  controller.updateDrag(
    DragUpdateDetails(globalPosition: latest, localPosition: latest),
  );
  if (release) controller.endDrag(DragEndDetails());
}

void _expectSameCurl(PageTurnController forward, PageTurnController backward) {
  expect(backward.point, forward.point);
  expect(backward.progress, closeTo(forward.progress, 0.00001));
  expect(backward.horizontal, forward.horizontal);
  expect(backward.top, forward.top);
  expect(backward.besselGeometry!.a, forward.besselGeometry!.a);
  expect(backward.besselGeometry!.f, forward.besselGeometry!.f);
  expect(backward.fromRight, !forward.fromRight);
}

void main() {
  for (final rtl in [false, true]) {
    testWidgets('${rtl ? 'RTL' : 'LTR'} 回拖时页角与触点重合', (tester) async {
      final controller = await _controller(tester, rtl: rtl);
      await _startDrag(tester, controller);

      _move(controller, const ui.Offset(280, 410));

      expect(controller.point, const ui.Offset(280, 410));
      expect(controller.besselGeometry!.a, const ui.Offset(280, 410));
      expect(controller.session.progress!.pageIndex, 1);
      controller.cancel();
      expect(controller.phase, PageTurnPhase.idle);
      expect(controller.session.progress!.pageIndex, 1);
    });
  }

  testWidgets('横坐标不变时页角仍跟随纵向触点', (tester) async {
    final controller = await _controller(tester);
    await _startDrag(tester, controller);

    _move(controller, const ui.Offset(220, 300));
    expect(controller.point, const ui.Offset(220, 300));
    expect(controller.besselGeometry!.a, const ui.Offset(220, 300));
  });

  testWidgets('中心拖动从整条侧边起卷且纸边经过触点', (tester) async {
    final controller = await _controller(tester);
    const down = ui.Offset(310, 240);
    controller.pointerDown(down);
    controller.beginDrag(DragStartDetails(localPosition: down));
    _move(controller, const ui.Offset(220, 240));
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.horizontal, isTrue);
    expect(controller.point, const ui.Offset(220, 240));
    final geometry = controller.besselGeometry!;
    final back = geometry.backPath(geometry.frontPath());
    expect(geometry.horizontal, isTrue);
    expect(geometry.a, const ui.Offset(220, 240));
    expect(back.getBounds().height, controller.size.height);
    expect(back.getBounds().width, greaterThan(controller.size.width / 10));
    expect(back.contains(const ui.Offset(240, 10)), isTrue);
    expect(back.contains(const ui.Offset(240, 470)), isTrue);
  });

  testWidgets('点击翻页从整条侧边中部起卷', (tester) async {
    final controller = await _controller(tester);
    controller.request(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(controller.point!.dy, closeTo(controller.size.height / 2, 0.001));
    final geometry = controller.besselGeometry!;
    expect(geometry.horizontal, isTrue);
    expect(geometry.backPath(geometry.frontPath()).getBounds().height, 480);
    controller.cancel();
  });

  testWidgets('拖出上下页缘后抓取点仍留在纸张范围内', (tester) async {
    final controller = await _controller(tester);
    await _startDrag(tester, controller);

    _move(controller, const ui.Offset(220, 550));
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.point!.dy, closeTo(479.9, 0.001));
    expect(controller.session.progress!.pageIndex, 1);
  });

  testWidgets('上角纵向回拖和越界拖动保持连续', (tester) async {
    final controller = await _controller(tester);
    const down = ui.Offset(310, 50);
    controller.pointerDown(down);
    controller.beginDrag(DragStartDetails(localPosition: down));
    _move(controller, const ui.Offset(220, 100));
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.top, isTrue);
    expect(controller.horizontal, isFalse);
    expect(controller.point, const ui.Offset(220, 100));
    _move(controller, const ui.Offset(220, 10));
    expect(controller.point, const ui.Offset(220, 10));
    expect(controller.besselGeometry!.a, const ui.Offset(220, 10));
    _move(controller, const ui.Offset(220, -100));
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.point!.dy, closeTo(0.1, 0.001));
  });

  testWidgets('上一页从左侧起卷且纸边随触点回拖', (tester) async {
    final controller = await _controller(tester);
    const down = ui.Offset(10, 240);
    controller.pointerDown(down);
    controller.beginDrag(DragStartDetails(localPosition: down));
    _move(controller, const ui.Offset(100, 300));
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.next, isFalse);
    expect(controller.horizontal, isTrue);
    expect(controller.point, const ui.Offset(220, 300));
    expect(controller.besselGeometry!.a, const ui.Offset(220, 300));
    _move(controller, const ui.Offset(40, 200));
    expect(controller.point, const ui.Offset(280, 200));
    expect(controller.besselGeometry!.a, const ui.Offset(280, 200));
    controller.cancel();
    expect(controller.session.progress!.pageIndex, 1);
  });

  testWidgets('松手后完成仿真翻页才提交目标页', (tester) async {
    final controller = await _controller(tester);
    await _startDrag(tester, controller);

    controller.endDrag(DragEndDetails());
    expect(controller.phase, PageTurnPhase.settling);
    expect(controller.session.progress!.pageIndex, 1);
    await tester.pump(const Duration(milliseconds: 150));
    expect(controller.session.progress!.pageIndex, 1);
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.phase, PageTurnPhase.settling);
    expect(controller.session.progress!.pageIndex, 1);
    await tester.pumpAndSettle();

    expect(controller.phase, PageTurnPhase.idle);
    expect(controller.session.progress!.pageIndex, 2);
    await controller.session.flushProgress();
  });

  for (final mode in <PageTurnMode>[
    PageTurnMode.cover,
    PageTurnMode.coverStack,
    PageTurnMode.simulationBessel,
    PageTurnMode.simulation3d,
    PageTurnMode.slideHorizontal,
  ]) {
    testWidgets('${mode.label}收尾统一使用 420 毫秒动画', (tester) async {
      final controller = await _controller(tester);
      controller
        ..mode = mode
        ..request(true);
      await tester.pump();
      expect(controller.phase, PageTurnPhase.settling);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.phase, PageTurnPhase.settling);
      await tester.pump(const Duration(milliseconds: 20));
      expect(controller.progress, 1);
      await tester.pumpAndSettle();
      expect(controller.phase, PageTurnPhase.idle);
      expect(controller.session.progress!.pageIndex, 2);
      await controller.session.flushProgress();
    });
  }

  testWidgets('3D 仿真折角跟随触点移动', (tester) async {
    final controller = await _controller(tester);
    controller.mode = PageTurnMode.simulation3d;
    const down = ui.Offset(310, 240);
    controller.pointerDown(down);
    controller.beginDrag(DragStartDetails(localPosition: down));
    _move(controller, const ui.Offset(150, 300));
    await tester.pump();
    await tester.pump();

    expect(controller.point, isNotNull);
    expect(controller.point!.dx, closeTo(160, 0.5));
    expect(controller.point!.dy, closeTo(300, 0.5));
    final geometry = controller.curl3dGeometry!;
    expect(geometry.grab, const ui.Offset(320, 240));
    final corner = geometry.pointAt(geometry.grab).position;
    expect(
      (corner - controller.point!).distance,
      lessThan(0.01),
      reason: '折起的页角必须贴在触点上',
    );
    controller.cancel();
  });

  testWidgets('动画期间快速连续点击逐页排队翻页', (tester) async {
    final controller = await _controller(tester, pageCount: 5);
    controller.request(true);
    await tester.pump();
    expect(controller.phase, PageTurnPhase.settling);

    controller
      ..request(true)
      ..request(true);
    await tester.pumpAndSettle();

    expect(controller.phase, PageTurnPhase.idle);
    expect(controller.session.progress!.pageIndex, 4);
    await controller.session.flushProgress();
  });

  for (final rtl in [false, true]) {
    testWidgets('${rtl ? 'RTL' : 'LTR'} 收尾期间的完整滑动逐页排队且保留方向', (tester) async {
      final controller = await _controller(tester, rtl: rtl, pageCount: 5);
      controller.request(true);
      await tester.pump();
      expect(controller.phase, PageTurnPhase.settling);
      _swipeDuringTurn(controller);
      _swipeDuringTurn(controller, next: false);
      await tester.pumpAndSettle();

      expect(controller.phase, PageTurnPhase.idle);
      expect(controller.session.progress!.pageIndex, 2);
      expect(controller.session.pageTurns, 3);
      await controller.session.flushProgress();
    });
  }

  testWidgets('图片准备期间的完整滑动不会丢失', (tester) async {
    final gate = Completer<void>();
    final controller = await _controller(
      tester,
      imageGate: gate.future,
      pageCount: 5,
    );
    controller.request(true);
    await tester.pump();
    expect(controller.phase, PageTurnPhase.preparing);
    _swipeDuringTurn(controller);
    gate.complete();
    await tester.pumpAndSettle();

    expect(controller.phase, PageTurnPhase.idle);
    expect(controller.session.progress!.pageIndex, 3);
    await controller.session.flushProgress();
  });

  testWidgets('起手时动画未结束、松手时已结束的滑动仍翻页', (tester) async {
    final controller = await _controller(tester, pageCount: 5);
    controller.request(true);
    await tester.pump();
    _swipeDuringTurn(controller, release: false);
    await tester.pumpAndSettle();
    expect(controller.session.progress!.pageIndex, 2);
    controller.endDrag(DragEndDetails());
    await tester.pumpAndSettle();

    expect(controller.phase, PageTurnPhase.idle);
    expect(controller.session.progress!.pageIndex, 3);
    await controller.session.flushProgress();
  });

  testWidgets('滑动尚未松手时外部跳转使旧输入失效', (tester) async {
    final controller = await _controller(tester, pageCount: 5);
    controller.request(true);
    await tester.pump();
    _swipeDuringTurn(controller, release: false);
    await tester.pumpAndSettle();
    await controller.session.jumpToChapter(0);
    expect(controller.session.progress!.pageIndex, 0);
    controller.endDrag(DragEndDetails());
    await tester.pumpAndSettle();

    expect(controller.phase, PageTurnPhase.idle);
    expect(controller.session.progress!.pageIndex, 0);
    await controller.session.flushProgress();
  });

  for (final cancel in [false, true]) {
    testWidgets('收尾期间${cancel ? '取消的' : '距离不足的'}滑动不额外翻页或取消当前动画', (
      tester,
    ) async {
      final controller = await _controller(tester, pageCount: 5);
      controller.request(true);
      await tester.pump();
      _swipeDuringTurn(controller, complete: cancel, release: !cancel);
      if (cancel) controller.cancelDrag();
      expect(controller.phase, PageTurnPhase.settling);
      await tester.pumpAndSettle();

      expect(controller.phase, PageTurnPhase.idle);
      expect(controller.session.progress!.pageIndex, 2);
      await controller.session.flushProgress();
    });
  }

  testWidgets('轻点翻页期间拖动手势取消不会清空翻页动画', (tester) async {
    final controller = await _controller(tester);
    controller.request(true);
    await tester.pump();
    expect(controller.phase, PageTurnPhase.settling);

    controller.cancelDrag();
    expect(controller.active, isTrue);

    await tester.pumpAndSettle();
    expect(controller.phase, PageTurnPhase.idle);
    expect(controller.session.progress!.pageIndex, 2);
    await controller.session.flushProgress();
  });

  testWidgets('真实拖动取消仍会中止翻页', (tester) async {
    final controller = await _controller(tester);
    await _startDrag(tester, controller);
    _move(controller, const ui.Offset(220, 240));
    await tester.pump();
    expect(controller.phase, PageTurnPhase.dragging);

    controller.cancelDrag();
    expect(controller.phase, PageTurnPhase.idle);
    expect(controller.session.progress!.pageIndex, 1);
    await controller.session.flushProgress();
  });

  testWidgets('图片准备超时后松手仍按最后拖动距离完成翻页', (tester) async {
    final gate = Completer<void>();
    final controller = await _controller(tester, imageGate: gate.future);
    const down = ui.Offset(310, 430);
    controller.pointerDown(down);
    controller.beginDrag(DragStartDetails(localPosition: down));
    _move(controller, const ui.Offset(220, 380));
    await tester.pump();
    expect(controller.phase, PageTurnPhase.preparing);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 320)),
    );
    controller.endDrag(DragEndDetails());
    gate.complete();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(controller.phase, PageTurnPhase.idle);
    expect(controller.session.progress!.pageIndex, 2);
    await controller.session.flushProgress();
  });

  for (final rtl in [false, true]) {
    for (final next in [false, true]) {
      testWidgets(
        '${rtl ? 'RTL' : 'LTR'} ${next ? '下一页' : '上一页'}中心区恰为屏高二十分之一',
        (tester) async {
          final controller = await _controller(tester, rtl: rtl);
          for (final y in <double>[227.9, 228, 240, 252, 252.1]) {
            final down = ui.Offset((next != rtl) ? 310 : 10, y);
            controller.pointerDown(down);
            controller.beginDrag(DragStartDetails(localPosition: down));
            _move(controller, ui.Offset(next ? 220 : 100, y));
            await tester.pump();

            expect(controller.next, next);
            expect(controller.top, y < 240);
            expect(controller.horizontal, y >= 228 && y <= 252);
            final geometry = controller.besselGeometry!;
            expect(geometry.horizontal, controller.horizontal);
            expect(geometry.a.dx, 220);
            if (controller.horizontal) {
              expect(geometry.a.dy, y);
            } else {
              expect(geometry.c.dx, greaterThanOrEqualTo(-0.001));
              expect(geometry.a.dy, inInclusiveRange(0.1, 479.9));
            }
            controller.cancel();
          }
        },
      );
    }
  }

  for (final next in [false, true]) {
    testWidgets('${next ? '下一页' : '上一页'}松手按方向与最小距离判定且只提交一次', (tester) async {
      final controller = await _controller(tester);
      for (final flick in [false, true]) {
        final down = ui.Offset(next ? 310 : 10, 240);
        controller.pointerDown(down);
        controller.beginDrag(DragStartDetails(localPosition: down));
        _move(controller, ui.Offset(next ? 290 : 30, 240));
        await tester.pump();
        final velocity = flick ? (next ? -500.0 : 500.0) : 0.0;
        controller.endDrag(
          DragEndDetails(
            primaryVelocity: velocity,
            velocity: Velocity(pixelsPerSecond: ui.Offset(velocity, 0)),
          ),
        );
        await tester.pumpAndSettle();

        expect(controller.phase, PageTurnPhase.idle);
        expect(
          controller.session.progress!.pageIndex,
          flick ? (next ? 2 : 0) : 1,
        );
      }
      await controller.session.flushProgress();
    });
  }

  for (final rtl in [false, true]) {
    for (final next in [false, true]) {
      for (final waiting in ['ready', 'origin', 'target']) {
        testWidgets('$rtl/$next/$waiting 零速慢回拖取消且正向恢复可提交', (tester) async {
          for (final resume in [false, true]) {
            final gate = Completer<void>();
            final controller = await _controller(
              tester,
              rtl: rtl,
              imageGate: waiting == 'origin' ? gate.future : null,
              targetImageGate: waiting == 'target' ? gate.future : null,
            );
            final sign = (next != rtl) ? -1.0 : 1.0;
            final down = ui.Offset(sign < 0 ? 310 : 10, 240);
            void move(double distance) {
              final p = down.translate(sign * distance, 0);
              controller.updateDrag(
                DragUpdateDetails(localPosition: p, globalPosition: p),
              );
            }

            controller.pointerDown(down);
            controller.beginDrag(DragStartDetails(localPosition: down));
            move(210);
            await tester.pump();
            for (var distance = 209.5; distance >= 50; distance -= 0.5) {
              move(distance);
            }
            if (resume) move(60);
            controller.endDrag(DragEndDetails());
            gate.complete();
            await tester.pumpAndSettle();
            expect(
              controller.session.progress!.pageIndex,
              resume ? (next ? 2 : 0) : 1,
            );
            await controller.session.flushProgress();
          }
        });
      }
    }
  }

  testWidgets('仿真末段一像素内抖动不改变方向', (tester) async {
    final controller = await _controller(tester);
    const down = ui.Offset(310, 240);
    controller.pointerDown(down);
    controller.beginDrag(DragStartDetails(localPosition: down));
    _move(controller, const ui.Offset(220, 240));
    await tester.pump();
    _move(controller, const ui.Offset(220.5, 240));
    _move(controller, const ui.Offset(220.9, 240));
    controller.endDrag(DragEndDetails());
    await tester.pumpAndSettle();
    expect(controller.session.progress!.pageIndex, 2);
    await controller.session.flushProgress();
  });

  for (final releaseBeforeFinish in [false, true]) {
    testWidgets('排队回拖跨过起点仍保留初始方向 $releaseBeforeFinish', (tester) async {
      final controller = await _controller(tester, pageCount: 5);
      controller.request(true);
      await tester.pump();
      const down = ui.Offset(160, 240);
      controller.pointerDown(down);
      controller.beginDrag(DragStartDetails(localPosition: down));
      controller.updateDrag(
        DragUpdateDetails(
          localPosition: const ui.Offset(80, 240),
          globalPosition: const ui.Offset(80, 240),
        ),
      );
      controller.updateDrag(
        DragUpdateDetails(
          localPosition: const ui.Offset(210, 240),
          globalPosition: const ui.Offset(210, 240),
        ),
      );
      if (!releaseBeforeFinish) {
        await tester.pumpAndSettle();
        expect(controller.next, isTrue);
      }
      controller.endDrag(DragEndDetails());
      await tester.pumpAndSettle();
      expect(controller.session.progress!.pageIndex, 2);
      expect(controller.session.pageTurns, 1);
      await controller.session.flushProgress();
    });
  }

  for (final mode in PageTurnMode.values) {
    if (mode == PageTurnMode.simulationBessel ||
        mode == PageTurnMode.simulation3d) {
      continue;
    }
    testWidgets('${mode.label} 保留旧距离与速度门槛', (tester) async {
      final controller = await _controller(tester);
      controller.mode = mode;
      const down = ui.Offset(310, 240);
      controller.pointerDown(down);
      controller.beginDrag(DragStartDetails(localPosition: down));
      controller.updateDrag(
        DragUpdateDetails(
          localPosition: const ui.Offset(280, 240),
          globalPosition: const ui.Offset(280, 240),
        ),
      );
      await tester.pump();
      controller.endDrag(
        DragEndDetails(
          primaryVelocity: -120,
          velocity: const Velocity(pixelsPerSecond: ui.Offset(-120, 0)),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.session.progress!.pageIndex, 1);
    });
  }

  for (final next in [false, true]) {
    testWidgets('${next ? '下一页' : '上一页'}轻扫方向一致即翻页，反向甩动回弹', (tester) async {
      Future<int> run({
        required double distance,
        required double velocity,
      }) async {
        final controller = await _controller(tester);
        final down = ui.Offset(next ? 310 : 10, 240);
        controller.pointerDown(down);
        controller.beginDrag(DragStartDetails(localPosition: down));
        _move(
          controller,
          ui.Offset(next ? 310 - distance : 10 + distance, 240),
        );
        await tester.pump();
        controller.endDrag(
          DragEndDetails(
            primaryVelocity: velocity,
            velocity: Velocity(pixelsPerSecond: ui.Offset(velocity, 0)),
          ),
        );
        await tester.pumpAndSettle();
        final page = controller.session.progress!.pageIndex;
        await controller.session.flushProgress();
        return page;
      }

      expect(
        await run(distance: 30, velocity: 0),
        next ? 2 : 0,
        reason: '慢拖超过 8% 页宽即按起手方向提交',
      );
      expect(
        await run(distance: 20, velocity: next ? -120 : 120),
        next ? 2 : 0,
        reason: '轻扫方向一致即翻页，不再要求 1/4 页宽',
      );
      expect(
        await run(distance: 20, velocity: next ? 120 : -120),
        next ? 1 : 1,
        reason: '反向甩动取消',
      );
      expect(
        await run(distance: 10, velocity: 0),
        next ? 1 : 1,
        reason: '细微抖动不翻页',
      );
    });
  }

  for (final rtl in [false, true]) {
    testWidgets('${rtl ? 'RTL' : 'LTR'} 前后翻页的拖动回拖与收尾共用轨迹且轴相反', (tester) async {
      final forward = await _controller(tester, rtl: rtl);
      final backward = await _controller(tester, rtl: rtl)
        ..next = false;
      for (final y in <double>[60, 240, 420]) {
        _drag(forward, ui.Offset(310, y), start: true);
        _drag(backward, ui.Offset(310, y), start: true);
        _drag(forward, ui.Offset(220, y));
        _drag(backward, ui.Offset(220, y));
        await tester.pump();
        _expectSameCurl(forward, backward);
        _drag(forward, ui.Offset(290, y + 10));
        _drag(backward, ui.Offset(290, y + 10));
        _expectSameCurl(forward, backward);
        forward.endDrag(DragEndDetails());
        backward.endDrag(DragEndDetails());
        await tester.pump();
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 40));
          _expectSameCurl(forward, backward);
        }
        await tester.pumpAndSettle();
        expect(forward.session.progress!.pageIndex, 1);
        expect(backward.session.progress!.pageIndex, 1);
      }
    });

    testWidgets('${rtl ? 'RTL' : 'LTR'} 点击前后翻页的整段收尾动画互为镜像', (tester) async {
      final forward = await _controller(tester, rtl: rtl);
      final backward = await _controller(tester, rtl: rtl);
      forward.request(true);
      backward.request(false);
      await tester.pump();
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 40));
        _expectSameCurl(forward, backward);
        expect(forward.session.progress!.pageIndex, 1);
        expect(backward.session.progress!.pageIndex, 1);
      }
      await tester.pumpAndSettle();
      expect(forward.session.progress!.pageIndex, 2);
      expect(backward.session.progress!.pageIndex, 0);
      await forward.session.flushProgress();
      await backward.session.flushProgress();
    });
  }

  for (final rtl in [false, true]) {
    for (final next in [false, true]) {
      testWidgets('${rtl ? 'RTL' : 'LTR'} ${next ? '下一页' : '上一页'}'
          '角部纵向过拉及松手收尾均受书脊边界限制', (tester) async {
        for (final top in [false, true]) {
          final controller = await _controller(tester, rtl: rtl)
            ..next = next;
          _drag(controller, ui.Offset(310, top ? 50 : 430), start: true);
          _drag(controller, ui.Offset(220, top ? 100 : 380));
          await tester.pump();
          final touch = ui.Offset(90, top ? 430 : 50);
          _drag(controller, touch);

          expect(controller.point, touch);
          expect(controller.horizontal, isFalse);
          final geometry = controller.besselGeometry!;
          expect(geometry.a.dx, touch.dx);
          expect(top ? geometry.a.dy < 240 : geometry.a.dy > 240, isTrue);
          expect(geometry.c.dx, greaterThanOrEqualTo(-0.001));
          expect(controller.session.progress!.pageIndex, 1);
          controller.endDrag(DragEndDetails());
          await tester.pump();
          for (var frame = 0; frame < 8; frame++) {
            await tester.pump(const Duration(milliseconds: 32));
            final geometry = controller.besselGeometry!;
            expect(geometry.e.dx, greaterThanOrEqualTo(-0.001));
            expect(geometry.c.dx, greaterThanOrEqualTo(-160.001));
            expect(controller.session.progress!.pageIndex, 1);
          }
          await tester.pumpAndSettle();
          expect(controller.session.progress!.pageIndex, next ? 2 : 0);
          await controller.session.flushProgress();
        }
      });
    }
  }
}
