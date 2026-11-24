import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

Future<Uint8List> _png(Color color) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(color, ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(10, 10);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<Uint8List> _pixels(WidgetTester tester, String paperKey) async {
  RenderObject? render = tester.renderObject(find.byKey(ValueKey(paperKey)));
  while (render != null && render is! RenderRepaintBoundary) {
    render = render.parent;
  }
  final boundary = render! as RenderRepaintBoundary;
  await pumpReaderUntilComplete(
    tester,
    () => !boundary.debugNeedsPaint,
    description: '纸面完成绘制',
  );
  final image = boundary.toImageSync();
  try {
    final data = (await tester.runAsync(image.toByteData))!;
    return Uint8List.fromList(data.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

/// 阅读页菜单含持续动画，`pumpAndSettle` 永不稳定；按固定帧推进。
Future<void> _pumpFrames(
  WidgetTester tester, {
  int frames = 20,
  Duration step = const Duration(milliseconds: 50),
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

Future<void> _waitImageTileReady(WidgetTester tester) async {
  final tile = find.byKey(const ValueKey<String>('settings-background-image'));
  for (var i = 0; i < 100; i++) {
    final ink = tester.widget<InkWell>(
      find.descendant(of: tile, matching: find.byType(InkWell)),
    );
    if (ink.onTap != null) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('背景图片按钮一直处于忙碌状态');
}

Future<void> _select(
  WidgetTester tester,
  String key,
  bool Function() isComplete,
) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await _pumpFrames(tester);
  if (key == 'settings-background-image') {
    await _waitImageTileReady(tester);
  }
  await tester.tap(target);
  await tester.pump();
  await pumpReaderUntilComplete(
    tester,
    isComplete,
    description: '$key 背景加载与应用',
  );
  await _pumpFrames(tester);
  if (key == 'settings-background-image') {
    await _waitImageTileReady(tester);
  }
}

Future<(ReaderSession, Future<void> Function())> _openReader(
  WidgetTester tester,
  PageTurnMode mode,
  List<String> changes,
) async {
  final source = await openTestChapterSource(
    File('../../test_corpus/basic.epub').readAsBytesSync(),
  );
  final red = (await tester.runAsync(() => _png(Colors.red)))!;
  final blue = (await tester.runAsync(() => _png(Colors.blue)))!;
  final imageIds = ['image:red', 'image:blue'].iterator;
  late ReaderSession session;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReaderPage(
          source: source,
          bookId: 'background-repaint-${mode.id}',
          store: MemoryReaderProgressStore(),
          pageTurnMode: mode,
          onSessionReady: (value) => session = value,
          onBackgroundChanged: changes.add,
          onBackgroundImageOpacityChanged: (_) {},
          onPickBackgroundImage: () async =>
              imageIds.moveNext() ? imageIds.current : null,
          backgroundImageLoader: (id) async => id == 'image:red' ? red : blue,
        ),
      ),
    ),
  );
  await pumpReaderUntilComplete(
    tester,
    () => !session.loading && session.hasContent,
    description: '${mode.label}首屏正文',
  );
  return (
    session,
    () async {
      source.close();
      await source.preparationsStopped;
    },
  );
}

Future<void> _verifyImageFade(
  WidgetTester tester,
  String paperKey,
  Uint8List original,
) async {
  final fade = find.byKey(const ValueKey('settings-background-image-fade'));
  await tester.ensureVisible(fade);
  await _pumpFrames(tester);
  for (final amount in [50.0, 100.0, 0.0]) {
    final slider = tester.widget<Slider>(fade);
    slider.onChanged!(amount);
    slider.onChangeEnd!(amount);
    await _pumpFrames(tester);
    final current = await _pixels(tester, paperKey);
    for (var channel = 0; channel < 3; channel++) {
      final expected =
          original[channel] * (1 - amount / 100) + 255 * amount / 100;
      expect(
        current[channel],
        closeTo(expected, 1),
        reason: '淡化 $amount% 即时更新纸面',
      );
    }
    if (amount == 0) {
      expect(current, orderedEquals(original), reason: '取消淡化恢复完整原图');
    }
  }
}

Future<void> _verifyBackgrounds(
  WidgetTester tester,
  String paperKey,
  List<String> changes,
) async {
  final plain = await _pixels(tester, paperKey);
  await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
  await _pumpFrames(tester);
  await tester.tap(find.byKey(const ValueKey('menu-entry-theme')));
  await _pumpFrames(tester);
  var previous = plain;
  for (final id in ['paper', 'wood', 'gray', 'image:red', 'image:blue']) {
    final key = id.startsWith('image:')
        ? 'settings-background-image'
        : 'settings-bg-$id';
    await _select(tester, key, () => changes.isNotEmpty && changes.last == id);
    expect(changes.last, id);
    final current = await _pixels(tester, paperKey);
    expect(current, isNot(orderedEquals(previous)), reason: '$id 即时绘制');
    if (id.startsWith('image:')) {
      final color = id == 'image:red' ? Colors.red : Colors.blue;
      expect(current.take(4), [
        (color.r * 255).round(),
        (color.g * 255).round(),
        (color.b * 255).round(),
        255,
      ], reason: '导入图片默认保留原色，不叠加白色蒙层');
    }
    previous = current;
  }
  await _verifyImageFade(tester, paperKey, previous);
  await _select(
    tester,
    'settings-bg-none',
    () => changes.isNotEmpty && changes.last == 'none',
  );
  expect(changes.last, 'none');
  expect(
    await _pixels(tester, paperKey),
    orderedEquals(plain),
    reason: '当前纸面立即还原纯色',
  );
}

void main() {
  for (final mode in [
    PageTurnMode.none,
    PageTurnMode.simulationBessel,
    PageTurnMode.scroll,
  ]) {
    testWidgets('${mode.label}中背景连续选择后立即重绘当前纸面', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final changes = <String>[];
      final (session, closeSource) = await _openReader(tester, mode, changes);
      final page = session.page;
      final position = session.progress;
      final fingerprint = session.layoutFingerprint;
      final prefix = mode == PageTurnMode.scroll
          ? 'scroll-page'
          : 'reader-page';
      final paperKey = '$prefix-${page!.spineIndex}-${page.pageIndex}';
      await _verifyBackgrounds(tester, paperKey, changes);
      expect(session.page, same(page), reason: '背景变化不重排');
      expect(session.layoutFingerprint, fingerprint);
      expect(session.progress, position, reason: '阅读位置不变');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpReaderTask(tester, closeSource());
      await tester.pumpAndSettle();
    });
  }
}
