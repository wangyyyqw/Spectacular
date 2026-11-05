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
  final image = boundary.toImageSync();
  try {
    final data = (await tester.runAsync(image.toByteData))!;
    return Uint8List.fromList(data.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

Future<void> _select(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pump();
  // 原生图片解码需离开测试虚拟时钟。
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}

Future<ReaderSession> _openReader(
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
          onPickBackgroundImage: () async =>
              imageIds.moveNext() ? imageIds.current : null,
          backgroundImageLoader: (id) async => id == 'image:red' ? red : blue,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

Future<void> _verifyBackgrounds(
  WidgetTester tester,
  String paperKey,
  List<String> changes,
) async {
  final plain = await _pixels(tester, paperKey);
  await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('menu-entry-theme')));
  await tester.pumpAndSettle();
  var previous = plain;
  for (final id in ['paper', 'wood', 'gray', 'image:red', 'image:blue']) {
    final key = id.startsWith('image:')
        ? 'settings-background-image'
        : 'settings-bg-$id';
    await _select(tester, key);
    expect(changes.last, id);
    final current = await _pixels(tester, paperKey);
    expect(current, isNot(orderedEquals(previous)), reason: '$id 即时绘制');
    previous = current;
  }
  await _select(tester, 'settings-bg-none');
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
      final changes = <String>[];
      final session = await _openReader(tester, mode, changes);
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
    });
  }
}
