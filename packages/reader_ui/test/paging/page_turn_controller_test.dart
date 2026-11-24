import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/paging/page_turn_controller.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_ui_diagnostics.dart';
import 'package:reader_core/source/chapter_source.dart';

import '../support/progressive_source.dart';

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

class _FailingChapterSource extends _Source {
  _FailingChapterSource({this.gate}) : super(1);

  final Completer<void>? gate;
  final started = Completer<void>();
  Object failure = StateError('邻章暂时获取失败');
  bool fail = true;

  @override
  int get chapterCount => 2;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    if (spineIndex == 1) {
      if (!started.isCompleted) started.complete();
      await gate?.future;
      if (fail) throw failure;
    }
    return super.loadChapter(spineIndex);
  }
}

Future<PageTurnController> _controller(
  WidgetTester tester, {
  bool rtl = false,
  Future<void>? imageGate,
  Future<void>? targetImageGate,
  int pageCount = 3,
  ReaderChapterSource? source,
  int initialPage = 1,
  bool autoFinish = true,
  void Function()? onBookEnd,
  void Function(Object error)? onError,
}) async {
  final store = MemoryReaderProgressStore();
  await store.save(
    'curl',
    ReaderProgress(spineIndex: 0, pageIndex: initialPage),
  );
  final session = ReaderSession(
    source: source ?? _Source(pageCount),
    store: store,
    bookId: 'curl',
    autoFinish: autoFinish,
  );
  await session.open();
  final image = _image();
  final controller =
      PageTurnController(
          session: session,
          vsync: tester,
          onBookEnd: onBookEnd,
          onError: onError,
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

ui.Image _image() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(1, 1);
  picture.dispose();
  return image;
}

Future<PageTurnController> _curlController(
  WidgetTester tester, {
  bool rtl = false,
  Future<void>? imageGate,
  Future<void>? targetImageGate,
  int pageCount = 3,
}) async => (await _controller(
  tester,
  rtl: rtl,
  imageGate: imageGate,
  targetImageGate: targetImageGate,
  pageCount: pageCount,
))..mode = PageTurnMode.simulation3d;

Future<void> _startCurlDrag(
  WidgetTester tester,
  PageTurnController controller,
  ui.Offset down,
  ui.Offset touch,
) async {
  final physical = ui.Offset(
    controller.rtl ? controller.size.width - down.dx : down.dx,
    down.dy,
  );
  controller.pointerDown(physical);
  controller.beginDrag(DragStartDetails(localPosition: physical));
  _move(controller, touch);
  await tester.pump();
  await tester.pump();
}

void _releaseCurl(PageTurnController controller, double velocity) {
  controller.endDrag(
    DragEndDetails(
      primaryVelocity: velocity,
      velocity: Velocity(pixelsPerSecond: ui.Offset(velocity, 0)),
    ),
  );
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
  if (controller.mode == PageTurnMode.simulationBessel) {
    expect(controller.point, const ui.Offset(220, 380));
  }
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

Completer<void> _requestWithActivationCancellation(
  PageTurnController controller,
) {
  final cancelled = Completer<void>();
  runZoned(
    () => controller.request(true),
    zoneSpecification: ZoneSpecification(
      scheduleMicrotask: (self, parent, zone, callback) {
        parent.scheduleMicrotask(zone, () {
          if (!cancelled.isCompleted &&
              controller.phase == PageTurnPhase.preparing &&
              controller.turn != null) {
            // 在目标就绪后的下一次异步续接前模拟取消输入。
            controller.cancel();
            cancelled.complete();
          }
          callback();
        });
      },
    ),
  );
  return cancelled;
}

void main() {
  testWidgets('跨章加载失败通知宿主并保留原位置，再次翻页可成功', (tester) async {
    final source = _FailingChapterSource();
    final errors = <Object>[];
    final controller = await _controller(
      tester,
      source: source,
      initialPage: 0,
      onError: errors.add,
    );
    final origin = controller.session.page;
    final progress = controller.session.progress;
    controller.request(true);
    await tester.pumpAndSettle();

    expect(errors, [source.failure]);
    expect(controller.active, isFalse);
    expect(controller.session.page, same(origin));
    expect(controller.session.progress, progress);
    expect(controller.session.pageTurns, 0);
    expect(tester.takeException(), isNull);

    source.fail = false;
    controller.request(true);
    await tester.pumpAndSettle();
    expect(controller.session.page?.spineIndex, 1);
    expect(controller.session.pageTurns, 1);
    expect(errors, [source.failure]);
    await controller.session.flushProgress();
  });

  testWidgets('未提供错误回调时跨章失败仍取消翻页并保留原页', (tester) async {
    final source = _FailingChapterSource();
    final controller = await _controller(
      tester,
      source: source,
      initialPage: 0,
    );
    final origin = controller.session.page;
    controller.request(true);
    await tester.pumpAndSettle();

    expect(controller.active, isFalse);
    expect(controller.session.page, same(origin));
    expect(tester.takeException(), isNull);
  });

  testWidgets('跨章等待者主动取消不触发错误回调', (tester) async {
    final source = _FailingChapterSource()
      ..failure = const ChapterLoadCancelled();
    final errors = <Object>[];
    final controller = await _controller(
      tester,
      source: source,
      initialPage: 0,
      onError: errors.add,
    );
    final origin = controller.session.page;
    controller.request(true);
    await tester.pumpAndSettle();

    expect(errors, isEmpty);
    expect(controller.active, isFalse);
    expect(controller.session.page, same(origin));
    expect(tester.takeException(), isNull);
  });

  for (final externalNavigation in [false, true]) {
    testWidgets('${externalNavigation ? '外部跳转' : '手动取消'}后邻章晚到的真实错误不通知宿主', (
      tester,
    ) async {
      final gate = Completer<void>();
      final source = _FailingChapterSource(gate: gate);
      final errors = <Object>[];
      final controller = await _controller(
        tester,
        source: source,
        initialPage: 0,
        onError: errors.add,
      );
      final origin = controller.session.page;
      controller.request(true);
      await tester.pump();
      expect(source.started.isCompleted, isTrue);
      if (externalNavigation) {
        await controller.session.jumpToChapter(0);
      } else {
        controller.cancel();
      }
      gate.complete();
      await tester.pumpAndSettle();

      expect(errors, isEmpty);
      expect(controller.active, isFalse);
      expect(controller.session.page, same(origin));
      expect(controller.session.pageTurns, 0);
      expect(tester.takeException(), isNull);
    });
  }
  for (final mode in PageTurnMode.values.where(
    (mode) => mode != PageTurnMode.scroll,
  )) {
    for (final rtl in [false, true]) {
      testWidgets('${mode.label} ${rtl ? '从右向左阅读' : '从左向右阅读'} '
          '书尾取消和反向不确认，正向达阈值松手或点击才确认', (tester) async {
        var confirmations = 0;
        final controller =
            await _controller(
                tester,
                rtl: rtl,
                pageCount: 2,
                autoFinish: false,
                onBookEnd: () => confirmations += 1,
              )
              ..mode = mode;
        final session = controller.session;
        final lastPage = session.page;
        expect(session.atBookEnd, isTrue);
        expect(session.progress?.finished, isFalse);

        _swipeDuringTurn(controller, release: false);
        await tester.pump();
        expect(confirmations, 0, reason: '拖动未松手不打开确认页');
        controller.cancelDrag();
        await tester.pumpAndSettle();
        expect(confirmations, 0);
        expect(controller.phase, PageTurnPhase.idle);

        _swipeDuringTurn(controller, complete: false);
        await tester.pumpAndSettle();
        expect(confirmations, 0, reason: '未达到位移门槛不打开确认页');

        _swipeDuringTurn(controller, release: false);
        _releaseCurl(controller, rtl ? -400 : 400);
        await tester.pumpAndSettle();
        expect(confirmations, 0, reason: '反向甩动不打开确认页');
        expect(session.page, same(lastPage));

        controller.request(false);
        await tester.pumpAndSettle();
        expect(session.progress?.pageIndex, 0);
        expect(confirmations, 0);
        controller.request(true);
        await tester.pumpAndSettle();
        expect(session.page, same(lastPage));
        expect(session.progress?.finished, isFalse);
        expect(confirmations, 0, reason: '刚到末页不能自动打开确认页');

        _swipeDuringTurn(controller, release: false);
        expect(confirmations, 0);
        controller.endDrag(DragEndDetails());
        await tester.pumpAndSettle();
        expect(confirmations, 1);
        expect(controller.phase, PageTurnPhase.idle);
        expect(session.page, same(lastPage));
        expect(session.progress?.finished, isFalse);

        controller.request(true);
        await tester.pumpAndSettle();
        expect(confirmations, 2, reason: '退出确认页后仍可从正文末页再次进入');
        expect(session.page, same(lastPage));
        await session.flushProgress();
        expect((await session.store.load(session.bookId))?.finished, isFalse);
      });
    }
  }

  testWidgets('前进探测多个尾部空章后打开确认页，保留最后正文页', (tester) async {
    final source = ProgressiveTestSource(counts: [2, 0, 0], heldSpines: {});
    addTearDown(source.cancelPendingLayouts);
    var confirmations = 0;
    final controller = await _controller(
      tester,
      source: source,
      autoFinish: false,
      onBookEnd: () => confirmations += 1,
    );
    final lastPage = controller.session.page;
    expect(controller.session.atBookEnd, isFalse);

    controller.request(true);
    await tester.pumpAndSettle();
    expect(confirmations, 1);
    expect(controller.session.atBookEnd, isTrue);
    expect(controller.session.page, same(lastPage));
    expect(controller.session.progress?.finished, isFalse);
    expect(controller.session.pageTurns, 0);
  });

  testWidgets('渐进分页尚未结束时等待后续页，取消后补全也不误开确认页', (tester) async {
    final source = ProgressiveTestSource(counts: [2], heldSpines: {0});
    addTearDown(source.cancelPendingLayouts);
    var confirmations = 0;
    final controller = await _controller(
      tester,
      source: source,
      initialPage: 0,
      autoFinish: false,
      onBookEnd: () => confirmations += 1,
    );
    final firstPage = controller.session.page;
    expect(controller.session.atBookEnd, isFalse);
    _swipeDuringTurn(controller, release: false);
    await tester.pump();
    expect(controller.phase, PageTurnPhase.preparing);
    expect(confirmations, 0);

    controller.cancelDrag();
    source.complete(0);
    await tester.pumpAndSettle();
    expect(controller.session.page, same(firstPage));
    expect(confirmations, 0);
    controller.request(true);
    await tester.pumpAndSettle();
    expect(controller.session.progress?.pageIndex, 1);
    expect(controller.session.progress?.finished, isFalse);
    expect(confirmations, 0);
    controller.request(true);
    await tester.pumpAndSettle();
    expect(confirmations, 1);
    await controller.session.flushProgress();
  });

  testWidgets('3D 起手以平移检测器的采样锚点为准', (tester) async {
    final controller = await _curlController(tester);
    controller.pointerDown(const ui.Offset(310, 100));
    controller.beginDrag(
      DragStartDetails(localPosition: const ui.Offset(282, 240)),
    );
    _move(controller, const ui.Offset(265, 240));
    await tester.pump();
    await tester.pump();
    expect(controller.horizontal, isTrue);
    expect(controller.grab, const ui.Offset(320, 240));
    controller.cancel();
  });

  testWidgets('无动画目标激活前取消后可继续翻页', (tester) async {
    final controller = (await _controller(tester))..mode = PageTurnMode.none;
    final cancelled = _requestWithActivationCancellation(controller);
    await tester.pumpAndSettle();

    expect(cancelled.isCompleted, isTrue);
    expect(controller.phase, PageTurnPhase.idle);
    expect(controller.turn, isNull);
    expect(controller.originImage, isNull);
    expect(controller.targetImage, isNull);
    expect(controller.session.page!.pageIndex, 1);
    expect(controller.session.pageTurns, 0);

    controller.request(true);
    await tester.pumpAndSettle();
    expect(controller.phase, PageTurnPhase.idle);
    expect(controller.session.page!.pageIndex, 2);
    expect(controller.session.pageTurns, 1);
    await controller.session.flushProgress();
  });

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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.session.progress!.pageIndex, 1);
    expect(controller.phase, PageTurnPhase.settling);
    await tester.pumpAndSettle();

    expect(controller.phase, PageTurnPhase.idle);
    expect(controller.session.progress!.pageIndex, 2);
    await controller.session.flushProgress();
  });

  for (final mode in <PageTurnMode>[
    PageTurnMode.cover,
    PageTurnMode.coverStack,
    PageTurnMode.simulationBessel,
    PageTurnMode.slideHorizontal,
  ]) {
    testWidgets('${mode.label}点击翻页在 280 毫秒内完成且中途不提交', (tester) async {
      final controller = await _controller(tester);
      controller
        ..mode = mode
        ..request(true);
      await tester.pump();
      expect(controller.phase, PageTurnPhase.settling);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 240));
      expect(controller.phase, PageTurnPhase.settling);
      expect(controller.session.progress!.pageIndex, 1);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump(const Duration(milliseconds: 1));
      expect(controller.phase, PageTurnPhase.idle);
      expect(controller.session.progress!.pageIndex, 2);
      await controller.session.flushProgress();
    });

    testWidgets('${mode.label}短拖回退在 160 毫秒内结束且不翻页', (tester) async {
      final controller = (await _controller(tester))..mode = mode;
      _swipeDuringTurn(controller, complete: false, release: false);
      await tester.pump();
      controller.endDrag(DragEndDetails());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      expect(controller.phase, PageTurnPhase.idle);
      expect(controller.session.progress!.pageIndex, 1);
      expect(controller.session.pageTurns, 0);
    });

    for (final rtl in [false, true]) {
      testWidgets('${mode.label} ${rtl ? 'RTL' : 'LTR'}同位移快甩比慢拖更早落页', (
        tester,
      ) async {
        final slow = (await _controller(tester, rtl: rtl))..mode = mode;
        final fast = (await _controller(tester, rtl: rtl))..mode = mode;
        await _startDrag(tester, slow);
        await _startDrag(tester, fast);
        _move(slow, const ui.Offset(160, 380));
        _move(fast, const ui.Offset(160, 380));
        final displayed = fast.progress;
        slow.endDrag(DragEndDetails());
        _releaseCurl(fast, rtl ? 3200 : -3200);
        expect(fast.progress, displayed, reason: '松手不能跳过已显示的纸面位置');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 180));
        expect(fast.phase, PageTurnPhase.idle);
        expect(fast.session.progress!.pageIndex, 2);
        expect(slow.phase, PageTurnPhase.settling);
        expect(slow.session.progress!.pageIndex, 1);
        await tester.pumpAndSettle();
        expect(slow.session.progress!.pageIndex, 2);
        await fast.session.flushProgress();
        await slow.session.flushProgress();
      });
    }
  }

  for (final rtl in [false, true]) {
    for (final next in [false, true]) {
      testWidgets('3D $rtl/$next 仅中央 5% 从侧边起卷且按起卷侧镜像', (tester) async {
        final controller = await _curlController(tester, rtl: rtl);
        for (final y in <double>[160, 227.9, 228, 240, 252, 252.1, 320]) {
          final x = next ? 220.0 : 100.0;
          await _startCurlDrag(
            tester,
            controller,
            ui.Offset(next ? 310 : 10, y),
            ui.Offset(x, y + 60),
          );
          await tester.pump(const Duration(milliseconds: 100));

          final center = y >= 228 && y <= 252;
          final grabY = center ? 240.0 : (y < 240 ? 0.0 : 480.0);
          final canonicalX = next ? x : 320 - x;
          expect(controller.next, next);
          expect(controller.horizontal, center);
          expect(controller.grab, ui.Offset(320, grabY));
          expect(
            controller.point,
            ui.Offset(canonicalX, center ? 240 : y + 60),
          );
          expect(controller.progress, (320 - canonicalX) / 640);
          expect(controller.curl3dGeometry!.touch, controller.point);
          _move(controller, ui.Offset(x + (next ? -30 : 30), 520));
          expect(controller.horizontal, center);
          expect(controller.grab, ui.Offset(320, grabY));
          expect(controller.point!.dy, center ? 240 : 520);
          controller.cancel();
          expect(controller.session.pageTurns, 0);
        }
      });

      testWidgets('3D $rtl/$next 拖回起卷侧及越界保留本轮网格，新轮不复用', (tester) async {
        final controller = await _curlController(tester, rtl: rtl);
        await _startCurlDrag(
          tester,
          controller,
          ui.Offset(next ? 310 : 10, 240),
          ui.Offset(next ? 220 : 100, 240),
        );
        await tester.pump(const Duration(milliseconds: 100));
        final folded = controller.curl3dGeometry!;
        expect(folded.active, isTrue);
        for (final x in <double>[320, 350]) {
          _move(controller, ui.Offset(next ? x : 320 - x, 240));
          expect(controller.point, ui.Offset(x, 240));
          expect(controller.curl3dGeometry, same(folded));
        }
        controller.cancel();
        expect(controller.curl3dGeometry, isNull);
        controller.request(true);
        final initial = controller.curl3dGeometry!;
        expect(initial.active, isFalse);
        expect(initial, isNot(same(folded)));
        expect(
          initial.pointAt(const ui.Offset(300, 200)).position,
          const ui.Offset(300, 200),
        );
        controller.cancel();
        await tester.pumpAndSettle();
        expect(controller.session.pageTurns, 0);
      });

      testWidgets('3D $rtl/$next 普通松手严格超过 10 dp、快扫按释放方向', (tester) async {
        const cases = [
          (distance: 10.0, velocity: 0.0, backtrack: false, complete: false),
          (distance: 11.0, velocity: 0.0, backtrack: false, complete: true),
          (distance: 11.0, velocity: 0.0, backtrack: true, complete: true),
          (distance: 40.0, velocity: -19.0, backtrack: false, complete: true),
          (distance: 11.0, velocity: 20.0, backtrack: false, complete: true),
          (distance: 40.0, velocity: -20.0, backtrack: false, complete: false),
          (distance: 0.0, velocity: 0.0, backtrack: true, complete: true),
        ];
        for (final sample in cases) {
          final controller = await _curlController(tester, rtl: rtl);
          final sign = next ? -1.0 : 1.0;
          final down = ui.Offset(next ? 310 : 10, 240);
          await _startCurlDrag(
            tester,
            controller,
            down,
            down.translate(sign * (sample.backtrack ? 40 : sample.distance), 0),
          );
          await tester.pump(const Duration(milliseconds: 100));
          if (sample.backtrack) {
            _move(controller, down.translate(sign * sample.distance, 0));
          }
          final velocity = sample.velocity * sign * (rtl ? -1 : 1);
          _releaseCurl(controller, velocity);
          _releaseCurl(controller, -velocity);
          await tester.pumpAndSettle();

          expect(
            controller.session.page!.pageIndex,
            sample.complete ? (next ? 2 : 0) : 1,
          );
          expect(controller.session.pageTurns, sample.complete ? 1 : 0);
          await controller.session.flushProgress();
        }
      });
    }
  }

  testWidgets('3D 起手按屏高计算时长并使用 smoothstep', (tester) async {
    final controller = await _curlController(tester);
    await _startCurlDrag(
      tester,
      controller,
      const ui.Offset(310, 240),
      const ui.Offset(280, 300),
    );
    expect(controller.point, const ui.Offset(320, 240));
    await tester.pump(const Duration(milliseconds: 5));
    expect(controller.point!.dx, closeTo(315.84, 0.001));
    _move(controller, const ui.Offset(270, 40));
    expect(controller.point!.dx, closeTo(315.84, 0.001));
    await tester.pump(const Duration(milliseconds: 19));
    expect(controller.point!.dx, greaterThan(280));
    await tester.pump(const Duration(milliseconds: 1));
    expect(controller.point, const ui.Offset(270, 240));
    controller.cancel();
  });

  testWidgets('3D 起手上限 100 ms、完成收尾按距离计算时长', (tester) async {
    final controller = await _curlController(tester);
    await _startCurlDrag(
      tester,
      controller,
      const ui.Offset(310, 240),
      const ui.Offset(160, 240),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.point, const ui.Offset(240, 240));
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.point, const ui.Offset(160, 240));

    controller.endDrag(DragEndDetails());
    expect(controller.point, const ui.Offset(160, 240));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(controller.point, const ui.Offset(-80, 240));
    expect(controller.session.pageTurns, 0);
    await tester.pump(const Duration(milliseconds: 149));
    expect(controller.phase, PageTurnPhase.settling);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(controller.session.page!.pageIndex, 2);
    expect(controller.session.pageTurns, 1);
    await controller.session.flushProgress();
  });

  for (final milliseconds in [16, 120]) {
    testWidgets('3D 起卷结束后手指已移动，${milliseconds}ms 帧间隔连续接续', (tester) async {
      final gate = Completer<void>();
      final controller = await _curlController(
        tester,
        targetImageGate: gate.future,
      );
      await _startCurlDrag(
        tester,
        controller,
        const ui.Offset(310, 240),
        const ui.Offset(240, 240),
      );
      await tester.pump(const Duration(milliseconds: 40));
      final before = controller.point!;
      _move(controller, const ui.Offset(100, 240));
      await tester.pump(const Duration(milliseconds: 10));
      expect((controller.point! - before).distance, lessThanOrEqualTo(16.01));
      expect(controller.point!.dx, greaterThan(100));
      await tester.pump();
      final catchingUp = controller.point!;
      await tester.pump(Duration(milliseconds: milliseconds));
      expect(
        (controller.point! - catchingUp).distance,
        lessThanOrEqualTo(16.01),
      );
      expect(controller.phase, PageTurnPhase.preparing);
      gate.complete();
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(controller.point, const ui.Offset(100, 240));
      expect(controller.targetOpacity, 1);
      controller.cancel();
    });
  }

  testWidgets('3D 起手中松手从已显示位置接续并以 150 ms 回弹', (tester) async {
    final controller = await _curlController(tester);
    await _startCurlDrag(
      tester,
      controller,
      const ui.Offset(310, 240),
      const ui.Offset(160, 240),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.point, const ui.Offset(240, 240));
    _releaseCurl(controller, 20);
    expect(controller.point, const ui.Offset(240, 240));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(controller.point, const ui.Offset(280, 240));
    await tester.pump(const Duration(milliseconds: 74));
    expect(controller.phase, PageTurnPhase.settling);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(controller.session.page!.pageIndex, 1);
    expect(controller.session.pageTurns, 0);
  });

  testWidgets('3D 冷目标等待时冻结松手显示点，就绪后连续收尾', (tester) async {
    final gate = Completer<void>();
    final controller = await _curlController(
      tester,
      targetImageGate: gate.future,
    );
    await _startCurlDrag(
      tester,
      controller,
      const ui.Offset(310, 80),
      const ui.Offset(150, 120),
    );
    await tester.pump(const Duration(milliseconds: 25));
    final displayed = controller.point;
    controller.endDrag(DragEndDetails());
    expect(controller.point, displayed);
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.phase, PageTurnPhase.preparing);
    expect(controller.point, displayed);
    gate.complete();
    await tester.pump();
    expect(controller.phase, PageTurnPhase.settling);
    expect(controller.point, displayed);
    await tester.pumpAndSettle();
    expect(controller.session.page!.pageIndex, 2);
    await controller.session.flushProgress();
  });

  testWidgets('3D 冷目标只渐入透明度，手指不参与渐入插值', (tester) async {
    final gate = Completer<void>();
    final controller = await _curlController(
      tester,
      targetImageGate: gate.future,
    );
    await _startCurlDrag(
      tester,
      controller,
      const ui.Offset(310, 240),
      const ui.Offset(220, 300),
    );
    await tester.pump(const Duration(milliseconds: 100));
    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(controller.targetOpacity, 0);
    _move(controller, const ui.Offset(150, 50));
    expect(controller.point, const ui.Offset(150, 240));
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.targetOpacity, closeTo(0.5, 0.001));
    _move(controller, const ui.Offset(140, 500));
    expect(controller.point, const ui.Offset(140, 240));
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.targetOpacity, 1);
    controller.cancel();
  });

  for (final rtl in [false, true]) {
    for (final next in [false, true]) {
      testWidgets('3D $rtl 点击${next ? '前进等待 50' : '后退等待 75'} ms 并复用按下纵坐标', (
        tester,
      ) async {
        final controller = await _curlController(tester, rtl: rtl);
        controller.pointerDown(const ui.Offset(290, 80));
        controller.request(next);
        await tester.pump();
        await tester.pump();
        expect(controller.grab, const ui.Offset(320, 0));
        expect(controller.phase, PageTurnPhase.dragging);
        final delay = next ? 50 : 75;
        await tester.pump(Duration(milliseconds: delay - 1));
        final displayed = controller.point;
        expect(displayed!.dx, inExclusiveRange(0, 320));
        expect(controller.progress, greaterThan(0));
        expect(controller.phase, PageTurnPhase.dragging);
        await tester.pump(const Duration(milliseconds: 1));
        expect(controller.phase, PageTurnPhase.settling);
        expect(controller.point, displayed);
        await tester.pumpAndSettle();
        expect(controller.session.page!.pageIndex, next ? 2 : 0);
        await controller.session.flushProgress();
      });
    }
  }

  testWidgets('3D 尚未松手时不覆盖触点，冷准备松手后接住后续点击', (tester) async {
    final gate = Completer<void>();
    final controller = await _curlController(
      tester,
      targetImageGate: gate.future,
      pageCount: 5,
    );
    controller.request(true);
    await tester.pump();
    expect(controller.phase, PageTurnPhase.preparing);
    controller.request(false);
    _swipeDuringTurn(controller, next: false);
    await tester.pump(const Duration(milliseconds: 50));
    final displayed = controller.point;
    controller.request(true);
    gate.complete();
    await tester.pump();
    expect(controller.phase, PageTurnPhase.settling);
    expect(controller.point, displayed);
    await tester.pumpAndSettle();
    expect(controller.session.page!.pageIndex, 3);
    expect(controller.session.pageTurns, 2);
    await controller.session.flushProgress();
  });

  for (final releaseBeforeFinish in [false, true]) {
    testWidgets(
      '3D 收尾期间开始的滑动在${releaseBeforeFinish ? '上一页结束前' : '上一页结束后'}松手均保留',
      (tester) async {
        final controller = await _curlController(tester, pageCount: 5);
        controller.request(true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 75));
        expect(controller.phase, PageTurnPhase.settling);
        _swipeDuringTurn(controller, release: releaseBeforeFinish);
        await tester.pumpAndSettle();
        if (!releaseBeforeFinish) {
          expect(controller.phase, PageTurnPhase.dragging);
          _releaseCurl(controller, 0);
          await tester.pumpAndSettle();
        }
        expect(controller.phase, PageTurnPhase.idle);
        expect(controller.session.page!.pageIndex, 3);
        expect(controller.session.pageTurns, 2);
        await controller.session.flushProgress();
      },
    );
  }

  testWidgets('慢准备只记录一次耗时阶段，取消后可重新翻页', (tester) async {
    final events = <String>[];
    ReaderUiDiagnostics.onEvent = (event, _) => events.add(event);
    addTearDown(() => ReaderUiDiagnostics.onEvent = null);
    final gate = Completer<void>();
    final controller = await _curlController(
      tester,
      targetImageGate: gate.future,
    );
    controller.request(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(events.where((event) => event == 'turn_prepare_slow').length, 1);
    controller.cancel();
    gate.complete();
    await tester.pumpAndSettle();
    controller.request(true);
    await tester.pumpAndSettle();
    expect(controller.phase, PageTurnPhase.idle);
    expect(events, containsAll(['turn_cancel', 'turn_ready', 'turn_finish']));
    expect(controller.session.pageTurns, 1);
    await controller.session.flushProgress();
  });

  testWidgets('翻页日志记录动画长帧间隔，下一次翻页重新统计', (tester) async {
    final completed = <Map<String, Object?>>[];
    final previous = ReaderUiDiagnostics.onEvent;
    ReaderUiDiagnostics.onEvent = (event, fields) {
      if (event == 'turn_finish') completed.add(fields);
    };
    addTearDown(() => ReaderUiDiagnostics.onEvent = previous);
    final controller = await _curlController(tester, pageCount: 5);
    controller.request(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 64));
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(completed.single['max_frame_gap_us'], greaterThanOrEqualTo(64000));
    expect(completed.single['committed'], isTrue);
    expect(completed.single, containsPair('origin_us', isNonNegative));
    expect(completed.single, containsPair('target_us', isNonNegative));
    controller.request(true);
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(completed, hasLength(2));
    expect(completed.last['max_frame_gap_us'], lessThanOrEqualTo(16000));
    await controller.session.flushProgress();
  });

  testWidgets('3D 按住原拖动时拒绝的新手势不覆盖原触点', (tester) async {
    final controller = await _curlController(tester, pageCount: 5);
    await _startCurlDrag(
      tester,
      controller,
      const ui.Offset(310, 240),
      const ui.Offset(220, 240),
    );
    await tester.pump(const Duration(milliseconds: 100));
    controller.request(false);
    _swipeDuringTurn(controller, next: false);
    expect(controller.phase, PageTurnPhase.dragging);
    expect(controller.point, const ui.Offset(220, 240));
    _releaseCurl(controller, 0);
    await tester.pumpAndSettle();
    expect(controller.session.page!.pageIndex, 2);
    expect(controller.session.pageTurns, 1);
    await controller.session.flushProgress();
  });

  testWidgets('3D 起手首次同步通知中取消后不再回写', (tester) async {
    final controller = await _curlController(tester);
    var cancelled = false;
    controller.addListener(() {
      if (cancelled || controller.originImage == null) return;
      cancelled = true;
      controller.cancel();
    });
    controller.request(true);
    await tester.pumpAndSettle();
    expect(cancelled, isTrue);
    expect(controller.phase, PageTurnPhase.idle);
    expect(controller.point, isNull);
    expect(controller.progress, 0);
    expect(controller.session.pageTurns, 0);
  });

  testWidgets('3D 取消后的旧点击等待不能覆盖新 token', (tester) async {
    final controller = await _curlController(tester);
    controller.request(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 25));
    controller.cancel();
    controller.request(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 25));
    expect(controller.phase, PageTurnPhase.dragging);
    expect(controller.next, isFalse);
    expect(controller.session.pageTurns, 0);
    controller.cancel();
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.phase, PageTurnPhase.idle);
    expect(controller.session.page!.pageIndex, 1);
  });

  testWidgets('3D dispose 取消点击等待及起手回写', (tester) async {
    final image = _image();
    final session = ReaderSession(
      source: _Source(3),
      store: MemoryReaderProgressStore(),
      bookId: 'dispose-curl',
    );
    await session.open();
    final controller =
        PageTurnController(
            session: session,
            vsync: tester,
            acquireImage: (_) async => image,
          )
          ..size = const ui.Size(320, 480)
          ..mode = PageTurnMode.simulation3d;
    addTearDown(() {
      session.dispose();
      image.dispose();
    });
    controller.request(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 25));
    controller.dispose();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(session.pageTurns, 0);
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
    if (mode == PageTurnMode.simulationBessel || mode.is3d) {
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
          if (!forward.active) {
            expect(backward.active, isFalse);
            break;
          }
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
            if (!controller.active) break;
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
