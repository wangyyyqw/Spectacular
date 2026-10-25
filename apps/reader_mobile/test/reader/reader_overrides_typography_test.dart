import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

Uint8List _epub(String css, String body, {bool heading = true}) {
  final archive = Archive();
  void add(String name, String content) {
    final bytes = Uint8List.fromList(utf8.encode(content));
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  archive.addFile(ArchiveFile('mimetype', 20, 'application/epub+zip'.codeUnits));
  add(
    'META-INF/container.xml',
    '<?xml version="1.0"?><container version="1.0" '
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>'
    '<rootfile full-path="OEBPS/content.opf" '
    'media-type="application/oebps-package+xml"/></rootfiles></container>',
  );
  add(
    'OEBPS/content.opf',
    '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" '
    'version="3.0" unique-identifier="uid">'
    '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:identifier id="uid">urn:uuid:ov-test-1</dc:identifier>'
    '<dc:title>Ov</dc:title><dc:language>zh</dc:language></metadata>'
    '<manifest>'
    '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
    '<item id="css" href="s.css" media-type="text/css"/>'
    '</manifest><spine><itemref idref="c1"/></spine></package>',
  );
  add(
    'OEBPS/c1.xhtml',
    '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
    '<link href="s.css" type="text/css" rel="stylesheet"/>'
    '</head><body>${heading ? '<h2>标题</h2>' : ''}$body</body></html>',
  );
  add('OEBPS/s.css', css);
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

const _bookCss =
    'h2 { font-size: 24px; margin-top: 1em; margin-bottom: 1em; }'
    'p { font-size: 16px; line-height: 130%; '
    'margin-top: 1em; margin-bottom: 1em; }';

Future<List<PageBlock>> _blocks(ReaderOverrides? overrides) async {
  final source = await EpubChapterSource.open(
    _epub(_bookCss, '<p>正文一段${'字' * 40}</p><p>正文二段${'字' * 40}</p>'),
  );
  await source.applyContentSize(width: 300, height: 600);
  if (overrides != null) {
    await source.applyOverrides(overrides);
  }
  return (await source.loadChapter(0))
      .expand((page) => page.slices.map((s) => s.block))
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('阅读器字号/行高覆盖作者 CSS（reader origin 优先）', () async {
    const overrides = ReaderOverrides(fontSize: 20, lineHeight: 1.8);
    final blocks = await _blocks(overrides);
    final paragraphs = blocks
        .where((b) => b.layout.text.contains('正文'))
        .toList();
    expect(paragraphs, isNotEmpty);
    for (final block in paragraphs) {
      expect(block.style!.fontSize, 20, reason: '字号覆盖作者声明');
      expect(
        block.style!.lineHeight,
        closeTo(36, 0.01),
        reason: '行高 1.8 × 20dp',
      );
      expect(block.layout.maxWidth, greaterThan(0));
    }
  });

  test('段距设置生效且相邻折叠后等于设置值', () async {
    const overrides = ReaderOverrides(paragraphSpacing: 8);
    final source = await EpubChapterSource.open(
      _epub(
        _bookCss,
        '<p>正文一段${'字' * 40}</p><p>正文二段${'字' * 40}</p>',
        heading: false,
      ),
    );
    await source.applyContentSize(width: 300, height: 600);
    await source.applyOverrides(overrides);
    final pages = await source.loadChapter(0);
    final slices = pages.first.slices
        .where((s) => s.block.layout.text.contains('正文'))
        .toList();
    expect(slices.length, greaterThanOrEqualTo(2));
    expect(slices[0].block.spaceBefore, 8, reason: '首段段前距取设置值');
    expect(slices[0].block.spaceAfter, 0, reason: '段后距折叠并入下段');
    expect(slices[1].block.spaceBefore, 8, reason: '下段段前距折叠结果');
    expect(slices[1].block.spaceAfter, 8, reason: '末段段后距保留设置值');
    expect(slices[1].leadingExtent, 8, reason: '折叠后段距 = 8，而非 8+8');
  });

  test('标题不参与正文字号/段距覆盖', () async {
    const overrides = ReaderOverrides(fontSize: 20, paragraphSpacing: 8);
    final blocks = await _blocks(overrides);
    final heading = blocks.firstWhere((b) => b.layout.text.contains('标题'));
    expect(heading.style!.fontSize, 24, reason: '标题字号跟随书籍样式');
    expect(heading.spaceBefore, 24, reason: '标题段前距保留 1em（24px）');
  });

  test('段距进排版指纹（设置变更触发重排）', () {
    const a = ReaderOverrides(paragraphSpacing: 8);
    const b = ReaderOverrides(paragraphSpacing: 12);
    expect(a.fingerprint, isNot(b.fingerprint));
    expect(
      ReaderOverrides().fingerprint,
      isNot(a.fingerprint),
      reason: '未设置与设置值必须区分',
    );
  });
}
