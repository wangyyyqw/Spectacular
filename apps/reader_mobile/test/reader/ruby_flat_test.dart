import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('P8-08 ruby 注音：rt 不进正文流、标注透传渲染层', () async {
    final archive = Archive();
    void addText(String name, String content) {
      final b = utf8.encode(content);
      archive.addFile(ArchiveFile(name, b.length, b));
    }
    archive.addFile(ArchiveFile('mimetype', 20, 'application/epub+zip'.codeUnits));
    addText('META-INF/container.xml',
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>');
    addText('OEBPS/content.opf',
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="uid">urn:uuid:ruby-0001</dc:identifier><dc:title>Ruby</dc:title><dc:language>ja</dc:language></metadata><manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c1"/></spine></package>');
    addText('OEBPS/c1.xhtml',
        '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
        '<p><ruby>漢字<rp>（</rp><rt>かんじ</rt><rp>）</rp></ruby>のテスト。</p>'
        '</body></html>');
    final source = await EpubChapterSource.open(
        Uint8List.fromList(ZipEncoder().encodeBytes(archive)));
    final block = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .first;
    expect(block.layout.text, contains('漢字'), reason: '主文本进流');
    expect(block.layout.text, isNot(contains('かんじ')), reason: '注音不进正文流');
    expect(block.layout.text, isNot(contains('（')), reason: 'rp 括号不进流');
    expect(block.rubies, hasLength(1));
    expect(block.rubies!.single.text, 'かんじ');
    final ruby = block.rubies!.single;
    expect(block.layout.text.substring(ruby.start, ruby.end), '漢字',
        reason: '注音区间覆盖主文本');
  });
}
