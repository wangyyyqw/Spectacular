import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
import 'package:reader_ui/a11y/semantics_layer.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

/// 通过 USB 的 adb reverse 提供原书，避免把版权语料打进测试包。
/// 真机请通过 tool/device_css_test.py 启动，避免驱动按正式包名清理。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    '原书第六章：容器、表格、翻页与字号重排',
    (tester) async {
      final bytes = await _readBook();
      final source = await _openReader(tester, bytes);
      final initial = await _checkChapter(source);
      expect(_page(tester).spineIndex, 32);
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await _capturePages(tester, binding, initial['pages']! as int);
      await _resizeText(tester);
      final enlarged = await _checkChapter(source);
      expect(enlarged['fontSize'], greaterThan(initial['fontSize']! as double));
      expect(_page(tester).spineIndex, 32, reason: '重排保持章节位置');
      await binding.takeScreenshot('chapter6-enlarged');
      binding.reportData!['chapter6'] = <String, Object?>{
        'bytes': bytes.length,
        'initial': initial,
        'enlarged': enlarged,
        'physicalSize': tester.view.physicalSize.toString(),
        'devicePixelRatio': tester.view.devicePixelRatio,
      };
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: const String.fromEnvironment('EPUB_TEST_URL').isEmpty,
  );
}

Future<EpubChapterSource> _openReader(
  WidgetTester tester,
  Uint8List bytes,
) async {
  final store = MemoryReaderProgressStore();
  await store.save(
    'css-device',
    const ReaderProgress(spineIndex: 32, pageIndex: 0),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: EpubReaderPage(
        bytes: bytes,
        bookId: 'css-device',
        store: store,
        bookTitle: '诸神愚戏',
      ),
    ),
  );
  await _settle(tester);
  final source =
      tester.widget<ReaderPage>(find.byType(ReaderPage)).source
          as EpubChapterSource;
  expect(
    flattenToc(source.toc).any(
      (row) => row.entry.spineIndex == 32 && row.entry.title.contains('道具'),
    ),
    isTrue,
  );
  return source;
}

Future<Uint8List> _readBook() async {
  const url = String.fromEnvironment('EPUB_TEST_URL');
  if (url.isEmpty) {
    throw StateError('请通过 EPUB_TEST_URL 指定 USB 转发的原书地址');
  }
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    expect(response.statusCode, HttpStatus.ok);
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  } finally {
    client.close(force: true);
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 250),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 90),
  );
  expect(find.byKey(const ValueKey<String>('epub-open-error')), findsNothing);
  expect(find.byKey(const ValueKey<String>('reader-error')), findsNothing);
  expect(find.byType(ReaderSemanticsLayer), findsOneWidget);
  expect(tester.takeException(), isNull);
}

PageContent _page(WidgetTester tester) =>
    tester.widget<ReaderSemanticsLayer>(find.byType(ReaderSemanticsLayer)).page;

Future<Map<String, Object>> _checkChapter(EpubChapterSource source) async {
  final pages = await source.loadChapter(32);
  expect(pages.length, greaterThan(1), reason: '原书道具章应有多页正文');
  final blocks = <PageBlock>{
    for (final page in pages)
      for (final slice in page.slices) slice.block,
  };
  _checkContainers(blocks);
  final body = blocks.firstWhere(
    (block) => block.layout.text.startsWith('你可以吸收周围的恐惧情绪'),
  );
  final tables = blocks.where((block) => block.table != null).toList();
  expect(tables, isNotEmpty);
  for (final table in tables) {
    expect(
      table.table!.tableWidth + table.style!.margin.horizontal,
      lessThanOrEqualTo(source.contentWidth + .01),
      reason: '评级表留在正文区',
    );
  }
  for (final page in pages) {
    expect(page.slices, isNotEmpty);
    expect(page.usedHeight, lessThanOrEqualTo(page.pageHeight + .01));
  }
  return <String, Object>{
    'pages': pages.length,
    'tables': tables.length,
    'contentWidth': source.contentWidth,
    'fontSize': body.style!.fontSize,
    'containerDepth': body.containers.length,
  };
}

void _checkContainers(Set<PageBlock> blocks) {
  final name = blocks.firstWhere((block) => block.layout.text == '【恐惧养料】');
  final body = blocks.firstWhere(
    (block) => block.layout.text.startsWith('你可以吸收周围的恐惧情绪'),
  );
  expect(name.containers, hasLength(3));
  expect(
    identical(name.containers.last.container, body.containers.last.container),
    isTrue,
    reason: '效果名与说明共享同一个完整盒',
  );
  expect(name.style!.borders.hasBorder, isFalse);
  expect(body.style!.borders.hasBorder, isFalse);
  expect(
    name.containers.every((item) => item.container.style.backgroundColor.a > 0),
    isTrue,
  );
  for (final container in name.containers.map((item) => item.container)) {
    final fragments = blocks
        .expand((block) => block.containers)
        .where((item) => identical(item.container, container));
    expect(fragments.where((item) => item.startsHere), hasLength(1));
    expect(fragments.where((item) => item.endsHere), hasLength(1));
  }
}

Future<void> _capturePages(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  int pageCount,
) async {
  // 逐页走真实点击路径，前三页留图；其余页验证页序与非空内容。
  for (var i = 0; i < pageCount; i++) {
    expect(_page(tester).spineIndex, 32);
    expect(_page(tester).pageIndex, i);
    expect(_page(tester).slices, isNotEmpty);
    if (i < 3) await binding.takeScreenshot('chapter6-page-${i + 1}');
    if (i + 1 < pageCount) await _turn(tester, forward: true);
  }
  await _turn(tester, forward: false);
  expect(_page(tester).pageIndex, pageCount - 2, reason: '反向翻页可恢复上一页');
}

Future<void> _turn(WidgetTester tester, {required bool forward}) async {
  final rect = tester.getRect(find.byType(ReaderView));
  await tester.tapAt(
    Offset(rect.left + rect.width * (forward ? .85 : .15), rect.center.dy),
  );
  await _settle(tester);
}

Future<void> _resizeText(WidgetTester tester) async {
  await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey<String>('menu-entry-type')));
  await tester.pumpAndSettle();
  final slider = find.byKey(const ValueKey<String>('settings-font-size'));
  final before = tester.widget<Slider>(slider).value;
  await tester.drag(slider, const Offset(45, 0));
  await tester.pumpAndSettle();
  expect(tester.widget<Slider>(slider).value, greaterThan(before));
  await tester.tap(find.byKey(const ValueKey<String>('menu-drawer-close')));
  await tester.pumpAndSettle();
  await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
  await _settle(tester);
}
