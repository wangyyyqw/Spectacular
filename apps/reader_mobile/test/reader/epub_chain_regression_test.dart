import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_ui/reader_session.dart';

import 'support/css_chapter_book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('行内块级链接正文进入真实章节分页并保留 CFI', () async {
    final source = await openCssChapter(
      body: '<a href="c.xhtml"><div>链接正文</div></a><p>结尾</p>',
    );
    addTearDown(source.close);
    final slices = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .toList();
    final text = slices.map((slice) => slice.block.layout.text).join('|');
    expect(text, contains('链接正文'));
    expect(text, contains('结尾'));
    expect(
      slices.any((slice) => slice.block.startCfi != null),
      isTrue,
      reason: '块级链接后代必须保留原始 CFI',
    );
  });

  test('正文 CDATA 内容进入真实章节分页', () async {
    final source = await openCssChapter(body: '<p>前<![CDATA[甲 < 乙 & 丙]]>后</p>');
    addTearDown(source.close);
    final text = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .map((slice) => slice.block.layout.text)
        .join();
    expect(text, contains('前甲 < 乙 & 丙后'));
  });

  test('内联 pre-wrap 应保留空格和换行', () async {
    final source = await openCssChapter(
      body: '<p style="white-space:pre-wrap">甲  乙\n丙</p>',
    );
    addTearDown(source.close);
    final block = (await source.loadChapter(0)).first.slices.first.block;
    expect(block.style!.whiteSpace, CssWhiteSpace.preWrap);
    expect(block.layout.text, '甲  乙\n丙');
  });

  test('内联自定义属性应进入变量解析', () async {
    final source = await openCssChapter(
      body: '<p style="--size:28px;font-size:var(--size)">变量字号</p>',
    );
    addTearDown(source.close);
    final block = (await source.loadChapter(0)).first.slices.first.block;
    expect(block.style!.fontSize, 28);
  });

  test('内联变量名保留大小写、复用前缀别名并阻断私有属性', () async {
    final source = await openCssChapter(
      body:
          '<p style="--Size:28px;--size:12px;font-size:var(--Size);'
          '-duokan-text-decoration:underline;-reader-audit:1">内联声明</p>',
    );
    addTearDown(source.close);
    final style = (await source.loadChapter(0)).first.slices.first.block.style!;
    expect(style.fontSize, 28);
    expect(style.values['--Size'], '28px');
    expect(style.values['--size'], '12px');
    expect(style.textDecoration, CssTextDecoration.underline);
    expect(style.values.containsKey('-reader-audit'), isFalse);
  });

  test('视口变化后外链 pre-wrap 应保留原文', () async {
    final source = await openCssChapter(
      body: '<p>甲  乙\n丙</p>',
      css: '@media (min-width:400px) {p {white-space:pre-wrap}}',
      contentWidth: 300,
    );
    addTearDown(source.close);
    final first = (await source.loadChapter(0)).first.slices.first.block;
    expect(first.layout.text, '甲 乙 丙');
    await source.applyContentSize(width: 500, height: 500);
    final after = (await source.loadChapter(0)).first.slices.first.block;
    expect(after.style!.whiteSpace, CssWhiteSpace.preWrap);
    expect(after.layout.text, '甲  乙\n丙');
  });

  test('字体 URL 应相对样式表目录解析', () async {
    final fontBytes = File('assets/fonts/SourceHanSerifCN-Regular.otf')
        .readAsBytesSync();
    final source = await openCssChapter(
      body: '<p>字体目录复现</p>',
      css:
          '@font-face {font-family:auditfont;src:url("Fonts/shared.otf");}'
          'p {font-family:auditfont,serif;}',
      binaryFiles: {
        'OEBPS/Styles/Fonts/shared.otf': fontBytes,
        'OEBPS/Other/Fonts/shared.otf': fontBytes,
      },
    );
    addTearDown(source.close);
    final block = (await source.loadChapter(0)).first.slices.first.block;
    expect(block.style!.fontFamily, startsWith('bi_'));
  });

  test('缺失章节应允许读取后续完好章节', () async {
    final archive = ZipDecoder().decodeBytes(
      buildCssChapterBook(body: '<p>首章完好</p>'),
    );
    final opfFile = archive.findFile('OEBPS/content.opf')!;
    final opf = utf8
        .decode(opfFile.content)
        .replaceFirst(
          '</manifest>',
          '<item id="missing" href="Text/missing.xhtml" media-type="application/xhtml+xml"/>'
              '<item id="last" href="Text/last.xhtml" media-type="application/xhtml+xml"/></manifest>',
        )
        .replaceFirst(
          '</spine>',
          '<itemref idref="missing"/><itemref idref="last"/></spine>',
        );
    final opfBytes = utf8.encode(opf);
    archive.addFile(
      ArchiveFile('OEBPS/content.opf', opfBytes.length, opfBytes),
    );
    final lastBytes = utf8.encode(
      '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>末章完好</p></body></html>',
    );
    archive.addFile(
      ArchiveFile('OEBPS/Text/last.xhtml', lastBytes.length, lastBytes),
    );
    final source = await EpubChapterSource.open(
      Uint8List.fromList(ZipEncoder().encodeBytes(archive)),
      verifyCrc: false,
    );
    addTearDown(source.close);
    expect(source.document.report.readabilityLevel, 2);
    final session = ReaderSession(
      source: source,
      store: MemoryReaderProgressStore(),
      bookId: '缺章审计',
    );
    addTearDown(session.dispose);
    await session.open();
    expect(session.currentText, contains('首章完好'));
    await session.next();
    expect(session.currentText, contains('末章完好'));
  });

  test('导入 CSS 与内嵌样式分别以自身来源解析字体 URL', () async {
    final fontBytes = File('assets/fonts/SourceHanSerifCN-Regular.otf')
        .readAsBytesSync();
    for (final inline in [false, true]) {
      final source = await openCssChapter(
        body: inline
            ? '<style>@font-face {font-family:nested;src:url("Fonts/shared.otf");}'
                  'p {font-family:nested}</style><p>内嵌字体来源</p>'
            : '<p>导入字体来源</p>',
        css: inline ? '' : '@import "nested/face.css";',
        binaryFiles: {
          'OEBPS/Styles/nested/face.css': utf8.encode(
            '@font-face {font-family:nested;src:url("Fonts/shared.otf");}'
            'p {font-family:nested}',
          ),
          if (inline)
            'OEBPS/Text/Fonts/shared.otf': fontBytes
          else
            'OEBPS/Styles/nested/Fonts/shared.otf': fontBytes,
          'OEBPS/Other/Fonts/shared.otf': const [1, 2, 3, 4],
        },
      );
      addTearDown(source.close);
      final block = (await source.loadChapter(0)).first.slices.first.block;
      expect(block.style!.fontFamily, startsWith('bi_'), reason: '$inline');
    }
  });

  test('UTF-16 样式表可被章节源读取并生效', () async {
    final css = _utf16('p { font-size: 28px; color: #112233; }', Endian.little);
    final source = await EpubChapterSource.open(
      _buildBookWithRawCss(body: '<p>UTF-16 样式</p>', cssBytes: css),
      verifyCrc: false,
    );
    addTearDown(source.close);
    final block = (await source.loadChapter(0)).first.slices.first.block;
    expect(block.style!.fontSize, 28);
  });
}

Uint8List _utf16(String text, Endian endian) {
  final output = BytesBuilder(copy: false);
  output.add(
    endian == Endian.little ? const <int>[0xFF, 0xFE] : const <int>[0xFE, 0xFF],
  );
  for (final unit in text.codeUnits) {
    if (endian == Endian.little) {
      output.add(<int>[unit & 0xFF, (unit >> 8) & 0xFF]);
    } else {
      output.add(<int>[(unit >> 8) & 0xFF, unit & 0xFF]);
    }
  }
  return output.toBytes();
}

Uint8List _buildBookWithRawCss({
  required String body,
  required Uint8List cssBytes,
}) {
  final archive = Archive();
  void add(String name, List<int> bytes) {
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('mimetype', utf8.encode('application/epub+zip'));
  add(
    'META-INF/container.xml',
    utf8.encode(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>',
    ),
  );
  add(
    'OEBPS/content.opf',
    utf8.encode(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="b"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="b">urn:uuid:utf16-css</dc:identifier>'
      '<dc:title>t</dc:title><dc:language>zh</dc:language>'
      '<meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>'
      '</metadata><manifest>'
      '<item id="c" href="Text/c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="s" href="Styles/s.css" media-type="text/css"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
    ),
  );
  add(
    'OEBPS/Text/c.xhtml',
    utf8.encode(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
      '<link rel="stylesheet" type="text/css" href="../Styles/s.css"/>'
      '</head><body>$body</body></html>',
    ),
  );
  add('OEBPS/Styles/s.css', cssBytes);
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}
