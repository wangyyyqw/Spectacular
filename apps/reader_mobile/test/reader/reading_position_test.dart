import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart' show TocEntry;
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/locator.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';
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

  test('多章不等长书籍的字符比例可双向换算并支持 0%/100%', () async {
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

  test('旧字符统计为空时等权估算仍支持章内比例和排除章节', () async {
    final source = await EpubChapterSource.open(
      _buildBook([_text(200), _text(600), _text(100)]),
      verifyCrc: false,
    );
    addTearDown(source.close);
    source.bindProgressWeights(
      ProgressWeights.fromCharCounts([0, 0, 0], excluded: {2}),
    );
    for (final percent in [0.0, 0.25, 0.75, 1.0]) {
      final cfi = source.cfiForReadingPercent(percent)!;
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
    final chapter = source.anchorChapter(1);
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
        cfi: EpubCfi.parse(source.anchorChapter(0).cfiAt(0)!),
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

  test('含空白与段首缩进的章节按非空白字符往返定位', () async {
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
    final chapter = source.anchorChapter(0);
    int weightAt(String cfi) {
      final offset = chapter.offsetFor(cfi);
      expect(offset, isNotNull);
      return chapter.text
          .substring(0, offset!)
          .replaceAll(RegExp(r'\s'), '')
          .length;
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
}
