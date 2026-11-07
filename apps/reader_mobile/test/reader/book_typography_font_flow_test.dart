import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/text/font_coverage.dart';
import 'package:reader_core/text/font_digest.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/epub/book_page_counter.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';
import 'package:reader_mobile/reader/reader_font_store.dart';
import 'package:reader_ui/decorations/decoration.dart';
import 'package:reader_ui/page_furniture/page_furniture.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

class _LateFontLoader {
  _LateFontLoader(this.store, this.bytes)
    : family = 'user_${fontDigest(bytes)}';

  final ReaderFontStore store;
  final Uint8List bytes;
  final String family;
  final ready = Completer<void>();
  final requests = <String>[];

  Future<void> load(String requested) async {
    requests.add(requested);
    await ready.future;
    final imported = await store.import(bytes, displayName: '计页晚到字体.otf');
    expect(imported.family, requested);
  }
}

class _DecorationStore extends Fake implements ReaderDecorationStore {
  _DecorationStore(this.item);
  final ReaderDecoration item;

  @override
  Future<List<ReaderDecoration>> list() async => [item];
}

class _CountCache implements BookPageCountStore {
  final saved = <String, Map<int, int>>{};
  final loads = <String>[];

  @override
  Future<Map<int, int>> load(String layoutKey) async {
    loads.add(layoutKey);
    return Map.of(saved[layoutKey] ?? {});
  }

  @override
  Future<void> save(String layoutKey, Map<int, int> counts) async =>
      saved[layoutKey] = Map.of(counts);
}

Future<_LateFontLoader> _fontLoader(
  WidgetTester tester, {
  String fontFile = 'SourceHanSerifSC-Regular.otf',
}) async {
  final directory = await tester.runAsync(
    () => Directory.systemTemp.createTemp('book-typography-font-'),
  );
  addTearDown(() => directory!.delete(recursive: true));
  final bytes = await tester.runAsync(
    () => File('../../test_fonts/$fontFile').readAsBytes(),
  );
  return _LateFontLoader(
    ReaderFontStore(
      LibraryStore.memory(),
      directoryProvider: () async => directory!,
    ),
    bytes!,
  );
}

Future<ReaderDecoration> _laterDecoration(
  Uint8List bytes,
  String family,
) async {
  // 使用独立原文源取得真实 CFI，不影响待测阅读源的准备和排版计数。
  final source = await EpubChapterSource.open(bytes, verifyCrc: false);
  try {
    final chapter = await source.loadAnchorChapter(1);
    final block = chapter.blocks.firstWhere(
      (block) => block.text.contains('后章手工字体'),
    );
    const quote = '后章手工字体';
    final start = block.text.indexOf(quote);
    return ReaderDecoration(
      id: 'later-font',
      startCfi: cfiWithCharOffset(block.cfi, start),
      endCfi: cfiWithCharOffset(block.cfi, start + quote.length),
      quote: quote,
      style: ReaderDecorationStyle(fontFamily: family),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
  } finally {
    source.close();
  }
}

Future<ReaderSession> _showReader(
  WidgetTester tester,
  EpubChapterSource source,
  ReaderDecoration item,
  Future<void> Function(String) loadFont, {
  String revision = 'book-typography-r1',
}) async {
  late ReaderSession session;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReaderPage(
          source: source,
          store: MemoryReaderProgressStore(),
          bookId: 'book-typography',
          contentRevision: revision,
          decorations: _DecorationStore(item),
          onLoadFont: loadFont,
          onSessionReady: (value) => session = value,
          pageTurnMode: PageTurnMode.none,
        ),
      ),
    ),
  );
  await pumpReaderUntil(tester, find.byType(ReaderPageFooter));
  return session;
}

Future<EpubChapterSource> _countingSource(
  WidgetTester tester,
  Uint8List bytes,
  _CountCache cache,
) async {
  final source = await tester.runAsync(
    () => EpubChapterSource.open(
      bytes,
      verifyCrc: false,
      contentVersion: 'book-font-deleted-r1',
    ),
  );
  addTearDown(source!.close);
  source.setPageCountStore(cache);
  return source;
}

Future<String> _completeCounts(
  WidgetTester tester,
  EpubChapterSource source,
) async {
  await pumpReaderUntilComplete(
    tester,
    () => source.pageCountState.value.isComplete,
    description: '两章实际计页完成',
  );
  await source.flushPageCounts();
  return source.pageCountState.value.layoutKey;
}

Future<void> _removeReader(
  WidgetTester tester,
  EpubChapterSource source,
) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  source.close();
}

Future<String> _primeCounts(
  WidgetTester tester,
  Uint8List bytes,
  ReaderDecoration item,
  Future<void> Function(String) loadFont,
  _CountCache cache,
) async {
  final original = await _countingSource(tester, bytes, cache);
  await _showReader(
    tester,
    original,
    item,
    loadFont,
    revision: 'book-font-deleted-r1',
  );
  final key = await _completeCounts(tester, original);
  expect(key, contains('availability=可用'));
  expect(cache.saved[key]?.length, 2);
  await _removeReader(tester, original);
  return key;
}

void main() {
  testWidgets('后章手工字体从缺失到可用时更换计页配置，当前章只排一次', (tester) async {
    final fonts = await _fontLoader(tester);
    final bytes = buildMultiChapterEpub(
      chapters: ['首屏正文不使用手工字体。', '后章手工字体改变度量。'],
    );
    final item = await tester.runAsync(
      () => _laterDecoration(bytes, fonts.family),
    );
    final source = await EpubChapterSource.open(
      bytes,
      verifyCrc: false,
      contentVersion: 'book-typography-r1',
    );
    addTearDown(source.close);
    final session = await _showReader(tester, source, item!, fonts.load);
    await pumpReaderUntilComplete(
      tester,
      () =>
          fonts.requests.isNotEmpty &&
          source.pageCountState.value.completedChapters == 1,
      description: '当前章完成且后章字体等待',
    );
    expect(source.chapterLayoutCount, 1);
    final original = session.page!.slices.first.block.layout;
    final missingKey = source.pageCountState.value.layoutKey;

    fonts.ready.complete();
    await pumpReaderUntilComplete(
      tester,
      () => source.pageCountState.value.isComplete,
      description: '实际字体注册后的完整计页',
    );
    expect(source.chapterLayoutCount, 2, reason: '两章各排一次，首屏缓存继续复用');
    expect(fonts.requests, [fonts.family]);
    expect(session.page!.slices.first.block.layout, same(original));
    expect(source.pageCountState.value.layoutKey, isNot(missingKey));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('同进程字体注册后文件丢失，回退计页不复用原字体的完整缓存', (tester) async {
    // 每个测试使用独立内容摘要，避免注册 Future 跨测试假时钟区域复用。
    final fonts = await _fontLoader(
      tester,
      fontFile: 'SourceHanSerifSC-Bold.otf',
    );
    final imported = await tester.runAsync(
      () => fonts.store.import(fonts.bytes, displayName: '计页删除字体.otf'),
    );
    final bytes = buildMultiChapterEpub(chapters: ['首屏正文。', '后章手工字体需要校验实际文件。']);
    final item = await tester.runAsync(
      () => _laterDecoration(bytes, fonts.family),
    );
    final cache = _CountCache();
    Future<void> load(String family) async {
      await fonts.store.load(family);
    }

    final availableKey = await _primeCounts(tester, bytes, item!, load, cache);
    await tester.runAsync(() => File(imported!.filePath).delete());
    expect(FontCoverageRegistry.covers(fonts.family, 0x41), isTrue);
    cache.loads.clear();

    final restored = await _countingSource(tester, bytes, cache);
    final session = await _showReader(
      tester,
      restored,
      item,
      load,
      revision: 'book-font-deleted-r1',
    );
    final currentLayout = session.page!.slices.first.block.layout;
    final fallbackKey = await _completeCounts(tester, restored);
    expect(fallbackKey, isNot(availableKey));
    expect(fallbackKey, contains('availability=回退'));
    expect(cache.loads, isNot(contains(availableKey)));
    expect(restored.chapterLayoutCount, 1, reason: '首屏复用已验证布局，只重排字体回退的后章');
    expect(session.page!.slices.first.block.layout, same(currentLayout));
    expect(restored.pageCountState.value.completedChapters, 2);
    expect(cache.saved[fallbackKey]?.length, 2);
    await _removeReader(tester, restored);
    expect(tester.takeException(), isNull);
  });
}
