import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/paging/page_turn_controller.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/reader_session.dart';

class _Source implements ReaderChapterSource {
  @override
  int get chapterCount => 1;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => [
    for (var page = 0; page < 3; page++)
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
}) async {
  final store = MemoryReaderProgressStore();
  await store.save('curl', const ReaderProgress(spineIndex: 0, pageIndex: 1));
  final session = ReaderSession(
    source: _Source(),
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
          acquireImage: (_) async => image,
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

void main() {
  for (final rtl in [false, true]) {
    testWidgets('${rtl ? 'RTL' : 'LTR'} 回拖时抓取点沿移动方向平滑返回', (tester) async {
      final controller = await _controller(tester, rtl: rtl);
      await _startDrag(tester, controller);

      _move(controller, const ui.Offset(280, 410));
      await tester.pump(const Duration(milliseconds: 16));

      expect(controller.point!.dx, inExclusiveRange(220, 280));
      expect(controller.point!.dy, inExclusiveRange(380, 410));
      expect(controller.session.progress!.pageIndex, 1);
      controller.cancel();
      expect(controller.phase, PageTurnPhase.idle);
      expect(controller.session.progress!.pageIndex, 1);
    });
  }

  testWidgets('横坐标不变时纵向拖动仍逐帧移动', (tester) async {
    final controller = await _controller(tester);
    await _startDrag(tester, controller);

    _move(controller, const ui.Offset(220, 300));
    await tester.pump(const Duration(milliseconds: 16));

    expect(controller.point!.dx, 220);
    expect(controller.point!.dy, inExclusiveRange(300, 380));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.point, const ui.Offset(220, 300));
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
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.point!.dy, inExclusiveRange(10, 100));
    _move(controller, const ui.Offset(220, -100));
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.point!.dy, closeTo(0.1, 0.001));
  });

  testWidgets('上一页回拖保持水平折痕并平滑移动', (tester) async {
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
    expect(controller.point, const ui.Offset(100, 240));
    _move(controller, const ui.Offset(40, 200));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.point!.dx, inExclusiveRange(40, 100));
    expect(controller.point!.dy, 240);
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
    await tester.pumpAndSettle();

    expect(controller.phase, PageTurnPhase.idle);
    expect(controller.session.progress!.pageIndex, 2);
    await controller.session.flushProgress();
  });
}
