import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

/// 构造带 link 作者 CSS 的最小 EPUB（真实书适配回归）。
Uint8List _buildEpubWithCss(String css, String bodyHtml) {
  final archive = Archive();
  void addText(String name, String content) {
    final bytes = Uint8List.fromList(utf8.encode(content));
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  archive.addFile(
    ArchiveFile('mimetype', 20, 'application/epub+zip'.codeUnits),
  );
  addText(
    'META-INF/container.xml',
    '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''',
  );
  addText(
    'OEBPS/content.opf',
    '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:css-test-0001</dc:identifier>
    <dc:title>CssStyle</dc:title>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
    <item id="css" href="style.css" media-type="text/css"/>
  </manifest>
  <spine><itemref idref="c1"/></spine>
</package>''',
  );
  addText(
    'OEBPS/c1.xhtml',
    '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
    '<link href="style.css" type="text/css" rel="stylesheet"/>'
    '</head><body>$bodyHtml</body></html>',
  );
  addText('OEBPS/style.css', css);
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('作者 p 规则：首行缩进/两端对齐/行距生效', () async {
    final source = await EpubChapterSource.open(_buildEpubWithCss(
      'p { text-align: justify; text-indent: 2em; line-height: 130%; }',
      '<p>正文段落，验证作者 CSS 的首行缩进与两端对齐是否进入 flat 管线。</p>',
    ));
    final block = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .first;
    final style = block.style!;
    expect(style.textIndent, isNotNull, reason: 'text-indent: 2em 解析');
    expect(style.textAlign, CssTextAlign.justify, reason: 'text-align: justify');
    expect(style.lineHeight, greaterThan(style.fontSize * 1.2),
        reason: 'line-height: 130% 相对字号解算');
  });

  test('作者 class 规则：h2.cls 居中覆盖 UA 左对齐', () async {
    final source = await EpubChapterSource.open(_buildEpubWithCss(
      'h2.chapter { text-align: center; }',
      '<h2 class="chapter">第一章 标题</h2><p>正文。</p>',
    ));
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .toList();
    final title = blocks.firstWhere((b) => b.layout.text.contains('第一章'));
    expect(title.style!.textAlign, CssTextAlign.center,
        reason: 'h2.chapter 类选择器命中');
    final body = blocks.firstWhere((b) => b.layout.text.contains('正文'));
    expect(body.style!.textAlign, isNot(CssTextAlign.center),
        reason: 'class 规则不串扰到无 class 的 p');
  });

  test('行内样式区间：span 类规则着色进入混排 runs', () async {
    final source = await EpubChapterSource.open(_buildEpubWithCss(
      'span.hl { color: #fc8c23; font-weight: bold; }',
      '<p>前文<span class="hl">高亮文字</span>后文</p>',
    ));
    final block = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .first;
    final runs = block.layout.runs;
    expect(runs, hasLength(1), reason: '高亮区间产出一条 StyledRun');
    expect(block.layout.text.substring(runs.first.start, runs.first.end),
        '高亮文字');
    expect(runs.first.style.color, const Color(0xFFFC8C23));
  });

  test('无 link 的书不受影响（UA 默认路径）', () async {
    final archive = Archive();
    void addText(String name, String content) {
      final bytes = Uint8List.fromList(utf8.encode(content));
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    archive.addFile(
      ArchiveFile('mimetype', 20, 'application/epub+zip'.codeUnits),
    );
    addText(
      'META-INF/container.xml',
      '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''',
    );
    addText(
      'OEBPS/content.opf',
      '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:no-css-0001</dc:identifier>
    <dc:title>NoCss</dc:title>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest>
  <spine><itemref idref="c1"/></spine>
</package>''',
    );
    addText(
      'OEBPS/c1.xhtml',
      '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>普通段落。</p></body></html>',
    );
    final source = await EpubChapterSource.open(
      Uint8List.fromList(ZipEncoder().encodeBytes(archive)),
    );
    final block = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .first;
    expect(block.style!.textIndent, 0.0, reason: '无作者 CSS 无首行缩进');
  });
}
