import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

const galleryImageUrl = 'OPS/image.png';

/// 让核心布局和阅读页共用真实 EPUB，图片与正文同段，保留边距和独立题注。
Uint8List inlineGalleryEpub({String extraStyle = ''}) {
  final resources = {
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml':
        '<container><rootfiles>'
        '<rootfile full-path="OPS/book.opf"/></rootfiles></container>',
    'OPS/book.opf': '''
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">行内画廊</dc:identifier><dc:title>行内画廊</dc:title><dc:language>zh</dc:language></metadata>
<manifest><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/><item id="image" href="image.png" media-type="image/png"/></manifest>
<spine><itemref idref="chapter"/></spine></package>''',
    'OPS/chapter.xhtml': _chapter(extraStyle),
  };
  final archive = Archive();
  for (final entry in resources.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(
      entry.key == 'mimetype'
          ? ArchiveFile.noCompress(entry.key, bytes.length, bytes)
          : ArchiveFile.bytes(entry.key, bytes),
    );
  }
  archive.addFile(
    ArchiveFile.bytes(
      galleryImageUrl,
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
      ),
    ),
  );
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

String _chapter(String extraStyle) =>
    '''
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>行内画廊</title><style>
body { margin: 0; }
p { margin: 0; font-size: 16px; line-height: 1.25; }
.duokan-image-gallery { margin: 9px 16px; padding: 4px; border: 2px solid; }
.picture { margin: 5px 7px; padding: 3px 5px; }
img { width: 40px; height: 40px; margin: 7px 3px 5px 9px; vertical-align: middle; }
$extraStyle
</style></head><body><p>画廊前正文</p><div class="duokan-image-gallery">
<div class="duokan-image-gallery-cell"><p class="picture">图一：<img src="image.png"/></p><p>图一题注</p></div>
<div class="duokan-image-gallery-cell"><p class="picture">图二：<img src="image.png"/></p><p>图二题注</p></div>
</div></body></html>''';
