import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/source/chapter_source.dart';
import 'package:reader_ui/paging/duokan_curl_shader.dart';
import 'package:reader_ui/paging/page_turn_controller.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_painter.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

// 魅族 20 的全屏阅读视口：1080×2400、450 dpi。
const _size = ui.Size(384, 853.3333333333334);
const _ratio = 2.8125;
const _paper = ui.Color(0xfff4eddb);

class _Source implements ReaderChapterSource {
  @override
  int get chapterCount => 1;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async => [
    for (var page = 0; page < 5; page++)
      PageContent(
        spineIndex: spineIndex,
        pageIndex: page,
        slices: const [],
        usedHeight: 0,
        pageHeight: _size.height,
        topPadding: 0,
      ),
  ];
}

class _Modes {
  _Modes(this.old, this.fresh);

  final PageTurnController old;
  final PageTurnController fresh;
  Iterable<PageTurnController> get both => [old, fresh];
}

Future<_Modes> _modes(
  WidgetTester tester, {
  bool rtl = false,
  Completer<void>? targetGate,
  (ui.Image, ui.Image)? images,
}) async {
  final origin = images?.$1 ?? _image(_paper);
  final target = images?.$2 ?? origin;
  if (images == null) addTearDown(origin.dispose);
  final controllers = <PageTurnController>[];
  for (final mode in [
    PageTurnMode.simulation3d,
    PageTurnMode.simulation3dNext,
  ]) {
    final store = MemoryReaderProgressStore();
    await store.save(mode.id, ReaderProgress(spineIndex: 0, pageIndex: 2));
    final session = ReaderSession(
      source: _Source(),
      store: store,
      bookId: mode.id,
    );
    await session.open();
    final controller =
        PageTurnController(
            session: session,
            vsync: tester,
            acquireImage: (page) async {
              if (page.pageIndex == 2) return origin;
              await targetGate?.future;
              return target;
            },
          )
          ..size = _size
          ..mode = mode
          ..rtl = rtl;
    controllers.add(controller);
    addTearDown(() {
      controller.dispose();
      session.dispose();
    });
  }
  return _Modes(controllers[0], controllers[1]);
}

void _same(_Modes modes) {
  final old = modes.old;
  final fresh = modes.fresh;
  expect(fresh.phase, old.phase, reason: '翻页阶段');
  expect(fresh.progress, old.progress, reason: '进度元数据');
  expect(fresh.grab, old.grab, reason: '固定抓点');
  expect(fresh.point, old.point, reason: '本帧显示触点');
  expect(fresh.top, old.top, reason: '上角起卷');
  expect(fresh.horizontal, old.horizontal, reason: '中央 5% 起卷方式');
  expect(fresh.next, old.next, reason: '前后方向');
  expect(fresh.fromRight, old.fromRight, reason: '实际起卷侧');
  expect(fresh.targetOpacity, old.targetOpacity, reason: '冷目标渐入');
  expect(fresh.originImage != null, old.originImage != null);
  expect(fresh.targetImage != null, old.targetImage != null);
  expect(fresh.session.page?.spineIndex, old.session.page?.spineIndex);
  expect(fresh.session.page?.pageIndex, old.session.page?.pageIndex);
  expect(fresh.session.pageTurns, old.session.pageTurns, reason: '提交次数');
}

Future<void> _pump(
  WidgetTester tester,
  _Modes modes, [
  Duration duration = Duration.zero,
]) async {
  await tester.pump(duration);
  _same(modes);
}

Future<void> _advance(
  WidgetTester tester,
  _Modes modes,
  int milliseconds,
) async {
  for (var remaining = milliseconds; remaining > 0;) {
    final step = remaining > 16 ? 16 : remaining;
    await _pump(tester, modes, Duration(milliseconds: step));
    remaining -= step;
  }
}

Future<void> _finish(WidgetTester tester, _Modes modes) async {
  for (var frame = 0; modes.old.active && frame < 80; frame++) {
    await _pump(tester, modes, const Duration(milliseconds: 16));
  }
  expect(modes.old.phase, PageTurnPhase.idle);
  expect(modes.fresh.phase, PageTurnPhase.idle);
  for (final controller in modes.both) {
    await controller.session.flushProgress();
  }
}

ui.Offset _physical(ui.Offset point, bool fromRight) =>
    ui.Offset(fromRight ? point.dx : _size.width - point.dx, point.dy);

Future<void> _start(
  WidgetTester tester,
  _Modes modes,
  bool next,
  ui.Offset down,
  ui.Offset touch,
) async {
  for (final controller in modes.both) {
    final side = next != controller.rtl;
    final position = _physical(down, side);
    controller.pointerDown(position);
    controller.beginDrag(DragStartDetails(localPosition: position));
    final latest = _physical(touch, side);
    controller.updateDrag(
      DragUpdateDetails(globalPosition: latest, localPosition: latest),
    );
  }
  await _pump(tester, modes);
  await _pump(tester, modes);
}

void _move(_Modes modes, ui.Offset point) {
  for (final controller in modes.both) {
    final position = _physical(point, controller.fromRight);
    controller.updateDrag(
      DragUpdateDetails(globalPosition: position, localPosition: position),
    );
  }
  _same(modes);
}

void _release(_Modes modes, [double towardVelocity = 0]) {
  for (final controller in modes.both) {
    final velocity = controller.fromRight ? -towardVelocity : towardVelocity;
    controller.endDrag(
      DragEndDetails(
        primaryVelocity: velocity,
        velocity: Velocity(pixelsPerSecond: ui.Offset(velocity, 0)),
      ),
    );
  }
  _same(modes);
}

void _intrude(_Modes modes) {
  for (final controller in modes.both) {
    controller.request(!controller.next);
    final down = _physical(const ui.Offset(374, 240), controller.fromRight);
    final touch = _physical(const ui.Offset(80, 240), controller.fromRight);
    controller.pointerDown(down);
    controller.beginDrag(DragStartDetails(localPosition: down));
    controller.updateDrag(
      DragUpdateDetails(globalPosition: touch, localPosition: touch),
    );
    controller.endDrag(DragEndDetails());
  }
  _same(modes);
}

ui.Image _image(ui.Color color) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(_ratio);
  canvas.drawRect(ui.Offset.zero & _size, ui.Paint()..color = color);
  for (var row = 0; row < 12; row++) {
    canvas.drawRect(
      ui.Rect.fromLTWH(24, 50 + row * 58, 200 + row * 3, 3),
      ui.Paint()..color = const ui.Color(0xff123456),
    );
  }
  canvas.drawRect(
    const ui.Rect.fromLTWH(260, 570, 70, 110),
    ui.Paint()..color = const ui.Color(0xff84a7c3),
  );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(1080, 2400);
  picture.dispose();
  return image;
}

Future<Uint8List> _render(PageTurnController controller) async {
  final recorder = ui.PictureRecorder();
  PageTurnPainter(
    controller,
    paperColor: _paper,
  ).paint(ui.Canvas(recorder)..scale(_ratio), _size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(1080, 2400);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

String? _firstMismatch(Uint8List old, Uint8List fresh) {
  for (var index = 0; index < old.length; index++) {
    if (old[index] != fresh[index]) {
      final pixel = index ~/ 4;
      return '像素 (${pixel % 1080},${pixel ~/ 1080}) 通道 ${index % 4}：'
          '旧版 ${old[index]}、新版 ${fresh[index]}';
    }
  }
  return null;
}

Future<PageTurnController> _reader(
  WidgetTester tester,
  PageTurnMode mode,
) async {
  final store = MemoryReaderProgressStore();
  await store.save(mode.id, ReaderProgress(spineIndex: 0, pageIndex: 2));
  await tester.pumpWidget(
    MaterialApp(
      home: ReaderPage(
        key: UniqueKey(),
        source: _Source(),
        store: store,
        bookId: mode.id,
        pageTurnMode: mode,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.state<PageTurnViewState>(find.byType(PageTurnView)).controller;
}

Future<List<Object>> _pointerFrames(
  WidgetTester tester,
  PageTurnController controller,
  double angle,
) async {
  const frame = Duration(microseconds: 8333);
  final states = <Object>[];
  void record() => states.add((
    controller.phase,
    controller.progress,
    controller.grab,
    controller.point,
    controller.horizontal,
    controller.top,
    controller.targetOpacity,
    controller.session.page?.pageIndex,
  ));
  final down = ui.Offset(_size.width * .94, _size.height * .15);
  final gesture = await tester.startGesture(down);
  for (var move = 1; move <= 16; move++) {
    await gesture.moveTo(
      down +
          ui.Offset(-move * 10.0, move * 10 * math.tan(angle * math.pi / 180)),
    );
    await tester.pump(frame);
    record();
  }
  await gesture.up();
  for (var tick = 0; tick < 60; tick++) {
    await tester.pump(frame);
    record();
  }
  return states;
}

void main() {
  testWidgets('正式阅读页的 49° 与 51° 触摸识别及每帧状态一致', (tester) async {
    tester.view
      ..devicePixelRatio = _ratio
      ..physicalSize = const ui.Size(1080, 2400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await DuokanCurlShader.load();
    for (final angle in [49.0, 51.0]) {
      final traces = <List<Object>>[];
      for (final mode in [
        PageTurnMode.simulation3d,
        PageTurnMode.simulation3dNext,
      ]) {
        final controller = await _reader(tester, mode);
        expect(controller.size, _size);
        expect(
          tester
              .widget<ReaderView>(find.byType(ReaderView))
              .config
              .minimumFlingVelocity,
          20,
        );
        traces.add(await _pointerFrames(tester, controller, angle));
        expect(controller.active, isFalse);
        expect(controller.session.page!.pageIndex, angle < 50 ? 3 : 2);
        await tester.pumpWidget(const SizedBox.shrink());
      }
      expect(traces[1], traces[0], reason: '$angle° 起拖采样、显示位置与释放时钟');
    }
  });

  for (final rtl in [false, true]) {
    for (final next in [false, true]) {
      final direction = '${rtl ? 'RTL' : 'LTR'}${next ? '前进' : '后退'}';
      testWidgets('$direction：中央 5% 边界与上下角逐帧一致', (tester) async {
        final center = _size.height / 2;
        final edge = _size.height / 40;
        for (final y in [
          _size.height / 8,
          center - edge - 0.1,
          center - edge,
          center,
          center + edge,
          center + edge + 0.1,
          _size.height * 7 / 8,
        ]) {
          final modes = await _modes(tester, rtl: rtl);
          await _start(
            tester,
            modes,
            next,
            ui.Offset(374, y),
            ui.Offset(304, y + 40),
          );
          await _advance(tester, modes, 100);
          final horizontal = (y - center).abs() <= edge;
          expect(modes.old.horizontal, horizontal);
          expect(
            modes.old.grab,
            ui.Offset(
              384,
              horizontal ? center : (y < center ? 0 : _size.height),
            ),
          );
          _move(modes, ui.Offset(230, y < center ? _size.height + 48 : -48));
          await _pump(tester, modes, const Duration(milliseconds: 16));
          _release(modes);
          await _finish(tester, modes);
          expect(modes.old.session.page!.pageIndex, next ? 3 : 1);
        }
      });

      testWidgets('$direction：短拖、回拖与正反快扫阈值一致', (tester) async {
        for (final sample in [
          (initial: 10.0, finalDistance: 10.0, velocity: 0.0, complete: false),
          (initial: 11.0, finalDistance: 11.0, velocity: 0.0, complete: true),
          (initial: 40.0, finalDistance: 0.0, velocity: 0.0, complete: true),
          (initial: 40.0, finalDistance: 40.0, velocity: -19.0, complete: true),
          (
            initial: 40.0,
            finalDistance: 40.0,
            velocity: -20.0,
            complete: false,
          ),
          (initial: 10.0, finalDistance: 10.0, velocity: 20.0, complete: true),
        ]) {
          final modes = await _modes(tester, rtl: rtl);
          final down = ui.Offset(374, _size.height / 2);
          await _start(
            tester,
            modes,
            next,
            down,
            down.translate(-sample.initial, 0),
          );
          await _advance(tester, modes, 100);
          _move(modes, down.translate(-sample.finalDistance, 0));
          _release(modes, sample.velocity);
          await _finish(tester, modes);
          expect(
            modes.old.session.page!.pageIndex,
            sample.complete ? (next ? 3 : 1) : 2,
          );
          expect(modes.old.session.pageTurns, sample.complete ? 1 : 0);
        }
      });

      testWidgets('$direction：起卷中移动与反向松手连续一致', (tester) async {
        final modes = await _modes(tester, rtl: rtl);
        await _start(
          tester,
          modes,
          next,
          ui.Offset(374, _size.height / 8),
          ui.Offset(192, _size.height / 8 + 40),
        );
        await _advance(tester, modes, 16);
        final displayed = modes.old.point;
        _move(modes, ui.Offset(60, _size.height + 80));
        expect(modes.old.point, displayed, reason: '起卷动画期间保留已显示触点');
        _release(modes, -20);
        expect(modes.old.point, displayed, reason: '反向松手从本帧位置回弹');
        await _finish(tester, modes);
        expect(modes.old.session.page!.pageIndex, 2);
        expect(modes.old.session.pageTurns, 0);
      });

      testWidgets('$direction：点击等待与收尾每帧一致', (tester) async {
        for (final y in <double?>[
          _size.height / 8,
          _size.height * 7 / 8,
          null,
        ]) {
          final modes = await _modes(tester, rtl: rtl);
          for (final controller in modes.both) {
            if (y != null) controller.pointerDown(ui.Offset(300, y));
            controller.request(next);
          }
          await _pump(tester, modes);
          await _pump(tester, modes);
          await _advance(tester, modes, (next ? 50 : 75) - 1);
          expect(modes.old.phase, PageTurnPhase.dragging);
          final displayed = modes.old.point;
          await _pump(tester, modes, const Duration(milliseconds: 1));
          expect(modes.old.phase, PageTurnPhase.settling);
          expect(modes.old.point, displayed);
          _intrude(modes);
          await _finish(tester, modes);
          expect(modes.old.session.page!.pageIndex, next ? 3 : 1);
          expect(modes.old.session.pageTurns, 1);
        }
      });

      testWidgets('$direction：冷目标冻结松手点且活动期间拒绝排队', (tester) async {
        final gate = Completer<void>();
        final modes = await _modes(tester, rtl: rtl, targetGate: gate);
        await _start(
          tester,
          modes,
          next,
          ui.Offset(374, _size.height / 8),
          ui.Offset(192, _size.height / 8 + 40),
        );
        await _advance(tester, modes, 100);
        expect(modes.old.phase, PageTurnPhase.preparing);
        _release(modes);
        final displayed = modes.old.point;
        _intrude(modes);
        await _advance(tester, modes, 200);
        expect(modes.old.point, displayed);
        expect(modes.old.session.pageTurns, 0);
        gate.complete();
        await _pump(tester, modes);
        await _pump(tester, modes);
        expect(modes.old.point, displayed);
        _intrude(modes);
        await _finish(tester, modes);
        expect(modes.old.session.page!.pageIndex, next ? 3 : 1);
        expect(modes.old.session.pageTurns, 1);
      });

      testWidgets('$direction：冷目标就绪只渐入底页并立即跟随手指', (tester) async {
        final gate = Completer<void>();
        final modes = await _modes(tester, rtl: rtl, targetGate: gate);
        await _start(
          tester,
          modes,
          next,
          ui.Offset(374, _size.height / 2),
          ui.Offset(260, _size.height / 2 + 40),
        );
        await _advance(tester, modes, 100);
        gate.complete();
        await _pump(tester, modes);
        await _pump(tester, modes);
        expect(modes.old.targetOpacity, 0);
        _move(modes, const ui.Offset(160, 40));
        expect(modes.old.point, ui.Offset(160, _size.height / 2));
        await _advance(tester, modes, 100);
        expect(modes.old.targetOpacity, 1);
        _release(modes);
        await _finish(tester, modes);
        expect(modes.old.session.page!.pageIndex, next ? 3 : 1);
      });
    }
  }

  testWidgets('真机分辨率下相同位图、抓点与触点的正式绘制像素一致', (tester) async {
    await DuokanCurlShader.load();
    final origin = _image(_paper);
    final target = _image(const ui.Color(0xff406c94));
    addTearDown(origin.dispose);
    addTearDown(target.dispose);
    final modes = await _modes(tester, images: (origin, target));
    for (final next in [true, false]) {
      for (final (grab, touch) in [
        (ui.Offset(384, _size.height / 2), ui.Offset(304, _size.height / 2)),
        (const ui.Offset(384, 0), ui.Offset(210, _size.height * 0.18)),
        (ui.Offset(384, _size.height), ui.Offset(120, _size.height * 0.82)),
        (ui.Offset(384, _size.height / 2), ui.Offset(-268, _size.height / 2)),
      ]) {
        for (final controller in modes.both) {
          controller
            ..phase = PageTurnPhase.dragging
            ..next = next
            ..grab = grab
            ..point = touch
            ..progress = (384 - touch.dx) / 768
            ..originImage = origin
            ..targetImage = target;
        }
        final old = (await tester.runAsync(() => _render(modes.old)))!;
        final fresh = (await tester.runAsync(() => _render(modes.fresh)))!;
        expect(
          _firstMismatch(old, fresh),
          isNull,
          reason: '${next ? '右' : '左'}起卷，抓点 $grab、触点 $touch',
        );
      }
    }
  });
}
