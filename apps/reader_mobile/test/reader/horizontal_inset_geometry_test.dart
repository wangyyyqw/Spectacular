import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

/// 构造带作者 CSS 的最小 EPUB。
Uint8List _buildEpub(String css, String bodyHtml) {
  final archive = Archive();
  void addText(String name, String content) {
    final bytes = Uint8List.fromList(utf8.encode(content));
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  archive.addFile(ArchiveFile('mimetype', 20, 'application/epub+zip'.codeUnits));
  addText(
    'META-INF/container.xml',
    '<?xml version="1.0"?>'
    '<container version="1.0" '
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
    '<rootfiles><rootfile full-path="OEBPS/content.opf" '
    'media-type="application/oebps-package+xml"/></rootfiles></container>',
  );
  addText(
    'OEBPS/content.opf',
    '<?xml version="1.0"?>'
    '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
    'unique-identifier="uid">'
    '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:identifier id="uid">urn:uuid:inset-test-0001</dc:identifier>'
    '<dc:title>Inset</dc:title><dc:language>zh</dc:language></metadata>'
    '<manifest>'
    '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
    '<item id="css" href="style.css" media-type="text/css"/>'
    '</manifest><spine><itemref idref="c1"/></spine></package>',
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

  test('块级水平外边距进排版宽度：正文不右溢出、左右留白对称', () async {
    const contentWidth = 300.0;
    // 真机书的典型作者 CSS：body/p 各 1% 左右外边距（诸神愚戏/克拉夫特）。
    final source = await EpubChapterSource.open(
      _buildEpub(
        'body { margin-left: 1%; margin-right: 1%; }'
        'p { margin-left: 1%; margin-right: 1%; text-align: justify; '
        'text-indent: 2em; }',
        '<p>${'正' * 240}</p>',
      ),
    );
    await source.applyContentSize(width: contentWidth, height: 600);
    final slices = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .where((slice) => slice.block.layout.text.trim().isNotEmpty)
        .toList();
    expect(slices, isNotEmpty);

    for (final slice in slices) {
      final style = slice.block.style!;
      final layout = slice.block.layout;
      // 绘制左缘 = 切片内缩（border+padding）+ 外边距。
      final paintLeft =
          slice.leftInset + style.margin.left;
      final rightInset = style.margin.right +
          style.padding.right +
          style.borders.right.width;
      expect(
        layout.maxWidth,
        closeTo(contentWidth - style.margin.horizontal, 0.5),
        reason: '排版宽度应扣除左右外边距',
      );
      final lineRight = layout.lines
          .map((line) => line.offsetX + line.width)
          .reduce(math.max);
      expect(
        paintLeft + lineRight,
        lessThanOrEqualTo(contentWidth - rightInset + 0.5),
        reason: '行盒右缘不得越过正文区右内缩边界（否则被裁切）',
      );
      expect(
        paintLeft,
        closeTo(
          style.margin.left + style.padding.left + style.borders.left.width,
          0.5,
        ),
        reason: '绘制左缘与排版内缩同源',
      );
    }
  });
}
