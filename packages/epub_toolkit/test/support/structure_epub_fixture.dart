import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';

final structurePngBytes = Uint8List.fromList(
  image.encodePng(image.Image(width: 2, height: 2)),
);

class StructureEpubFixture {
  StructureEpubFixture({
    required this.opfPath,
    this.version = '3.0',
    this.title = '结构回归',
    this.identifier = 'urn:structure:book',
    this.navigationDirectory = '',
  }) {
    archive.addFile(
      ArchiveFile.noCompress(
        'mimetype',
        20,
        utf8.encode('application/epub+zip'),
      ),
    );
    archive.addFile(
      ArchiveFile.string(
        'META-INF/container.xml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="$opfPath" media-type="application/oebps-package+xml"/></rootfiles>
</container>''',
      ),
    );
    archive.addFile(ArchiveFile.string(opfPath, _package()));
    setText(ncxHref, _ncx());
    if (version == '3.0') setText(navHref, _nav());
    setText(chapterHrefs[0], _chapter(0));
    setText(chapterHrefs[1], _chapter(1));
    setText(
      'Styles/main.css',
      'p { text-indent: 2em; } .mark { background-image: url("../Images/cover.png"); }',
    );
    archive.addFile(
      ArchiveFile.bytes(pathFor('Images/cover.png'), structurePngBytes),
    );
  }

  final String opfPath;
  final String version;
  final String title;
  final String identifier;
  final String navigationDirectory;
  final Archive archive = Archive();

  static const chapterHrefs = ['Text/第一章.xhtml', 'Text/第二章.xhtml'];

  String get navHref => path.posix.join(navigationDirectory, 'nav.xhtml');
  String get ncxHref => path.posix.join(navigationDirectory, 'toc.ncx');
  String get opfDirectory => path.posix.dirname(opfPath);

  String pathFor(String href) =>
      path.posix.normalize(path.posix.join(opfDirectory, href));

  void setText(String href, String content) {
    archive.addFile(ArchiveFile.string(pathFor(href), content));
  }

  String text(String href) => structureText(archive, pathFor(href));

  Future<void> write(String outputPath) async {
    await File(outputPath).writeAsBytes(ZipEncoder().encodeBytes(archive));
  }

  String _package() {
    final navItem = version == '3.0'
        ? '<item id="nav" href="$navHref" media-type="application/xhtml+xml" properties="nav"/>'
        : '';
    final modified = version == '3.0'
        ? '<meta property="dcterms:modified">2026-11-19T00:00:00Z</meta>'
        : '<meta name="cover" content="cover"/>';
    final coverProperty = version == '3.0' ? ' properties="cover-image"' : '';
    return '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="$version" unique-identifier="book-id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="book-id">$identifier</dc:identifier><dc:title>$title</dc:title>
<dc:creator>结构作者</dc:creator><dc:language>zh-CN</dc:language>$modified
</metadata><manifest>
$navItem
<item id="ncx" href="$ncxHref" media-type="application/x-dtbncx+xml"/>
<item id="chapter1" href="${Uri.encodeFull(chapterHrefs[0])}" media-type="application/xhtml+xml"/>
<item id="chapter2" href="${Uri.encodeFull(chapterHrefs[1])}" media-type="application/xhtml+xml"/>
<item id="style" href="Styles/main.css" media-type="text/css"/>
<item id="cover" href="Images/cover.png" media-type="image/png"$coverProperty/>
</manifest><spine toc="ncx"><itemref idref="chapter1"/><itemref idref="chapter2"/></spine>
<guide><reference type="text" title="正文" href="${Uri.encodeFull(chapterHrefs[0])}#top"/></guide>
</package>''';
  }

  String _chapter(int index) {
    final heading = index == 0
        ? '<h1 id="top">第一章</h1><p>甲书正文</p><h2 id="part">分节</h2><p>分节正文</p>'
        : '<h1>第二章</h1><p id="epub-toolkit-heading-1">乙书正文</p>';
    return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>第${index + 1}章</title><link rel="stylesheet" href="../Styles/main.css"/></head>
<body>$heading<p class="mark"><img src="../Images/cover.png" alt="封面"/></p></body></html>''';
  }

  String _navigationHref(String href) {
    return Uri.encodeFull(
      path.posix.relative(
        pathFor(href),
        from: path.posix.dirname(pathFor(navHref)),
      ),
    );
  }

  String _nav() {
    final first = _navigationHref(chapterHrefs[0]);
    final second = _navigationHref(chapterHrefs[1]);
    return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目录</title></head><body>
<nav epub:type="toc"><ol><li><a href="$first#top">第一章</a>
<ol><li><a href="$first#part">分节</a></li></ol></li>
<li><a href="$second">第二章</a></li></ol></nav>
<nav epub:type="landmarks"><ol><li><a epub:type="bodymatter" href="$first#top">正文</a></li></ol></nav>
<nav epub:type="page-list"><ol><li><a href="$first#top">1</a></li></ol></nav>
</body></html>''';
  }

  String _ncx() {
    final first = _navigationHref(chapterHrefs[0]);
    final second = _navigationHref(chapterHrefs[1]);
    return '''<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
<head><meta name="dtb:uid" content="$identifier"/><meta name="dtb:depth" content="2"/></head>
<docTitle><text>$title</text></docTitle><navMap>
<navPoint id="n1" playOrder="1"><navLabel><text>第一章</text></navLabel><content src="$first#top"/>
<navPoint id="n2" playOrder="2"><navLabel><text>分节</text></navLabel><content src="$first#part"/></navPoint></navPoint>
<navPoint id="n3" playOrder="3"><navLabel><text>第二章</text></navLabel><content src="$second"/></navPoint>
</navMap><pageList><pageTarget id="page1" value="1" type="normal" playOrder="4">
<navLabel><text>1</text></navLabel><content src="$first#top"/></pageTarget></pageList></ncx>''';
  }
}

String structureText(Archive archive, String name) {
  return utf8.decode(archive.findFile(name)!.content);
}

XmlDocument structurePackage(Archive archive) {
  final container = XmlDocument.parse(
    structureText(archive, 'META-INF/container.xml'),
  );
  final opfPath = container
      .findAllElements('rootfile', namespaceUri: '*')
      .first
      .getAttribute('full-path')!;
  return XmlDocument.parse(structureText(archive, opfPath));
}

Future<Archive> reopenStructureEpub(String filePath) async {
  final bytes = await File(filePath).readAsBytes();
  final header = ByteData.sublistView(bytes);
  expect(header.getUint32(0, Endian.little), 0x04034b50);
  expect(header.getUint16(8, Endian.little), 0, reason: '首项必须未压缩');
  expect(header.getUint16(28, Endian.little), 0, reason: '首项不能带 extra field');
  final archive = ZipDecoder().decodeBytes(bytes, verify: true);
  expect(archive.files.first.name, 'mimetype');
  expect(structureText(archive, 'mimetype'), 'application/epub+zip');
  final container = XmlDocument.parse(
    structureText(archive, 'META-INF/container.xml'),
  );
  final opfPath = container
      .findAllElements('rootfile', namespaceUri: '*')
      .first
      .getAttribute('full-path')!;
  final package = structurePackage(archive);
  expect(package.rootElement.getAttribute('version'), anyOf('2.0', '3.0'));
  final items = package.findAllElements('item', namespaceUri: '*').toList();
  final ids = items.map((item) => item.getAttribute('id')).toList();
  expect(ids.toSet(), hasLength(items.length), reason: 'manifest ID 必须唯一');
  for (final item in items) {
    final href = item.getAttribute('href')!;
    expect(
      () => Uri.decodeFull(href),
      returnsNormally,
      reason: 'manifest href: $href',
    );
    final resource = path.posix.normalize(
      path.posix.join(path.posix.dirname(opfPath), Uri.decodeFull(href)),
    );
    expect(archive.findFile(resource), isNotNull, reason: resource);
  }
  final spine = package.findAllElements('itemref', namespaceUri: '*').toList();
  expect(spine, isNotEmpty);
  for (final itemref in spine) {
    expect(ids, contains(itemref.getAttribute('idref')));
  }
  for (final file in archive.files) {
    final extension = path.posix.extension(file.name).toLowerCase();
    if (const ['.xhtml', '.html', '.ncx', '.opf'].contains(extension)) {
      XmlDocument.parse(structureText(archive, file.name));
    }
  }
  return archive;
}
