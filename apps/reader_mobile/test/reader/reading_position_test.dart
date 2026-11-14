import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart' show TocEntry;
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/book_progress_index.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_ui/reader_session.dart';

Uint8List _buildBook(List<String> chapters, {List<String>? bodies}) {
  final archive = Archive();
  void add(String name, String value) {
    final bytes = utf8.encode(value);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  const container =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>';
  add('mimetype', 'application/epub+zip');
  final manifest = StringBuffer();
  final spine = StringBuffer();
  for (var index = 0; index < chapters.length; index++) {
    manifest.write(
      '<item id="c$index" href="Text/c$index.xhtml" '
      'media-type="application/xhtml+xml"/>',
    );
    spine.write('<itemref idref="c$index"/>');
    add(
      'OEBPS/Text/c$index.xhtml',
      '<?xml version="1.0" encoding="UTF-8"?>'
          '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
          '${bodies?[index] ?? '<p>${chapters[index]}</p>'}</body></html>',
    );
  }
  add('META-INF/container.xml', container);
  add(
    'OEBPS/content.opf',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
        'unique-identifier="b"><metadata '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="b">urn:uuid:reading-position</dc:identifier>'
        '<dc:title>进度测试</dc:title><dc:language>zh</dc:language>'
        '<meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>'
        '</metadata><manifest>$manifest</manifest>'
        '<spine>$spine</spine></package>',
  );
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

String _text(int count) => List<String>.filled(count, '甲').join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('多章不等长书籍的字节比例可双向换算并支持 0%/100%', () async {
    final source = await EpubChapterSource.open(
      _buildBook(<String>[_text(100), _text(300), _text(100)]),
      verifyCrc: false,
    );
    addTearDown(source.close);
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'position-multi',
    );
    addTearDown(session.dispose);
    await session.open();
    expect(session.readingPercent, closeTo(0, 1e-9));

    expect(await session.seekToReadingPercent(0.5), isTrue);
    expect(session.progress?.spineIndex, 1);
    expect(session.readingPercent, closeTo(0.5, 0.02));

    expect(await session.seekToReadingPercent(1), isTrue);
    expect(session.progress?.spineIndex, 2);
    expect(session.readingPercent, closeTo(1, 1e-9));

    expect(await session.seekToReadingPercent(0), isTrue);
    expect(session.progress?.spineIndex, 0);
    expect(session.readingPercent, closeTo(0, 0.01));
  });

  test('单章书滑杆也能按章内比例跳转', () async {
    final source = await EpubChapterSource.open(
      _buildBook(<String>[_text(2000)]),
      verifyCrc: false,
    );
    addTearDown(source.close);
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'position-single',
    );
    addTearDown(session.dispose);
    await session.open();
    expect(await session.seekToReadingPercent(0.5), isTrue);
    expect(session.progress?.pageIndex, greaterThan(0));
    expect(session.readingPercent, closeTo(0.5, 0.02));
  });

  test('元数据不可用时等权估算仍支持章内比例和排除章节', () async {
    final source = await EpubChapterSource.open(
      _buildBook([_text(200), _text(600), _text(100)]),
      verifyCrc: false,
    );
    addTearDown(source.close);
    source.bindProgressIndex(
      BookProgressIndex.fromUncompressedSizes(
        [null, null, null],
        excluded: {2},
      ),
    );
    for (final percent in [0.0, 0.25, 0.75, 1.0]) {
      final cfi = (await source.prepareCfiForReadingPercent(percent))!;
      expect(source.readingPercentForCfi(cfi), closeTo(percent, 0.002));
      expect(spineIndexOfCfi(EpubCfi.parse(cfi)!), lessThan(2));
    }
  });

  test('目录目标优先使用 CFI，其次 fragment，最后才回退章首', () async {
    final source = await EpubChapterSource.open(
      _buildBook(
        <String>[_text(100), _text(300)],
        bodies: <String>[
          '<p>${_text(100)}</p>',
          '<p>${_text(100)}</p><p id="后半">${_text(200)}</p>',
        ],
      ),
      verifyCrc: false,
    );
    addTearDown(source.close);
    final chapter = await source.loadAnchorChapter(1);
    final firstChapter = await source.loadAnchorChapter(0);
    final targetOffset = chapter.text.length ~/ 2;
    final targetCfi = chapter.cfiAt(targetOffset)!;
    final direct = source.cfiForTocEntry(
      TocEntry(title: '后半', spineIndex: 1, cfi: EpubCfi.parse(targetCfi)),
    );
    expect(direct, targetCfi);
    final fallback = source.cfiForTocEntry(
      const TocEntry(title: '章首', spineIndex: 1),
    );
    expect(fallback, chapter.cfiAt(0));

    final fragment = source.cfiForTocEntry(
      const TocEntry(title: '后半', spineIndex: 1, fragment: '后半'),
    );
    expect(fragment, isNot(chapter.cfiAt(0)));
    final parsedFragment = EpubCfi.parse(fragment!);
    expect(parsedFragment, isNotNull);
    expect(spineIndexOfCfi(parsedFragment!), 1);

    final invalidDirect = source.cfiForTocEntry(
      TocEntry(
        title: '后半',
        spineIndex: 1,
        fragment: '后半',
        cfi: EpubCfi.parse(firstChapter.cfiAt(0)!),
      ),
    );
    expect(invalidDirect, fragment, reason: '跨 spine 的目录 CFI 应改用 fragment');
    final invalidPath = source.cfiForTocEntry(
      TocEntry(
        title: '后半',
        spineIndex: 1,
        fragment: '后半',
        cfi: EpubCfi.parse('epubcfi(/6/4!/4/9998:0)'),
      ),
    );
    expect(invalidPath, fragment, reason: '同章无效目录 CFI 应改用 fragment');

    expect(
      source.cfiForTocEntry(
        const TocEntry(title: '无命中', spineIndex: 1, fragment: '不存在'),
      ),
      chapter.cfiAt(0),
    );
  });

  test('含空白与段首缩进的章节按聚合原文偏移往返定位', () async {
    final source = await EpubChapterSource.open(
      _buildBook(
        const <String>['空白'],
        bodies: const <String>[
          '<p style="white-space:pre-wrap">  甲  乙\n  丙 丁\n戊  </p>',
        ],
      ),
      verifyCrc: false,
    );
    addTearDown(source.close);
    final chapter = await source.loadAnchorChapter(0);
    int weightAt(String cfi) {
      final offset = chapter.offsetFor(cfi);
      expect(offset, isNotNull);
      return offset!;
    }

    for (var offset = 0; offset <= chapter.text.length; offset++) {
      final cfi = chapter.cfiAt(offset);
      if (cfi == null) continue;
      final percent = source.readingPercentForCfi(cfi);
      expect(percent, isNotNull);
      final roundTrip = source.cfiForReadingPercent(percent!);
      expect(roundTrip, isNotNull);
      expect(
        (weightAt(roundTrip!) - weightAt(cfi)).abs(),
        lessThanOrEqualTo(1),
        reason: '原文偏移 $offset',
      );
    }
  });

  test('千章书建立字节比例只准备目标 CFI 的章节原文', () async {
    final source = await EpubChapterSource.open(
      _buildBook(List<String>.filled(1000, _text(100))),
      verifyCrc: false,
    );
    addTearDown(source.close);
    expect(source.progressIndex.estimated, isFalse);
    expect(source.anchorPreparationCount, 0);
    final chapter = await source.loadAnchorChapter(777);
    final cfi = chapter.cfiAt(chapter.text.length ~/ 2)!;
    final percent = source.readingPercentForCfi(cfi)!;
    expect(source.cfiForReadingPercent(percent), cfi);
    expect(source.anchorPreparationCount, 1);
  });

  test('同一 CFI 的全书百分比不随字号往返改变', () async {
    final source = await EpubChapterSource.open(
      _buildBook([_text(100), _text(600), _text(100)]),
      verifyCrc: false,
    );
    addTearDown(source.close);
    final chapter = await source.loadAnchorChapter(1);
    final cfi = chapter.cfiAt(chapter.text.length ~/ 2)!;
    final original = source.readingPercentForCfi(cfi);
    for (final size in [21.0, 22.0, 17.0]) {
      await source.applyOverrides(ReaderOverrides(fontSize: size));
      await source.loadChapter(1);
      expect(source.readingPercentForCfi(cfi), original);
    }
  });

  test('连续翻页跨过缓存容量后仍有真实百分比且可保存位置', () async {
    final source = await EpubChapterSource.open(
      _buildBook(List.filled(8, _text(150))),
    );
    final store = MemoryReaderProgressStore();
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: 'page-turn-position',
      contentRevision: 'r1',
    );
    addTearDown(() async {
      session.dispose();
      source.close();
      await source.preparationsStopped;
    });
    await session.open(contentWidth: 200, contentHeight: 200);
    final visited = <int>{};
    for (final next in [true, false]) {
      for (var i = 0; i < 12; i++) {
        final origin = session.page;
        final preview = await session.preparePageTurn(next, prefetch: true);
        if (preview == null) break;
        final previewPercent = session.readingPercentOf(preview.target.content);
        expect(previewPercent, isNotNull);
        expect(session.page, same(origin), reason: '预热不改变当前页');
        final turn = await session.preparePageTurn(next);
        expect(turn, isNotNull);
        expect(session.commitPageTurn(turn!), isTrue);
        visited.add(session.progress!.spineIndex);
        expect(session.readingPercent, previewPercent, reason: '预热与落页使用同一比例');
        await session.flushProgress();
        final saved = await store.load('page-turn-position');
        expect(saved?.cfi, session.readingCfi);
        expect(saved?.readingPercent, session.readingPercent);
      }
    }
    expect(
      visited.length,
      greaterThan(EpubChapterSource.documentCacheChapterLimit),
    );
  });

  test('原文缓存淘汰后纸面比例稳定，实际翻页仍重新准备当前正文', () async {
    final source = await EpubChapterSource.open(
      _buildBook(List.filled(8, _text(100))),
    );
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'cached-page-percent',
    );
    addTearDown(() async {
      session.dispose();
      source.close();
      await source.preparationsStopped;
    });
    await session.open(contentWidth: 300, contentHeight: 500);
    expect(session.chapterPageCount, 1);
    final preview = (await session.preparePageTurn(true, prefetch: true))!;
    final target = preview.target.content;
    final cfi = session.cfiAtPageOffset(target, null)!;
    final percent = session.readingPercentOf(target);
    expect(percent, isNotNull);
    for (var spine = 2; spine < 8; spine++) {
      final chapter = await source.loadAnchorChapter(spine);
      expect(source.readingPercentForCfi(chapter.cfiAt(0)), isNotNull);
    }
    expect(source.readingPercentForCfi(cfi), isNull);
    expect(session.readingPercentOf(target), percent);
    final turn = (await session.preparePageTurn(true))!;
    expect(source.readingPercentForCfi(cfi), percent);
    expect(session.commitPageTurn(turn), isTrue);
    expect(session.readingPercent, percent);
    await session.flushProgress();
  });

  test('百分比定位准备的空值不阻断就绪后重新计算', () async {
    final source = await EpubChapterSource.open(_buildBook([_text(2000)]));
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: 'preparing-percent',
    );
    addTearDown(() async {
      session.dispose();
      source.close();
      await source.preparationsStopped;
    });
    await session.open(contentWidth: 300, contentHeight: 400);
    final cfi = source.anchorChapter(0).cfiAt(60)!;
    final percent = source.readingPercentForCfi(cfi);
    expect(
      session.stageViewportSnapshot(
        ReaderViewportSnapshot(
          spineIndex: 0,
          pageIndex: 0,
          scrollOffset: 10,
          generation: session.generation,
          cfi: cfi,
        ),
      ),
      isTrue,
    );
    await source.applyContentSize(width: 260, height: 400);
    expect(session.readingPercent, isNull);
    await source.loadAnchorChapter(0);
    expect(session.readingPercent, percent);
  });

  test('暂存滚动位置后调整边距，定位准备期间可读进度且最终正常落盘', () async {
    final source = await EpubChapterSource.open(_buildBook([_text(2000)]));
    final store = MemoryReaderProgressStore();
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: 'resize-position',
      contentRevision: 'r1',
    );
    addTearDown(() async {
      session.dispose();
      source.close();
      await source.preparationsStopped;
    });
    await session.open(contentWidth: 300, contentHeight: 400);
    final cfi = source.anchorChapter(0).cfiAt(60)!;
    final percent = source.readingPercentForCfi(cfi);
    expect(
      session.stageViewportSnapshot(
        ReaderViewportSnapshot(
          spineIndex: 0,
          pageIndex: 0,
          scrollOffset: 10,
          generation: session.generation,
          cfi: cfi,
        ),
      ),
      isTrue,
    );
    session.addListener(() {
      expect(session.bookProgress, inInclusiveRange(0, 1));
      expect(session.progress, isNotNull);
    });
    await session.applyContentSize(width: 260, height: 400, preview: true);
    await session.applyContentSize(width: 260, height: 400);
    expect(session.error, isNull);
    expect(session.readingPercent, percent);
    await session.flushProgress();
    final saved = await store.load('resize-position');
    expect(saved?.cfi, cfi);
    expect(saved?.readingPercent, percent);
  });
}
