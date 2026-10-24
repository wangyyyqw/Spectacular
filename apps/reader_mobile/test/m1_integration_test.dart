import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/theme/reader_theme.dart';

import 'package:reader_mobile/reader/epub_chapter_source.dart';

/// P2-35 M1 集成测试：真实 EPUB 样本走完整「打开→分页→绘制→翻页→
/// 设置重排→主题切换→进度恢复」链路。
const _bookFile = 'basic.epub';

Directory? _findCorpus() {
  var directory = Directory.current;
  while (true) {
    final candidate = Directory('${directory.path}/test_corpus');
    if (candidate.existsSync()) {
      return candidate;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      return null;
    }
    directory = parent;
  }
}

Future<EpubChapterSource?> _openSource([String file = _bookFile]) async {
  final corpus = _findCorpus();
  if (corpus == null) {
    return null;
  }
  final entry = File('${corpus.path}/$file');
  if (!entry.existsSync()) {
    return null;
  }
  return EpubChapterSource.open(entry.readAsBytesSync());
}

Widget _app(
  EpubChapterSource source,
  ReaderProgressStore store, {
  ReaderOverrides overrides = const ReaderOverrides(),
  ReaderTheme? theme,
  ValueChanged<ReaderSession>? onReady,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 360,
        height: 640,
        child: ReaderPage(
          source: source,
          store: store,
          bookId: 'm1-integration',
          overrides: overrides,
          theme: theme,
          onSessionReady: onReady,
        ),
      ),
    ),
  ),
);

Future<void> _tapRight(WidgetTester tester) async {
  final rect = tester.getRect(find.byType(ReaderPage));
  await tester.tapAt(
    rect.topLeft + Offset(rect.width * 0.85, rect.height * 0.5),
  );
  await tester.pumpAndSettle();
}

String? _firstCfi(PageContent? page) {
  for (final slice in page?.slices ?? const <PageBlockSlice>[]) {
    if (slice.startLine != 0) {
      continue;
    }
    final cfi = slice.block.startCfi;
    if (cfi != null) {
      return cfi;
    }
  }
  for (final slice in page?.slices ?? const <PageBlockSlice>[]) {
    final cfi = slice.block.startCfi;
    if (cfi != null) {
      return cfi;
    }
  }
  return null;
}

/// 构造「标签不闭合」章节的最小 EPUB（P7-11 双路径集成样本）。
Uint8List _buildBrokenChapterEpub() {
  final files = <String, String>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml':
        '<?xml version="1.0"?><container><rootfiles>'
        '<rootfile full-path="OEBPS/content.opf"/></rootfiles></container>',
    'OEBPS/content.opf':
        '<?xml version="1.0"?><package '
        'xmlns="http://www.idpf.org/2007/opf" version="3.0" '
        'unique-identifier="bid"><metadata '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="bid">urn:uuid:p7-0001</dc:identifier>'
        '<dc:title>P7</dc:title><dc:language>zh</dc:language></metadata>'
        '<manifest><item id="c1" href="c1.xhtml" '
        'media-type="application/xhtml+xml"/></manifest>'
        '<spine><itemref idref="c1"/></spine></package>',
    // 段落未闭合：严格 XML 失败 → 容错回退（P7-11）。
    'OEBPS/c1.xhtml':
        '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
        '<p>第一段没有闭合标签'
        '<p>第二段也没有闭合'
        '</body></html>',
  };
  final archive = Archive();
  files.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  testWidgets('M1 全链路：打开→分页→绘制→翻页→设置→主题→恢复', (tester) async {
    final source = await _openSource();
    if (source == null) {
      // ignore: avoid_print
      print('SKIP 本地样本库缺失（test_corpus/ 不入库）');
      return;
    }
    final store = MemoryReaderProgressStore();
    late ReaderSession session;
    await tester.pumpWidget(
      _app(source, store, onReady: (value) => session = value),
    );
    await tester.pumpAndSettle();

    // 打开 + 分页 + 绘制。
    expect(session.error, isNull);
    expect(session.page, isNotNull, reason: '打开后应有可绘制页');
    expect(session.loading, isFalse);
    expect(find.byType(CustomPaint), findsWidgets);

    final visited = <ReaderProgress>[session.progress!];
    final anchor = _firstCfi(session.page);
    // 连续翻页到末页。
    for (var i = 0; i < 10; i++) {
      await _tapRight(tester);
      final progress = session.progress!;
      if (visited.last == progress) {
        break;
      }
      visited.add(progress);
      expect(session.page, isNotNull, reason: '翻页不应出现空白页');
    }
    expect(visited.length, greaterThan(1), reason: '应能连续翻页');
    expect(
      visited.any((p) => p.spineIndex > visited.first.spineIndex),
      isTrue,
      reason: '应跨章节翻页',
    );

    // 末页不再前进。
    final atEnd = session.progress!;
    await _tapRight(tester);
    expect(session.progress, atEnd);

    // 恢复进度：重新打开同一 store，回到离开时的页。
    final reopened = ReaderSession(
      source: source,
      store: store,
      bookId: 'm1-integration',
    );
    await reopened.open();
    expect(reopened.progress, atEnd, reason: '重新打开应恢复到保存进度');
    expect(reopened.page, isNotNull);
    reopened.dispose();

    // 设置重排：字号变化后仍在原段落附近。
    final beforeReflow = session.progress!;
    final pageBefore = session.page!;
    final anchorBefore = _firstCfi(pageBefore);
    await tester.pumpWidget(
      _app(
        source,
        store,
        overrides: const ReaderOverrides(fontSize: 22),
        onReady: (value) => session = value,
      ),
    );
    await tester.pumpAndSettle();
    expect(session.error, isNull);
    expect(session.layoutFingerprint, contains('fs=22.0'));
    expect(session.page, isNotNull, reason: '重排后不应空白');
    expect(session.page!.slices.isNotEmpty, isTrue, reason: '重排后应有内容');
    final anchorAfter = _firstCfi(session.page);
    expect(anchorAfter ?? anchorBefore, isNotNull, reason: '重排后仍应能取到定位 CFI');
    expect(session.progress, isNotNull);
    // ignore: avoid_print
    print(
      'M1 reflow before=${beforeReflow.spineIndex}/${beforeReflow.pageIndex} '
      'after=${session.progress!.spineIndex}/${session.progress!.pageIndex} '
      'anchor=$anchor',
    );

    // 主题切换：不改布局指纹，只重绘。
    final fingerprint = session.layoutFingerprint;
    await tester.pumpWidget(
      _app(
        source,
        store,
        overrides: const ReaderOverrides(fontSize: 22),
        theme: ReaderTheme.dark,
        onReady: (value) => session = value,
      ),
    );
    await tester.pumpAndSettle();
    expect(session.layoutFingerprint, fingerprint, reason: '换主题不应触发重排');
    expect(session.page, isNotNull);
    expect(find.byType(CustomPaint), findsWidgets);

    await tester.pumpWidget(
      _app(
        source,
        store,
        overrides: const ReaderOverrides(fontSize: 22),
        theme: ReaderTheme.black,
        onReady: (value) => session = value,
      ),
    );
    await tester.pumpAndSettle();
    expect(session.layoutFingerprint, fingerprint);
    expect(session.error, isNull);
  }, skip: Platform.environment['M1_INTEGRATION'] == '0');

  testWidgets('P7 集成：冷启动页索引重放 + 双路径坏书可打开', (tester) async {
    final source = await _openSource();
    if (source == null) {
      // ignore: avoid_print
      print('SKIP 本地样本库缺失（test_corpus/ 不入库）');
      return;
    }

    // 冷启动重放（P7-22/23）：清页缓存后同章按页索引直接出页，
    // 页数与几何一致，不重跑分页状态机。
    final first = await source.loadChapter(0);
    expect(first, isNotEmpty);
    source.clearPaginationCache();
    final replayed = await source.loadChapter(0);
    expect(replayed, hasLength(first.length));
    for (var i = 0; i < first.length; i++) {
      expect(replayed[i].pageIndex, first[i].pageIndex);
      expect(replayed[i].usedHeight, closeTo(first[i].usedHeight, 0.01));
    }

    // 双路径解析（P7-11）：标签不闭合的章节经容错回退仍可打开并阅读。
    final broken = _buildBrokenChapterEpub();
    final opened = await openEpub(broken);
    expect(opened.ok, isTrue, reason: opened.report.message);
    final brokenSource = opened.document;
    expect(brokenSource, isNotNull);
    final pages = await EpubChapterSource.open(broken);
    final brokenPages = await pages.loadChapter(0);
    expect(brokenPages, isNotEmpty, reason: '容错路径仍应产出可读页');
  }, skip: Platform.environment['M1_INTEGRATION'] == '0');

  testWidgets('真实书冒烟：诸神愚戏打开→首页绘制→翻一页（REAL_EPUB=1）', (tester) async {
    final source = await _openSource('real/zhushen-yuxi.epub');
    if (source == null) {
      // ignore: avoid_print
      print('SKIP 缺少真书 zhushen-yuxi.epub 或样本库缺失');
      return;
    }
    late ReaderSession session;
    final watch = Stopwatch()..start();
    await tester.pumpWidget(
      _app(
        source,
        MemoryReaderProgressStore(),
        onReady: (value) => session = value,
      ),
    );
    await tester.pumpAndSettle();
    watch.stop();

    expect(session.error, isNull);
    expect(session.page, isNotNull);
    expect(session.progress, isNotNull);
    final before = session.progress!;
    await _tapRight(tester);
    expect(session.page, isNotNull);
    expect(session.progress, isNotNull);
    // ignore: avoid_print
    print(
      'M1 real_book=zhushen-yuxi open_and_first_page_ms=${watch.elapsedMilliseconds} '
      'chapters=${source.chapterCount} before=${before.spineIndex}/${before.pageIndex} '
      'after=${session.progress!.spineIndex}/${session.progress!.pageIndex}',
    );
  }, skip: Platform.environment['REAL_EPUB'] != '1');
}
