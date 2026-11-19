import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/menu/reader_menu_overlay.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

import '../test/support/test_epub.dart';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('桌面阅读验收等待超时');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump();
}

Future<ReaderSession> _openReader(
  WidgetTester tester,
  EpubChapterSource source,
  String contentRevision,
) async {
  ReaderSession? session;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: RepaintBoundary(
          key: const ValueKey('desktop-reader-capture'),
          child: ReaderPage(
            source: source,
            store: MemoryReaderProgressStore(),
            bookId: 'desktop-wheel-acceptance',
            contentRevision: contentRevision,
            bookTitle: '桌面滚轮验收',
            onSessionReady: (value) => session = value,
          ),
        ),
      ),
    ),
  );
  await _until(tester, () => session?.page != null && !session!.loading);
  return session!;
}

Future<void> _wheel(WidgetTester tester, double delta) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      kind: PointerDeviceKind.mouse,
      position: tester.getCenter(find.byType(ReaderView)),
      scrollDelta: Offset(0, delta),
    ),
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  const capture = bool.fromEnvironment('CAPTURE_DESKTOP_INPUT');
  if (!capture) return;
  final output = '${Directory.systemTemp.path}/spectacular-desktop-input';
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('desktop-reader-capture')),
  );
  await tester.pump(const Duration(milliseconds: 350));
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('桌面验收截图：$output/$name.png');
  } finally {
    image.dispose();
  }
}

Future<void> _checkMenu(WidgetTester tester, ReaderSession session) async {
  final page = session.page;
  await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
  await tester.pumpAndSettle();
  expect(
    tester.widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay)).open,
    isTrue,
  );
  await _wheel(tester, 120);
  await tester.pump(const Duration(milliseconds: 500));
  expect(session.page, same(page));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('桌面正式 EPUB 引擎：滚轮前翻、回翻、保存位置与菜单遮罩', (tester) async {
    final bytes = buildTestEpub(
      title: '桌面滚轮验收',
      paragraphs: List.generate(
        100,
        (index) => '第 $index 段。${'这是正式 EPUB 引擎的桌面滚轮翻页验收正文。' * 12}',
      ),
    );
    final revision = sha256.convert(bytes).toString();
    final source = await EpubChapterSource.open(
      bytes,
      contentVersion: revision,
    );
    addTearDown(source.close);
    final session = await _openReader(tester, source, revision);
    final firstCfi = session.readingCfi;
    expect(firstCfi, isNotNull);
    await _capture(tester, 'reader-first');
    await _wheel(tester, 120);
    await _until(tester, () => session.page?.pageIndex == 1);
    expect(session.readingCfi, isNot(firstCfi));
    await _capture(tester, 'reader-next');
    await tester.pump(const Duration(milliseconds: 300));
    await _wheel(tester, -120);
    await _until(tester, () => session.page?.pageIndex == 0);
    expect(session.readingCfi, firstCfi);
    await session.flushProgress();
    expect((await session.store.load(session.bookId))?.cfi, firstCfi);
    await _capture(tester, 'reader-returned');
    await _checkMenu(tester, session);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
