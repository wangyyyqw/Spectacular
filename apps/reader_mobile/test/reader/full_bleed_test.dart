import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';

Future<Uint8List> _pngBytes(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF3F51B5),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Uint8List _buildEpub(Uint8List pngBytes) {
  final archive = Archive();
  void addText(String name, String content) {
    final bytes = Uint8List.fromList(content.codeUnits);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  archive.addFile(
    ArchiveFile('mimetype', 20, 'application/epub+zip'.codeUnits),
  );
  addText('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''');
  addText('OEBPS/content.opf', '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:1234-5678</dc:identifier>
    <dc:title>FullBleed</dc:title>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>
    <item id="pic" href="images/pic.png" media-type="image/png"/>
  </manifest>
  <spine><itemref idref="c1"/><itemref idref="c2"/></spine>
</package>''');
  addText(
    'OEBPS/c1.xhtml',
    '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>文字章节</p></body></html>',
  );
  addText(
    'OEBPS/c2.xhtml',
    '<html xmlns="http://www.w3.org/1999/xhtml"><body><img src="images/pic.png"/></body></html>',
  );
  archive.addFile(
    ArchiveFile('OEBPS/images/pic.png', pngBytes.length, pngBytes),
  );
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('满屏章：单图章走整页单块背景图路径，文字章走普通路径', () async {
    final source = await EpubChapterSource.open(
      _buildEpub(await _pngBytes(64, 48)),
    );

    // 文字章：普通路径（多块文本）。
    final normal = await source.loadChapter(0);
    expect(normal, isNotEmpty);
    expect(source.fullBleedAnalysis(0).isFullBleed, isFalse);

    // 图片章：满屏路径 → 单页、整页高、背景图 cover。
    await source.loadAnchorChapter(1);
    expect(source.fullBleedAnalysis(1).isFullBleed, isTrue);
    final pages = await source.loadChapter(1);
    expect(pages, hasLength(1));
    final page = pages.single;
    expect(page.slices, hasLength(1));
    final block = page.slices.single.block;
    expect(block.style!.backgroundImage, 'OEBPS/images/pic.png');
    expect(
      block.style!.backgroundSize.mode,
      CssBackgroundSizeMode.cover,
      reason: '背景图按 cover 铺满整页',
    );
    expect(page.usedHeight, greaterThan(0));
  });
}
