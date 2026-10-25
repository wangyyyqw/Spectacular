import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

Uint8List _epub(String bodyHtml, String css) {
  final archive = Archive();
  void addText(String name, String content) {
    final b = utf8.encode(content);
    archive.addFile(ArchiveFile(name, b.length, b));
  }
  archive.addFile(ArchiveFile('mimetype', 20, 'application/epub+zip'.codeUnits));
  addText('META-INF/container.xml',
      '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>');
  addText('OEBPS/content.opf',
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="uid">u</dc:identifier><dc:title>t</dc:title><dc:language>zh</dc:language></metadata><manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/><item id="css" href="style.css" media-type="text/css"/></manifest><spine><itemref idref="c1"/></spine></package>');
  addText('OEBPS/c1.xhtml',
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><link href="style.css" type="text/css" rel="stylesheet"/></head><body>$bodyHtml</body></html>');
  addText('OEBPS/style.css', css);
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('P8-09 ::before/::after content 注入块首尾', () async {
    final source = await EpubChapterSource.open(_epub(
      '<p class="q">引用文字</p>',
      'p.q::before { content: "「"; } p.q::after { content: "」"; }',
    ));
    final block = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .first;
    expect(block.layout.text, '「引用文字」', reason: '伪元素生成内容拼接');
  });

  test('P8-09 ::first-letter 首字放大 run', () async {
    final source = await EpubChapterSource.open(_epub(
      '<p class="drop">下沉段落正文。</p>',
      'p.drop::first-letter { font-size: 3em; color: #B71C1C; }',
    ));
    final block = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .first;
    final run = block.layout.runs.firstWhere(
      (r) => r.end - r.start == 1,
      orElse: () => throw StateError('未产出首字 run'),
    );
    expect(block.layout.text.substring(run.start, run.end), '下');
    expect(run.style.fontSize, greaterThan(block.style!.fontSize * 2),
        reason: '3em 首字');
  });

  test('attr() 取元素属性', () async {
    final source = await EpubChapterSource.open(_epub(
      '<p class="ref" data-mark="注">正文</p>',
      'p.ref::after { content: attr(data-mark); }',
    ));
    final block = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .first;
    expect(block.layout.text, '正文注');
  });
}
