import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/paging/page_turn_controller.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_core/source/chapter_source.dart';

class _Source implements ReaderChapterSource {
  final nextChapter = Completer<List<PageContent>>();
  @override
  int get chapterCount => 2;
  static PageContent page(int spine, int index) => PageContent(
    spineIndex: spine,
    pageIndex: index,
    slices: const [],
    usedHeight: 0,
    pageHeight: 480,
    topPadding: 0,
  );
  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async =>
      spineIndex == 0 ? [page(0, 0)] : nextChapter.future;
}

Future<PageTurnController> _open(
  WidgetTester tester,
  PageTurnMode mode, {
  required _Source source,
  bool missingTarget = false,
}) async {
  final session = ReaderSession(
    source: source,
    store: MemoryReaderProgressStore(),
    bookId: '跨章手势',
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
          acquireImage: (page) async =>
              missingTarget && page.spineIndex == 1 ? null : image,
        )
        ..size = const ui.Size(320, 480)
        ..mode = mode;
  addTearDown(() {
    controller.dispose();
    session.dispose();
    image.dispose();
  });
  return controller;
}

void _move(PageTurnController controller, double x) => controller.updateDrag(
  DragUpdateDetails(
    localPosition: ui.Offset(x, 360),
    globalPosition: ui.Offset(x, 360),
  ),
);
void _start(PageTurnController controller) {
  const down = ui.Offset(310, 360);
  controller.pointerDown(down);
  controller.beginDrag(DragStartDetails(localPosition: down));
  _move(controller, 240);
}

void main() {
  for (final mode in PageTurnMode.values.where(
    (mode) => mode != PageTurnMode.none && mode != PageTurnMode.scroll,
  )) {
    testWidgets('${mode.label} 冷跨章准备期间先响应原页且松手后保留收尾', (tester) async {
      final source = _Source();
      final controller = await _open(tester, mode, source: source);
      _start(controller);
      await tester.pump();
      if (mode.is3d) {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(controller.phase, PageTurnPhase.preparing);
      expect(controller.originImage, isNotNull, reason: '下一章未完成时原页已可绘制');
      expect(controller.progress, greaterThan(0));
      final before = controller.progress;
      _move(controller, 100);
      expect(controller.progress, greaterThanOrEqualTo(before));
      controller.endDrag(DragEndDetails());
      await tester.pump(const Duration(seconds: 1));
      expect(controller.session.page!.spineIndex, 0);
      source.nextChapter.complete([_Source.page(1, 0)]);
      await tester.pump();
      expect(controller.phase, PageTurnPhase.settling);
      final start = controller.progress;
      expect(start, lessThan(.5), reason: '从已显示的起卷位置接续，避免就绪时瞬移');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.progress, greaterThan(start));
      expect(controller.progress, lessThan(1));
      expect(controller.session.page!.spineIndex, 0);
      await tester.pumpAndSettle();
      expect(controller.session.page!.spineIndex, 1);
      await controller.session.flushProgress();
    });
    testWidgets('${mode.label} 冷跨章短拖回退不必等下一章加载', (tester) async {
      final source = _Source();
      final controller = await _open(tester, mode, source: source);
      _start(controller);
      _move(controller, mode.is3d ? 301 : 295);
      await tester.pump();
      controller.endDrag(DragEndDetails());
      await tester.pumpAndSettle();
      expect(controller.active, isFalse);
      expect(controller.session.page!.spineIndex, 0);
      source.nextChapter.complete([_Source.page(1, 0)]);
      await tester.pump();
      expect(controller.turn, isNull);
      expect(controller.targetImage, isNull);
      expect(controller.originImage, isNull);
      expect(controller.session.pageTurns, 0);
    });
    testWidgets(
      '${mode.label} ${mode.is3d ? '动画中拒绝第二次拖动' : '连续滑动在收尾后接管触点'}',
      (tester) async {
        final source = _Source()
          ..nextChapter.complete([_Source.page(1, 0), _Source.page(1, 1)]);
        final controller = await _open(tester, mode, source: source);
        controller.request(true);
        await tester.pump();
        _start(controller);
        _move(controller, 100);
        await tester.pumpAndSettle();
        expect(controller.session.page!.spineIndex, 1);
        if (mode.is3d) {
          expect(controller.phase, PageTurnPhase.idle);
          _move(controller, 80);
          controller.endDrag(DragEndDetails());
          await tester.pumpAndSettle();
          expect(controller.session.page!.pageIndex, 0);
          expect(controller.session.pageTurns, 1);
          await controller.session.flushProgress();
          return;
        }
        expect(
          controller.phase,
          PageTurnPhase.dragging,
          reason: '第二笔仍按住时应直接跟手',
        );
        _move(controller, 80);
        expect(controller.progress, greaterThan(0));
        controller.endDrag(DragEndDetails());
        await tester.pumpAndSettle();
        expect(controller.session.page!.pageIndex, 1);
        expect(controller.session.pageTurns, 2);
        await controller.session.flushProgress();
      },
    );
  }
  testWidgets('仿真冷跨章大幅回拖零速度松手立即回弹', (tester) async {
    final source = _Source();
    final controller = await _open(
      tester,
      PageTurnMode.simulationBessel,
      source: source,
    );
    _start(controller);
    await tester.pump();
    _move(controller, 100);
    _move(controller, 250);
    controller.endDrag(DragEndDetails());
    await tester.pumpAndSettle();
    expect(controller.active, isFalse);
    expect(controller.session.pageTurns, 0);
    source.nextChapter.complete([_Source.page(1, 0)]);
    await tester.pumpAndSettle();
    expect(controller.session.page!.spineIndex, 0);
    expect(controller.session.pageTurns, 0);
  });

  testWidgets('目标快照失败保留原页，不能直接闪到下一页', (tester) async {
    final source = _Source()..nextChapter.complete([_Source.page(1, 0)]);
    final controller = await _open(
      tester,
      PageTurnMode.cover,
      source: source,
      missingTarget: true,
    );
    controller.request(true);
    await tester.pumpAndSettle();
    expect(controller.session.page!.spineIndex, 0);
    expect(controller.active, isFalse);
    expect(controller.session.pageTurns, 0);
  });

  testWidgets('目标尚未排版时外部跳转也能使旧手势失效', (tester) async {
    final source = _Source();
    final controller = await _open(tester, PageTurnMode.cover, source: source);
    _start(controller);
    await tester.pump();
    await controller.session.jumpToChapter(0);
    expect(controller.active, isFalse);
    source.nextChapter.complete([_Source.page(1, 0)]);
    await tester.pumpAndSettle();
    expect(controller.session.page!.spineIndex, 0);
    expect(controller.targetImage, isNull);
    await controller.session.flushProgress();
  });
}
