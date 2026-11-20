import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_ui/paging/page_turn_controller.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/theme/reader_theme.dart';

import '../test/support/test_epub.dart';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('桌面 3D 翻页等待超时');
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('桌面正式 EPUB 切换 3D 后可前后翻页并保留阅读位置', (tester) async {
    final bytes = buildTestEpub(
      title: '桌面 3D 翻页验收',
      paragraphs: List.generate(
        80,
        (index) => '第 $index 段。${'三维卷页保持正文和阅读位置。' * 12}',
      ),
    );
    final revision = sha256.convert(bytes).toString();
    final source = await EpubChapterSource.open(
      bytes,
      contentVersion: revision,
    );
    addTearDown(source.close);
    final store = MemoryReaderProgressStore();
    ReaderSession? session;
    final mode = ValueNotifier(PageTurnMode.cover);
    addTearDown(mode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: const ValueKey('desktop-3d-capture'),
          child: ValueListenableBuilder(
            valueListenable: mode,
            builder: (_, value, _) => ReaderPage(
              source: source,
              store: store,
              bookId: 'desktop-3d-acceptance',
              contentRevision: revision,
              theme: ReaderTheme.sepia,
              pageTurnMode: value,
              onSessionReady: (value) => session = value,
            ),
          ),
        ),
      ),
    );
    await _until(tester, () => session?.page != null && !session!.loading);
    final firstCfi = session!.readingCfi;
    mode.value = PageTurnMode.simulation3d;
    await tester.pump();
    final view = tester.state<PageTurnViewState>(find.byType(PageTurnView));
    await _until(tester, () => view.snapshotCount >= 2);
    for (final next in [true, true, false, false]) {
      final page = session!.page!.pageIndex;
      view.controller.pointerDown(
        Offset(
          view.controller.size.width * 0.9,
          view.controller.size.height * 0.9,
        ),
      );
      view.controller.request(next);
      await _until(
        tester,
        () => view.controller.phase == PageTurnPhase.settling,
      );
      await tester.pump(const Duration(milliseconds: 80));
      if (next && page == 0) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('desktop-3d-capture')),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory(
            '${Directory.systemTemp.path}/spectacular-desktop-3d',
          );
          await directory.create(recursive: true);
          await File('${directory.path}/3d-turn.png')
              .writeAsBytes(data!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      }
      await _until(tester, () => !view.controller.active);
      expect(session!.page!.pageIndex, page + (next ? 1 : -1));
      await tester.pump(const Duration(milliseconds: 350));
    }
    await tester.sendEventToBinding(
      PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: tester.getCenter(find.byType(PageTurnView)),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await _until(tester, () => session!.page!.pageIndex == 1);
    await _until(tester, () => !view.controller.active);
    view.controller.request(false);
    await _until(tester, () => !view.controller.active);
    expect(session!.readingCfi, firstCfi);
    await session!.flushProgress();
    expect((await store.load(session!.bookId))!.cfi, firstCfi);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
