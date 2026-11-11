import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/paging/page_turn_controller.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_core/source/chapter_source.dart';

const _size = Size(320, 480);
const _frame = Duration(milliseconds: 16);

class _Source implements ReaderChapterSource {
  final pages = List.generate(
    5,
    (spine) => PageContent(
      spineIndex: spine,
      pageIndex: 0,
      slices: const [],
      usedHeight: 0,
      pageHeight: _size.height,
      topPadding: 0,
    ),
  );

  @override
  int get chapterCount => pages.length;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => [
    pages[spineIndex],
  ];
}

ui.Image _image() {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.teal, BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(32, 32);
  picture.dispose();
  return image;
}

Widget _paper(PageContent page, ui.Image image) => ColoredBox(
  color: Colors.white,
  child: Column(
    children: [
      Text('图文页 ${page.spineIndex}', style: const TextStyle(fontSize: 12)),
      SizedBox(
        height: 160,
        child: Row(
          children: List.generate(
            3,
            (_) => Expanded(child: RawImage(image: image)),
          ),
        ),
      ),
      Table(
        border: TableBorder.all(),
        children: List.generate(
          4,
          (row) => TableRow(
            children: List.generate(
              3,
              (column) => Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  '单元格 $row/$column',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  ),
);

void _move(PageTurnController controller, double x, {bool? fromRight}) {
  final position = Offset(
    (fromRight ?? controller.fromRight) ? x : _size.width - x,
    360,
  );
  controller.updateDrag(
    DragUpdateDetails(localPosition: position, globalPosition: position),
  );
}

Future<void> _activateCold(
  WidgetTester tester,
  PageTurnController controller,
  Completer<void> gate,
  double targetX,
  bool fromRight,
) async {
  final down = Offset(fromRight ? 310 : 10, 360);
  controller.pointerDown(down);
  controller.beginDrag(DragStartDetails(localPosition: down));
  _move(controller, 240, fromRight: fromRight);
  for (var frame = 0; frame < 6 && controller.originImage == null; frame++) {
    await tester.pump();
  }
  _move(controller, targetX);
  await tester.pump(const Duration(seconds: 1));
  expect(controller.phase, PageTurnPhase.preparing);
  expect(controller.progress, 0.08);
  expect(controller.targetImage, isNull);
  gate.complete();
  for (var frame = 0; frame < 6 && controller.targetImage == null; frame++) {
    await tester.pump();
  }
  await tester.pump();
  expect(controller.phase, PageTurnPhase.dragging);
  expect(controller.progress, 0.08);
  expect(controller.targetOpacity, 0);
  expect(find.byKey(const ValueKey('page-turn-animation')), findsOneWidget);
}

Future<PageTurnController> _coldTurn(
  WidgetTester tester, {
  PageTurnMode mode = PageTurnMode.simulationBessel,
  bool next = true,
  bool rtl = false,
  double targetX = 100,
}) async {
  final gate = Completer<void>();
  final session = await _open();
  final image = _image();
  final key = GlobalKey<PageTurnViewState>();
  _disposePaper(tester, key, session, image, gate);
  await _showPaper(
    tester,
    PageTurnView(
      key: key,
      session: session,
      mode: mode,
      rtl: rtl,
      revision: 1,
      preload: false,
      paperColor: Colors.white,
      paperBuilder: (page, _) => _paper(page, image),
      preparePageImages: (page) async {
        if (page.spineIndex == (next ? 3 : 1)) await gate.future;
      },
    ),
  );
  final controller = key.currentState!.controller;
  await _activateCold(tester, controller, gate, targetX, next != rtl);
  return controller;
}

Future<ReaderSession> _open() async {
  final store = MemoryReaderProgressStore();
  await store.save('卷角接续', const ReaderProgress(spineIndex: 2, pageIndex: 0));
  final session = ReaderSession(
    source: _Source(),
    store: store,
    bookId: '卷角接续',
  );
  await session.open();
  return session;
}

void _disposePaper(
  WidgetTester tester,
  GlobalKey<PageTurnViewState> key,
  ReaderSession session,
  ui.Image image,
  Completer<void> gate,
) => addTearDown(() async {
  key.currentState?.controller.cancel();
  if (!gate.isCompleted) gate.complete();
  await tester.pumpWidget(const SizedBox.shrink());
  session.dispose();
  image.dispose();
});

Future<void> _showPaper(WidgetTester tester, PageTurnView view) =>
    tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox.fromSize(size: _size, child: view),
        ),
      ),
    );

void _expectStep(Offset before, Offset after) {
  expect(
    (after - before).distance,
    lessThanOrEqualTo(_size.width * 0.05 + 0.01),
  );
}

void main() {
  for (final milliseconds in [16, 33, 50, 120, 500]) {
    testWidgets('图文目标就绪后帧间隔 ${milliseconds}ms 不跳到触点', (tester) async {
      final controller = await _coldTurn(tester);
      try {
        final before = controller.point!;
        final crease = controller.besselGeometry!.j;
        await tester.pump(Duration(milliseconds: milliseconds));
        _expectStep(before, controller.point!);
        expect(controller.point!.dx, inExclusiveRange(100, before.dx));
        expect(
          (controller.besselGeometry!.j - crease).distance,
          lessThan(_size.height * 0.05),
          reason: '输入点与实际绘制的折痕都必须连续接续',
        );
        await tester.pumpAndSettle(_frame);
        expect(controller.point, const Offset(100, 360));
        expect(controller.targetOpacity, 1);
      } finally {
        controller.cancel();
      }
    });
  }

  testWidgets('长等待积累更远距离仍限制首帧位移', (tester) async {
    final controller = await _coldTurn(tester, targetX: 20);
    try {
      final before = controller.point!;
      await tester.pump(_frame);
      _expectStep(before, controller.point!);
      expect(controller.point!.dx, greaterThan(20));
      await tester.pumpAndSettle(_frame);
      expect(controller.point, const Offset(20, 360));
    } finally {
      controller.cancel();
    }
  });

  testWidgets('追赶中途持续出现长短帧仍连续到达触点', (tester) async {
    final controller = await _coldTurn(tester);
    try {
      for (final milliseconds in [16, 8, 33, 50, 120, 16, 500, 8, 16]) {
        final before = controller.point!;
        await tester.pump(Duration(milliseconds: milliseconds));
        _expectStep(before, controller.point!);
        expect(controller.point!.dx, inInclusiveRange(100, before.dx));
      }
      await tester.pumpAndSettle(_frame);
      expect(controller.point, const Offset(100, 360));
    } finally {
      controller.cancel();
    }
  });

  testWidgets('淡入结束后的密集手势与反向拖动从显示点继续追赶', (tester) async {
    final controller = await _coldTurn(tester);
    try {
      await tester.pump(const Duration(milliseconds: 120));
      expect(controller.targetOpacity, 1);
      final before = controller.point!;
      for (final x in [20.0, 0.0, 40.0, 60.0]) {
        _move(controller, x);
      }
      await tester.pump();
      expect(controller.point, before, reason: '同一帧内的手势不能多次推进补偿');
      await tester.pump(_frame);
      _expectStep(before, controller.point!);
      final reversing = controller.point!;
      _move(controller, 300);
      expect(controller.point, reversing);
      await tester.pump(_frame);
      _expectStep(reversing, controller.point!);
      expect(controller.point!.dx, greaterThan(reversing.dx));
      await tester.pumpAndSettle(_frame);
      expect(controller.point, const Offset(300, 360));
      _move(controller, 280);
      expect(controller.point, const Offset(280, 360), reason: '追赶结束后立即跟手');
    } finally {
      controller.cancel();
    }
  });

  testWidgets('丢帧后追赶期间松手从当前显示点收尾并提交', (tester) async {
    final controller = await _coldTurn(tester);
    try {
      await tester.pump(const Duration(milliseconds: 120));
      final displayed = controller.point;
      controller.endDrag(
        DragEndDetails(
          primaryVelocity: -400,
          velocity: const Velocity(pixelsPerSecond: Offset(-400, 0)),
        ),
      );
      expect(controller.point, displayed);
      await tester.pump();
      expect(controller.point, displayed);
      await tester.pumpAndSettle(_frame);
      expect(controller.phase, PageTurnPhase.idle);
      expect(controller.session.page!.spineIndex, 3);
      await controller.session.flushProgress();
    } finally {
      controller.cancel();
    }
  });

  for (final (next, rtl) in [(false, false), (true, true), (false, true)]) {
    testWidgets('${rtl ? 'RTL' : 'LTR'} ${next ? '下一页' : '上一页'}冷目标连续接续', (
      tester,
    ) async {
      final controller = await _coldTurn(tester, next: next, rtl: rtl);
      try {
        final before = controller.point!;
        await tester.pump(const Duration(milliseconds: 120));
        _expectStep(before, controller.point!);
        await tester.pumpAndSettle(_frame);
        expect(controller.point, const Offset(100, 360));
      } finally {
        controller.cancel();
      }
    });
  }

  for (final mode in [
    PageTurnMode.cover,
    PageTurnMode.coverStack,
    PageTurnMode.slideHorizontal,
  ]) {
    testWidgets('${mode.label}共享冷目标接续在丢帧后仍限制位移', (tester) async {
      final controller = await _coldTurn(tester, mode: mode);
      try {
        final before = controller.progress;
        await tester.pump(const Duration(milliseconds: 120));
        expect(controller.progress, inExclusiveRange(before, before + 0.051));
        await tester.pumpAndSettle(_frame);
        expect(controller.progress, closeTo(210 / 320, 0.00001));
      } finally {
        controller.cancel();
      }
    });
  }
}
