import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/paging/page_turn_controller.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_session.dart';

PageContent _page(int spine) => PageContent(
  spineIndex: spine,
  pageIndex: 0,
  slices: const [],
  usedHeight: 0,
  pageHeight: 480,
  topPadding: 0,
);

class _Source implements ReaderChapterSource {
  final loads = <int>[];
  Completer<List<PageContent>>? gate;

  @override
  int get chapterCount => 5;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    loads.add(spineIndex);
    if (spineIndex == 3 && gate != null) return gate!.future;
    return [_page(spineIndex)];
  }
}

Future<ReaderSession> _open(_Source source) async {
  final store = MemoryReaderProgressStore();
  await store.save('准备诊断', const ReaderProgress(spineIndex: 2, pageIndex: 0));
  final session = ReaderSession(source: source, store: store, bookId: '准备诊断');
  await session.open();
  return session;
}

void _move(PageTurnController controller, double x) => controller.updateDrag(
  DragUpdateDetails(
    localPosition: Offset(x, 360),
    globalPosition: Offset(x, 360),
  ),
);

void _start(PageTurnController controller) {
  controller.pointerDown(const Offset(310, 360));
  controller.beginDrag(DragStartDetails(localPosition: const Offset(310, 360)));
  _move(controller, 240);
}

Widget _view(
  ReaderSession session,
  GlobalKey<PageTurnViewState> key,
  ReaderPageImagesPreparer prepare,
) => MaterialApp(
  home: Center(
    child: SizedBox(
      width: 320,
      height: 480,
      child: PageTurnView(
        key: key,
        session: session,
        mode: PageTurnMode.simulationBessel,
        revision: 1,
        preparePageImages: prepare,
        paperColor: Colors.white,
        paperBuilder: (page, size) => ColoredBox(
          color: Colors.white,
          child: Text('章节 ${page.spineIndex}'),
        ),
      ),
    ),
  ),
);

void main() {
  for (final mode in [
    PageTurnMode.simulationBessel,
    PageTurnMode.simulation3d,
    PageTurnMode.cover,
    PageTurnMode.coverStack,
    PageTurnMode.slideHorizontal,
  ]) {
    for (final releaseDuringCatchUp in [false, true]) {
      testWidgets('${mode.label}冷目标接续，接续时松手=$releaseDuringCatchUp', (
        tester,
      ) async {
        final source = _Source()..gate = Completer<List<PageContent>>();
        final session = await _open(source);
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
              ..size = const Size(320, 480)
              ..mode = mode;
        _start(controller);
        await tester.pump();
        _move(controller, 100);
        expect(controller.phase, PageTurnPhase.preparing);
        expect(controller.progress, 0.08);
        expect(controller.targetImage, isNull);
        final origin = controller.originImage;
        final beforeX = controller.point!.dx;
        final bessel = mode == PageTurnMode.simulationBessel;
        final curl3d = mode == PageTurnMode.simulation3d;
        final expected = bessel
            ? 220 / 640
            : curl3d
            ? 210 / (320 * 0.9)
            : 210 / 320;
        if (bessel) expect(beforeX, closeTo(268.8, 0.001));
        if (curl3d) expect(beforeX, 110);
        tester.binding.scheduleFrame();
        await tester.pump(const Duration(milliseconds: 16));
        source.gate!.complete([_page(3)]);
        await tester.pump();
        expect(controller.phase, PageTurnPhase.dragging);
        expect(controller.originImage, same(origin));
        expect(controller.targetImage, same(image));
        expect(controller.progress, 0.08);
        expect(controller.point!.dx, beforeX);
        expect(controller.targetOpacity, 0);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(controller.progress, inExclusiveRange(0.08, expected));
        if (bessel) {
          expect(controller.point!.dx, inExclusiveRange(100, beforeX));
        }
        if (curl3d) expect(controller.point!.dx, beforeX);
        if (releaseDuringCatchUp) {
          final beforeRelease = controller.progress;
          final pointBeforeRelease = controller.point;
          controller.endDrag(
            DragEndDetails(
              primaryVelocity: -400,
              velocity: const Velocity(pixelsPerSecond: Offset(-400, 0)),
            ),
          );
          expect(controller.progress, beforeRelease);
          expect(controller.point, pointBeforeRelease);
          await tester.pumpAndSettle();
          expect(session.page!.spineIndex, 3);
          controller.dispose();
          image.dispose();
          session.dispose();
          return;
        }
        _move(controller, 80);
        await tester.pump(const Duration(milliseconds: 60));
        expect(
          controller.progress,
          closeTo(
            bessel
                ? 240 / 640
                : curl3d
                ? 230 / (320 * 0.9)
                : 230 / 320,
            0.00001,
          ),
        );
        if (bessel) expect(controller.point!.dx, 80);
        if (curl3d) expect(controller.point!.dx, 90);
        expect(controller.targetOpacity, 1);
        debugPrint(
          '诊断 ${mode.label}：进度 0.08 -> ${controller.progress}；'
          '触点横坐标 $beforeX -> ${controller.point!.dx}；原页快照未替换',
        );
        controller.dispose();
        image.dispose();
        session.dispose();
      });
    }
  }

  testWidgets('诊断：完整预热±2后翻页复用快照但仍经过准备阶段', (tester) async {
    final source = _Source();
    final session = await _open(source);
    final key = GlobalKey<PageTurnViewState>();
    final prepared = <int>[];
    await tester.pumpWidget(
      _view(session, key, (page) async {
        prepared.add(page.spineIndex);
      }),
    );
    await tester.pumpAndSettle();
    expect(prepared, [2, 3, 1, 4, 0]);
    expect(key.currentState!.snapshotCount, 5);
    final controller = key.currentState!.controller;
    final frames = <String>[];
    controller.addListener(() {
      frames.add('${controller.phase.name}:${controller.progress}');
    });
    final beforeLoads = List<int>.of(source.loads);
    _start(controller);
    await tester.pump();
    expect(controller.phase, PageTurnPhase.dragging);
    expect(controller.targetImage, isNotNull);
    expect(controller.progress, closeTo(0.125, 0.00001));
    expect(controller.targetOpacity, 1, reason: '暖缓存不引入接续动画');
    expect(prepared, [2, 3, 1, 4, 0], reason: '没有再次解码或截图准备，命中快照');
    expect(source.loads, beforeLoads, reason: '没有再次加载章节');
    expect(frames.any((frame) => frame.startsWith('preparing:')), isTrue);
    debugPrint('诊断 暖缓存：预热顺序 $prepared；快照5张；状态 $frames；无新增准备/加载');
    controller.cancel();
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });

  testWidgets('目标准备未完成时保持原页，完成后连续接续', (tester) async {
    final session = await _open(_Source());
    final key = GlobalKey<PageTurnViewState>();
    final gate = Completer<void>();
    final prepared = <int>[];
    await tester.pumpWidget(
      _view(session, key, (page) async {
        prepared.add(page.spineIndex);
        if (page.spineIndex == 3) await gate.future;
      }),
    );
    await tester.pumpAndSettle();
    expect(prepared, [2, 3]);
    expect(key.currentState!.snapshotCount, 1);
    final controller = key.currentState!.controller;
    _start(controller);
    await tester.pump();
    _move(controller, 100);
    expect(controller.phase, PageTurnPhase.preparing);
    expect(controller.originImage, isNotNull);
    expect(controller.targetImage, isNull);
    expect(controller.progress, 0.08);
    gate.complete();
    await tester.pumpAndSettle();
    expect(controller.phase, PageTurnPhase.dragging);
    expect(controller.point!.dx, 100);
    expect(controller.progress, closeTo(0.34375, 0.00001));
    expect(prepared.where((spine) => spine == 3), hasLength(1),
        reason: '翻页复用正在准备的目标，不重复解码');
    debugPrint(
      '诊断 复用预热：原先仅1张快照；目标就绪前进度0.08，'
      '就绪后${controller.progress}；图片准备调用 $prepared',
    );
    controller.cancel();
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });
}
