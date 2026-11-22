import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/paging/page_turn_controller.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

import '../support/progressive_source.dart';

final _animation = find.byKey(const ValueKey('page-turn-animation'));

ProgressiveTestSource _source() =>
    ProgressiveTestSource(counts: const [3], heldSpines: const {});

Future<ReaderSession> _open() async {
  final session = ReaderSession(
    bookId: '新版翻页',
    source: _source(),
    store: MemoryReaderProgressStore(),
  );
  await session.open();
  return session;
}

Widget _window(
  ReaderSession session, {
  PageTurnMode mode = PageTurnMode.simulation3dNext,
  ReaderPageImagesPreparer? prepare,
}) => MaterialApp(
  home: Center(
    child: SizedBox(
      width: 320,
      height: 480,
      child: ListenableBuilder(
        listenable: session,
        builder: (_, _) => PageTurnView(
          session: session,
          mode: mode,
          revision: 1,
          preload: false,
          preparePageImages: prepare,
          paperColor: Colors.white,
          paperBuilder: (page, _) => ColoredBox(
            color: page.pageIndex == 0
                ? const Color(0xff00aa00)
                : const Color(0xff0000ff),
          ),
        ),
      ),
    ),
  ),
);

PageTurnController _controller(WidgetTester tester) =>
    tester.state<PageTurnViewState>(find.byType(PageTurnView)).controller;

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var frame = 0; frame < 40 && !done(); frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  expect(done(), isTrue, reason: '翻页窗口应在 40 帧内到达待检查状态');
}

Future<Color> _exposedEdge(WidgetTester tester) async {
  final boundary =
      tester.renderObject(_animation).parent! as RenderRepaintBoundary;
  final pixel = await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final offset = 4 * ((image.height ~/ 2) * image.width + image.width - 3);
      return Color.fromARGB(
        bytes.getUint8(offset + 3),
        bytes.getUint8(offset),
        bytes.getUint8(offset + 1),
        bytes.getUint8(offset + 2),
      );
    } finally {
      image.dispose();
    }
  });
  return pixel!;
}

void main() {
  testWidgets('3D（新版）冷目标复用原页露底，渐入目标后释放才提交', (tester) async {
    final session = await _open();
    final imageGate = Completer<void>();
    await tester.pumpWidget(
      _window(
        session,
        prepare: (page) async {
          if (page.pageIndex == 1) await imageGate.future;
        },
      ),
    );
    final controller = _controller(tester);
    const down = Offset(315, 240);
    const moved = Offset(100, 240);
    controller.pointerDown(down);
    controller.beginDrag(DragStartDetails(localPosition: down));
    controller.updateDrag(
      DragUpdateDetails(globalPosition: moved, delta: moved - down),
    );
    await _pumpUntil(tester, () => _animation.evaluate().isNotEmpty);
    expect(controller.phase, PageTurnPhase.preparing);
    expect(controller.targetImage, isNull);
    final cold = await _exposedEdge(tester);
    expect(cold.r, lessThan(0.05));
    expect(cold.g, greaterThan(0.5));
    expect(cold.b, lessThan(0.05));

    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    controller.updateDrag(
      DragUpdateDetails(
        globalPosition: const Offset(99, 240),
        localPosition: const Offset(99, 240),
        delta: const Offset(-1, 0),
      ),
    );
    await tester.pump();
    imageGate.complete();
    await _pumpUntil(tester, () => controller.phase == PageTurnPhase.dragging);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final middle = await _exposedEdge(tester);
    expect(
      middle.b - middle.r,
      inExclusiveRange(0.05, 0.95),
      reason: '混合色 $middle，渐入进度 ${controller.targetOpacity}',
    );
    await tester.pump(const Duration(milliseconds: 120));
    final ready = await _exposedEdge(tester);
    expect(ready.b - ready.r, greaterThan(0.95));
    expect(session.page!.pageIndex, 0);
    controller.endDrag(DragEndDetails(primaryVelocity: 0));
    await _pumpUntil(tester, () => !controller.active);
    expect(session.page!.pageIndex, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });

  testWidgets('3D（新版）活动期间拒绝排队，切换模式撤销本次翻页', (tester) async {
    final session = await _open();
    await tester.pumpWidget(_window(session));
    final controller = _controller(tester)..request(true);
    await _pumpUntil(tester, () => controller.phase == PageTurnPhase.settling);
    controller.request(true);
    await tester.pumpWidget(_window(session, mode: PageTurnMode.none));
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.active, isFalse);
    expect(session.page!.pageIndex, 0);
    expect(_animation, findsNothing);
    controller.request(true);
    await tester.pump();
    expect(session.page!.pageIndex, 1);
    expect(controller.active, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });

  for (final inkMode in [false, true]) {
    final setting = inkMode ? '墨水屏' : '系统减少动画';
    testWidgets('3D（新版）启用$setting时无动画落页，关闭后恢复新版', (tester) async {
      tester.view
        ..devicePixelRatio = 2.8125
        ..physicalSize = const Size(1080, 2400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final source = _source();
      final store = MemoryReaderProgressStore();
      Widget reader(bool enabled) => MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: enabled && !inkMode),
            child: ReaderPage(
              source: source,
              store: store,
              bookId: '新版无动画',
              pageTurnMode: PageTurnMode.simulation3dNext,
              inkMode: enabled && inkMode,
            ),
          ),
        ),
      );
      await tester.pumpWidget(reader(true));
      await _pumpUntil(
        tester,
        () => find.byType(PageTurnView).evaluate().isNotEmpty,
      );
      final controller = _controller(tester);
      expect(controller.mode, PageTurnMode.none);
      final body = tester.getRect(find.byType(ReaderView));
      await tester.tapAt(body.centerRight - const Offset(16, 0));
      await tester.pump();
      expect(controller.session.page!.pageIndex, 1);
      expect(controller.active, isFalse);
      expect(_animation, findsNothing);

      await tester.pumpWidget(reader(false));
      expect(_controller(tester).mode, PageTurnMode.simulation3dNext);
      await _pumpUntil(tester, () => !controller.session.loading);
      await tester.pumpAndSettle();
      expect(controller.session.page!.pageIndex, 1);
      await tester.tapAt(body.centerRight - const Offset(16, 0));
      await _pumpUntil(tester, () => _animation.evaluate().isNotEmpty);
      expect(controller.session.page!.pageIndex, 1);
      await _pumpUntil(tester, () => !controller.active);
      expect(controller.session.page!.pageIndex, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
