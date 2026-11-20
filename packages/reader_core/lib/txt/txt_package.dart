import 'dart:convert';

import 'package:archive/archive_io.dart';
import 'package:xml/xml.dart';

import 'txt_models.dart';

/// 按章写 ZIP，正文不保留第二份完整 XHTML 字符串。
void writeTxtEpub(
  String target,
  List<String> blocks,
  ChapterDetectionResult detection, {
  required String title,
  required String sourceDigest,
  required String encoding,
  required ChapterDetectionOptions options,
  required void Function(double) onProgress,
}) {
  final output = OutputFileStream(target);
  final encoder = ZipEncoder()..startEncode(output);
  try {
    encoder.add(
      ArchiveFile.noCompress(
        'mimetype',
        20,
        utf8.encode('application/epub+zip'),
      ),
    );
    void add(String path, String text) =>
        encoder.add(ArchiveFile.bytes(path, utf8.encode(text)));
    add('META-INF/container.xml', _container);
    add('OEBPS/styles.css', _styles);
    add(
      txtMetadataPath,
      jsonEncode({
        'schema': 1,
        'converterVersion': 1,
        'sourceDigest': sourceDigest,
        'encoding': encoding,
        'options': options.toJson(),
      }),
    );
    final chapters = detection.boundaries;
    for (var i = 0; i < chapters.length; i++) {
      final end = i + 1 < chapters.length
          ? chapters[i + 1].blockIndex
          : blocks.length;
      add(
        'OEBPS/Text/chapter-${i + 1}.xhtml',
        _chapter(blocks, chapters[i], end),
      );
      onProgress((i + 1) / chapters.length);
    }
    final identifier = '$txtIdentifierPrefix$sourceDigest';
    add('OEBPS/content.opf', _opf(title, identifier, chapters));
    add('OEBPS/nav.xhtml', _nav(chapters));
    add('OEBPS/toc.ncx', _ncx(title, identifier, chapters));
    encoder.endEncode();
  } finally {
    output.closeSync();
  }
}

const _container =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
    '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>'
    '</rootfiles></container>';

const _styles =
    'p { text-indent: 2em; text-align: justify; }\n'
    'h1, h2 { text-align: center; }\n';

String _escape(String text) => XmlText(text).toXmlString();
String _attribute(String text) => XmlAttribute(
  XmlName.parts('v'),
  text,
).toXmlString().substring(3).replaceFirst(RegExp(r'"$'), '');

String _chapter(List<String> blocks, ChapterBoundary boundary, int end) {
  final text = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml">'
    '<head><title>${_escape(boundary.title)}</title>'
    '<link rel="stylesheet" type="text/css" href="../styles.css"/></head><body>',
  );
  for (var i = boundary.blockIndex; i < end; i++) {
    final tag = i == boundary.blockIndex && !boundary.synthetic
        ? (boundary.isVolume ? 'h1' : 'h2')
        : 'p';
    text.write('<$tag id="txt-$i">${_escape(blocks[i])}</$tag>');
  }
  text.write('</body></html>');
  return text.toString();
}

String _opf(String title, String identifier, List<ChapterBoundary> chapters) {
  final modified =
      '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';
  final text = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">'
    '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:identifier id="uid">${_escape(identifier)}</dc:identifier>'
    '<dc:title>${_escape(title)}</dc:title><dc:language>und</dc:language>'
    '<meta property="dcterms:modified">$modified</meta></metadata><manifest>'
    '<item id="style" href="styles.css" media-type="text/css"/>'
    '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
    '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
    '<item id="$txtMetadataManifestId" href="spectacular-txt.json" media-type="application/json"/>',
  );
  for (var i = 0; i < chapters.length; i++) {
    text.write(
      '<item id="chapter-${i + 1}" href="Text/chapter-${i + 1}.xhtml" media-type="application/xhtml+xml"/>',
    );
  }
  text.write('</manifest><spine toc="ncx">');
  for (var i = 0; i < chapters.length; i++) {
    text.write('<itemref idref="chapter-${i + 1}"/>');
  }
  text.write('</spine></package>');
  return text.toString();
}

String _nav(List<ChapterBoundary> chapters) {
  final text = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
    '<head><title>目录</title></head><body><nav epub:type="toc" id="toc"><ol>',
  );
  var volumeOpen = false;
  for (var i = 0; i < chapters.length; i++) {
    final chapter = chapters[i];
    if (chapter.isVolume && volumeOpen) {
      text.write('</ol></li>');
      volumeOpen = false;
    }
    text.write(
      '<li><a href="Text/chapter-${i + 1}.xhtml">${_escape(chapter.title)}</a>',
    );
    if (chapter.isVolume &&
        i + 1 < chapters.length &&
        !chapters[i + 1].isVolume) {
      text.write('<ol>');
      volumeOpen = true;
    } else {
      text.write('</li>');
    }
  }
  if (volumeOpen) text.write('</ol></li>');
  text.write('</ol></nav></body></html>');
  return text.toString();
}

String _ncx(String title, String identifier, List<ChapterBoundary> chapters) {
  final text = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
    '<head><meta name="dtb:uid" content="${_attribute(identifier)}"/>'
    '<meta name="dtb:depth" content="2"/><meta name="dtb:totalPageCount" content="0"/>'
    '<meta name="dtb:maxPageNumber" content="0"/></head>'
    '<docTitle><text>${_escape(title)}</text></docTitle><navMap>',
  );
  var volumeOpen = false;
  for (var i = 0; i < chapters.length; i++) {
    final chapter = chapters[i];
    if (chapter.isVolume && volumeOpen) {
      text.write('</navPoint>');
      volumeOpen = false;
    }
    text.write(
      '<navPoint id="nav-${i + 1}" playOrder="${i + 1}">'
      '<navLabel><text>${_escape(chapter.title)}</text></navLabel>'
      '<content src="Text/chapter-${i + 1}.xhtml"/>',
    );
    if (chapter.isVolume) {
      volumeOpen = true;
    } else {
      text.write('</navPoint>');
    }
  }
  if (volumeOpen) text.write('</navPoint>');
  text.write('</navMap></ncx>');
  return text.toString();
}
