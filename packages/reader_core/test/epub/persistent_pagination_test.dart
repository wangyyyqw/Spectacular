import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/cache/chapter_pagination_store.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/chapter/chapter_layout_cache.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/source/chapter_source.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

final _epub = auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
  'book.opf':
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">持久分页</dc:identifier></metadata>'
      '<manifest><item id="c" href="c.xhtml" media-type="application/xhtml+xml"/></manifest>'
      '<spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
      'body{margin:0}p{margin:0 0 10px;font-size:18px;line-height:1.6}'
      '</style></head><body>${List.generate(70, (i) => '<p>第 $i 段：${'准确页界与原文位置保持一致。' * 10}</p>').join()}'
      '</body></html>',
});

Future<ChapterPaginationStore> _store() async {
  final root = await Directory.systemTemp.createTemp('真实分页缓存-');
  addTearDown(() => root.delete(recursive: true));
  return FileChapterPaginationStore(directoryProvider: () async => root);
}

Future<EpubChapterSource> _open(
  ChapterPaginationStore store, {
  String? version = '正文版本一',
  double width = 366.6666666666667,
  ReaderOverrides overrides = const ReaderOverrides(),
}) async {
  final source = await EpubFormatOpener(paginationStore: store).openBytes(
    _epub,
    options: ReaderOpenOptions(
      contentWidth: width,
      contentHeight: 773.1694444444443,
      contentVersion: version,
    ),
  );
  addTearDown(() async {
    source.close();
    await source.preparationsStopped;
  });
  await source.applyContentSize(
    width: width,
    height: 773.1694444444443,
    topInset: 56.075,
    sideInsets: (left: 8.8, right: 8.53333333333336),
  );
  await source.applyOverrides(overrides);
  return source;
}

Object _geometry(List<PageContent> pages) => [
  for (final page in pages)
    [
      page.usedHeight,
      page.pageHeight,
      page.topPadding,
      for (final slice in page.slices)
        [
          slice.block.startCfi,
          slice.block.layout.text,
          slice.startLine,
          slice.endLine,
          slice.height,
          slice.absoluteTop,
          slice.leadingExtent,
          slice.trailingExtent,
          for (final line in slice.lines)
            [
              line.start,
              line.end,
              line.top,
              line.height,
              line.width,
              line.baseline,
            ],
        ],
    ],
];

Object? _expected(Object? value) {
  if (value is double) return closeTo(value, 1e-8);
  if (value is List) return value.map(_expected).toList();
  return value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(ChapterLayoutCache.recent.clear);
  tearDown(ChapterLayoutCache.recent.clear);

  test('清空进程内布局后先恢复准确页数，再回放持久索引，正文与CFI不变', () async {
    final store = await _store();
    final writer = await _open(store);
    final expected = await writer.loadChapter(0);
    writer.close();
    await writer.preparationsStopped;
    ChapterLayoutCache.recent.clear();
    final reader = await _open(store);
    final handle = reader.scheduleProgressiveChapter(0);
    final count = await handle.pageCountUpdates.first;
    expect(count, expected.length);
    expect(handle.availablePages, isEmpty, reason: '统计独立于页面准备');
    expect(handle.isComplete, isFalse);
    final first = await handle.firstPages;
    expect(handle.pageCount, expected.length);
    expect(first.length, lessThan(count));
    final actual = await handle.result;
    expect(_geometry(actual), _expected(_geometry(expected)));
    expect(actual.first, same(first.first));
    expect(reader.cacheReport, contains('持久分页命中 1 次'));
    expect(reader.cacheReport, contains('持久页索引回放 1 次'));
  });

  test('准确计数后取消剩余工作仍可保存总数，重开不把统计当作完整章节', () async {
    final store = await _store();
    final writer = await _open(store);
    final handle = writer.scheduleProgressiveChapter(0);
    await handle.firstPages;
    final counted = Completer<int>();
    final subscription = handle.pageCountUpdates.listen((count) {
      writer.setBackgroundLayoutPaused(true);
      counted.complete(count);
    });
    final count = await counted.future;
    await writer.cacheWritesStopped;
    await subscription.cancel();
    handle.cancel();
    writer.close();
    await writer.preparationsStopped;
    ChapterLayoutCache.recent.clear();
    final reader = await _open(store);
    final resumed = reader.scheduleProgressiveChapter(0);
    expect(await resumed.pageCountUpdates.first, count);
    expect(resumed.availablePages, isEmpty);
    expect(resumed.isComplete, isFalse);
    expect(await resumed.result, hasLength(count));
  });

  test('版面尺寸、字体设置及内容版本变化不复用旧总数或索引', () async {
    final store = await _store();
    final writer = await _open(store);
    await writer.loadChapter(0);
    writer.close();
    await writer.preparationsStopped;
    for (final variant in [
      (version: '正文版本一', width: 320.0, overrides: const ReaderOverrides()),
      (
        version: '正文版本二',
        width: 366.6666666666667,
        overrides: const ReaderOverrides(),
      ),
      (
        version: '正文版本一',
        width: 366.6666666666667,
        overrides: const ReaderOverrides(fontFamily: 'serif', fontSize: 22),
      ),
    ]) {
      ChapterLayoutCache.recent.clear();
      final reader = await _open(
        store,
        version: variant.version,
        width: variant.width,
        overrides: variant.overrides,
      );
      final handle = reader.scheduleProgressiveChapter(0);
      await handle.firstPages;
      expect(handle.pageCount, isNull);
      final pages = await handle.result;
      expect(handle.pageCount, pages.length);
      expect(reader.cacheReport, contains('持久分页命中 0 次'));
      reader.close();
      await reader.preparationsStopped;
    }
  });

  test('没有稳定内容身份时不读取或写入持久缓存', () async {
    final store = _RejectedStore();
    final source = await _open(store, version: null);
    expect(await source.loadChapter(0), isNotEmpty);
    source.close();
    await source.preparationsStopped;
    expect(store.reads, 0);
    expect(store.writes, 0);
  });

  test('热缓存页数回调立即关书时，取消不误标完整或重复完成句柄', () async {
    final store = await _store();
    final writer = await _open(store);
    final pages = await writer.loadChapter(0);
    writer.close();
    await writer.preparationsStopped;
    final reader = await _open(store);
    final handle = reader.scheduleProgressiveChapter(0);
    final subscription = handle.pageCountUpdates.listen((count) {
      expect(count, pages.length);
      reader.close();
    });
    await expectLater(handle.result, throwsA(isA<ChapterLoadCancelled>()));
    await subscription.cancel();
    await reader.preparationsStopped;
    expect(handle.isComplete, isFalse);
  });

  test('存储失败不阻塞首页、完整章节或关闭', () async {
    final source = await _open(_RejectedStore());
    final handle = source.scheduleProgressiveChapter(0);
    expect(await handle.firstPages, isNotEmpty);
    expect(await handle.result, hasLength(handle.pageCount!));
    source.close();
    await source.preparationsStopped;
    expect(source.cacheReport, contains('缓存异常 3 次'));
  });
}

class _RejectedStore implements ChapterPaginationStore {
  int reads = 0;
  int writes = 0;
  @override
  Future<ChapterPaginationData?> read(String key) async {
    reads += 1;
    throw const FileSystemException('缓存不可读');
  }

  @override
  Future<void> write(ChapterPaginationData data) async {
    writes += 1;
    throw const FileSystemException('缓存不可写');
  }
}
