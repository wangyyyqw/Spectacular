import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/paging/page_turn_controller.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_painter.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_ui_diagnostics.dart';
import 'package:reader_core/source/chapter_source.dart';

class _Source implements ReaderChapterSource {
  final pages = List.generate(
    9,
    (index) => PageContent(
      spineIndex: 0,
      pageIndex: index,
      slices: const [],
      usedHeight: 0,
      pageHeight: 400,
      topPadding: 0,
    ),
  );

  @override
  int get chapterCount => 1;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => pages;
}

Future<ReaderSession> _open() async {
  final store = MemoryReaderProgressStore();
  await store.save('窗口', const ReaderProgress(spineIndex: 0, pageIndex: 3));
  final session = ReaderSession(source: _Source(), store: store, bookId: '窗口');
  await session.open();
  return session;
}

Widget _view(
  ReaderSession session,
  GlobalKey<PageTurnViewState> key,
  ReaderPageImagesPreparer prepare,
  PageTurnMode mode, {
  ReaderPaperBuilder? paperBuilder,
  bool preload = true,
}) => MaterialApp(
  home: ListenableBuilder(
    listenable: session,
    builder: (_, _) => PageTurnView(
      key: key,
      session: session,
      mode: mode,
      preload: preload,
      revision: 1,
      paperBuilder:
          paperBuilder ??
          (page, size) =>
              ColoredBox(color: Colors.white, child: Text('${page.pageIndex}')),
      paperColor: Colors.white,
      preparePageImages: prepare,
    ),
  ),
);

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 35,
}) async {
  for (var frame = 0; frame < maxFrames && !ready(); frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(ready(), isTrue, reason: '应到达待检查的捕获阶段');
}

Future<List<int>> _firstPixel(ui.Image image) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return List<int>.generate(4, data.getUint8);
}

void main() {
  testWidgets('3D 视口复用资源，缓存失效和退出释放对应着色器', (tester) async {
    final session = await _open();
    addTearDown(session.dispose);
    final key = GlobalKey<PageTurnViewState>();
    await tester.pumpWidget(
      _view(session, key, (_) async {}, PageTurnMode.simulation3d),
    );
    await tester.pumpAndSettle();
    final controller = key.currentState!.controller;
    Future<PageTurnPainter> begin() async {
      controller.pointerDown(const Offset(790, 300));
      controller.beginDrag(
        DragStartDetails(localPosition: const Offset(790, 300)),
      );
      controller.updateDrag(
        DragUpdateDetails(
          globalPosition: const Offset(500, 300),
          localPosition: const Offset(500, 300),
        ),
      );
      await tester.pumpAndSettle();
      return tester
              .widget<CustomPaint>(
                find.byKey(const ValueKey('page-turn-animation')),
              )
              .painter!
          as PageTurnPainter;
    }

    final resources = (await begin()).curl3dResources!;
    final sheet = resources.debugSheetShader!;
    final shadow = resources.debugShadowShader!;
    controller.cancel();
    await tester.pumpAndSettle();
    expect(sheet.debugDisposed, isFalse, reason: '普通收尾仍保留当前窗口的绘制资源');
    key.currentState!.releaseCachedBitmaps();
    await tester.pump();
    expect(sheet.debugDisposed, isTrue);
    expect(resources.debugSheetShader, isNull);
    expect(shadow.debugDisposed, isFalse);
    key.currentState!.resumeWarmup();
    await tester.pumpAndSettle();
    expect((await begin()).curl3dResources, same(resources));
    final replacement = resources.debugSheetShader!;
    expect(replacement, isNot(same(sheet)));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(replacement.debugDisposed, isTrue);
    expect(shadow.debugDisposed, isTrue);
  });

  testWidgets('3D 冷目标提交后立即回翻复用刚读过的原页', (tester) async {
    final session = await _open();
    addTearDown(session.dispose);
    final key = GlobalKey<PageTurnViewState>();
    final gate = Completer<void>();
    var blocked = false;
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    await tester.pumpWidget(
      _view(
        session,
        key,
        (_) => blocked ? gate.future : Future<void>.value(),
        PageTurnMode.simulation3d,
        preload: false,
      ),
    );
    final controller = key.currentState!.controller;
    controller.request(true);
    await _pumpUntil(tester, () => !controller.active, maxFrames: 90);
    expect(session.page!.pageIndex, 4);
    expect(key.currentState!.snapshotCount, 2);
    blocked = true;
    controller.request(false);
    await tester.pump();
    expect(controller.targetImage, isNotNull, reason: '回翻命中原页快照，不等图片重新准备');
    gate.complete();
    await tester.pumpAndSettle();
    expect(session.page!.pageIndex, 3);
    await session.flushProgress();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('3D 连续翻页的短空闲直接补齐第二邻页，不在缓存命中处多等帧', (tester) async {
    final session = await _open();
    addTearDown(session.dispose);
    final key = GlobalKey<PageTurnViewState>();
    final prepared = <int>[];
    await tester.pumpWidget(
      _view(session, key, (page) async {
        prepared.add(page.pageIndex);
      }, PageTurnMode.simulation3d),
    );
    await tester.pumpAndSettle();
    expect(key.currentState!.snapshotCount, 5);
    final controller = key.currentState!.controller;
    controller.request(true);
    await _pumpUntil(tester, () => !controller.active, maxFrames: 90);
    expect(session.page!.pageIndex, 4);
    prepared.clear();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 16));
    expect(prepared, [6], reason: '近邻命中后应立即补新窗口的 +2 页');
    expect(key.currentState!.snapshotCount, 5);
    await session.flushProgress();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('取消后迟到的目标图片不能在下一次手势中插队截图', (tester) async {
    final session = await _open();
    addTearDown(session.dispose);
    final key = GlobalKey<PageTurnViewState>();
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    await tester.pumpWidget(
      _view(session, key, (page) {
        return page.pageIndex == 4 ? gate.future : Future<void>.value();
      }, PageTurnMode.simulation3d),
    );
    final controller = key.currentState!.controller;
    controller.request(true);
    await _pumpUntil(tester, () => controller.originImage != null);
    controller.cancel();
    controller.beginDrag(
      DragStartDetails(localPosition: const Offset(10, 300)),
    );
    controller.updateDrag(
      DragUpdateDetails(
        globalPosition: const Offset(300, 300),
        localPosition: const Offset(300, 300),
      ),
    );
    await _pumpUntil(tester, () => controller.phase == PageTurnPhase.dragging);
    expect(key.currentState!.snapshotCount, 2);
    gate.complete();
    await tester.pump(const Duration(milliseconds: 200));
    expect(key.currentState!.snapshotCount, 2);
    expect(controller.turn!.target.pageIndex, 2);
    controller.cancel();
    await tester.pumpAndSettle();
    expect(key.currentState!.snapshotCount, 5);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('后台图片准备失败后，实际翻页可重新请求并提交', (tester) async {
    final session = await _open();
    addTearDown(session.dispose);
    final key = GlobalKey<PageTurnViewState>();
    var requests = 0;
    await tester.pumpWidget(
      _view(session, key, (page) async {
        if (page.pageIndex == 4 && ++requests == 1) {
          throw StateError('首次解码失败');
        }
      }, PageTurnMode.simulation3d),
    );
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(tester.takeException(), isNull);
    key.currentState!.controller.request(true);
    await tester.pumpAndSettle();
    expect(session.page!.pageIndex, 4);
    expect(requests, greaterThanOrEqualTo(2));
    expect(tester.takeException(), isNull);
    await session.flushProgress();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('等待捕获期间往返导航仍把邻页画面缓存到正确页', (tester) async {
    final session = await _open();
    addTearDown(session.dispose);
    final gate = Completer<void>();
    final prepared = <int>[];
    final key = GlobalKey<PageTurnViewState>();
    await tester.pumpWidget(
      _view(
        session,
        key,
        (page) async {
          prepared.add(page.pageIndex);
          if (page.pageIndex == 4) await gate.future;
        },
        PageTurnMode.simulationBessel,
        paperBuilder: (page, size) => ColoredBox(
          color: page.pageIndex == 4
              ? const Color(0xFF0000FF)
              : const Color(0xFFFF0000),
        ),
      ),
    );
    await _pumpUntil(tester, () => prepared.contains(4));
    await session.next();
    await tester.pump();
    gate.complete();
    await tester.idle();
    await session.previous();
    await tester.pump();
    final controller = key.currentState!.controller;
    controller.request(true);
    await _pumpUntil(tester, () => controller.targetImage != null);
    final pixel = await tester.runAsync(
      () => _firstPixel(controller.targetImage!),
    );
    expect(controller.turn!.target.pageIndex, 4);
    expect(pixel, [0, 0, 255, 255], reason: '目标快照必须来自页4，不能误捕获当前页3');
    await session.flushProgress();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final mode in [
    PageTurnMode.cover,
    PageTurnMode.coverStack,
    PageTurnMode.simulationBessel,
    PageTurnMode.simulation3d,
    PageTurnMode.slideHorizontal,
  ]) {
    testWidgets('${mode.label} 成功提交仅补窗口差集，回退不移动窗口', (tester) async {
      final session = await _open();
      addTearDown(session.dispose);
      final key = GlobalKey<PageTurnViewState>();
      final prepared = <int>[];
      await tester.pumpWidget(
        _view(session, key, (page) async {
          prepared.add(page.pageIndex);
        }, mode),
      );
      await tester.pumpAndSettle();
      expect(prepared, [3, 4, 2, 5, 1]);
      final controller = key.currentState!.controller;
      controller.pointerDown(const Offset(790, 300));
      controller.beginDrag(
        DragStartDetails(localPosition: const Offset(790, 300)),
      );
      controller.updateDrag(
        DragUpdateDetails(
          globalPosition: const Offset(770, 300),
          localPosition: const Offset(770, 300),
        ),
      );
      await tester.pump();
      final velocity = mode == PageTurnMode.simulation3d ? 20.0 : 0.0;
      controller.endDrag(
        DragEndDetails(
          primaryVelocity: velocity,
          velocity: Velocity(pixelsPerSecond: Offset(velocity, 0)),
        ),
      );
      await tester.pumpAndSettle();
      expect(session.page!.pageIndex, 3);
      expect(key.currentState!.snapshotCount, 5);
      expect(prepared.where((index) => index != 3), [4, 2, 5, 1]);
      prepared.clear();
      controller.request(true);
      await tester.pumpAndSettle();
      expect(session.page!.pageIndex, 4);
      expect(key.currentState!.snapshotCount, 5);
      expect(prepared.where((index) => index != 4), [6]);
      prepared.clear();
      controller.request(false);
      await tester.pumpAndSettle();
      expect(session.page!.pageIndex, 3);
      expect(key.currentState!.snapshotCount, 5);
      expect(prepared.where((index) => index != 3), [1]);
      await session.flushProgress();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('窗口外的延迟准备不阻塞翻页且完成后不回写缓存', (tester) async {
    final session = await _open();
    addTearDown(session.dispose);
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final key = GlobalKey<PageTurnViewState>();
    final prepared = <int>[];
    await tester.pumpWidget(
      _view(session, key, (page) {
        prepared.add(page.pageIndex);
        return page.pageIndex == 1 ? gate.future : Future<void>.value();
      }, PageTurnMode.cover),
    );
    await tester.pumpAndSettle();
    expect(key.currentState!.snapshotCount, 4);
    expect(prepared, [3, 4, 2, 5, 1]);
    key.currentState!.controller.request(true);
    await tester.pumpAndSettle();
    expect(session.page!.pageIndex, 4);
    expect(key.currentState!.snapshotCount, 5);
    gate.complete();
    await tester.pumpAndSettle();
    expect(key.currentState!.snapshotCount, 5);
    expect(prepared.where((index) => index == 1).length, 1);
    await session.flushProgress();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('目标预热复用同一准备任务，后台截图推迟到收尾后', (tester) async {
    final session = await _open();
    addTearDown(session.dispose);
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final prepared = <int>[];
    final cacheEvents = <Map<String, Object?>>[];
    final previous = ReaderUiDiagnostics.onEvent;
    ReaderUiDiagnostics.onEvent = (event, fields) {
      if (event == 'turn.cache') cacheEvents.add(fields);
    };
    addTearDown(() => ReaderUiDiagnostics.onEvent = previous);
    final key = GlobalKey<PageTurnViewState>();
    await tester.pumpWidget(
      _view(session, key, (page) {
        prepared.add(page.pageIndex);
        return page.pageIndex == 4 ? gate.future : Future<void>.value();
      }, PageTurnMode.cover),
    );
    await _pumpUntil(tester, () => prepared.contains(4));
    expect(prepared, [3, 4]);
    final controller = key.currentState!.controller;
    controller.pointerDown(const Offset(790, 300));
    controller.beginDrag(
      DragStartDetails(localPosition: const Offset(790, 300)),
    );
    controller.updateDrag(
      DragUpdateDetails(
        globalPosition: const Offset(500, 300),
        localPosition: const Offset(500, 300),
      ),
    );
    await tester.pump();
    expect(controller.phase, PageTurnPhase.preparing);
    expect(prepared.where((index) => index == 4).length, 1);
    expect(
      cacheEvents.any(
        (event) =>
            event['page'] == 4 &&
            event['shared'] == true &&
            event['urgent'] == true,
      ),
      isTrue,
      reason: '前台目标升级同一后台准备任务',
    );
    gate.complete();
    await tester.pumpAndSettle();
    expect(controller.phase, PageTurnPhase.dragging);
    expect(
      key.currentState!.isPresentingSnapshot(controller.turn!.target.content),
      isTrue,
      reason: '迟到目标图片仍触发状态维护并接住收尾纸面',
    );
    expect(session.page!.pageIndex, 3);
    expect(key.currentState!.snapshotCount, 2);
    expect(prepared, [3, 4], reason: '手势期间不启动后方页面的后台图片准备');
    controller.cancel();
    await tester.pumpAndSettle();
    expect(key.currentState!.snapshotCount, 5);
    expect(prepared.where((index) => index == 2).length, 1);
    expect(prepared, containsAll([3, 4, 2, 5, 1]));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
