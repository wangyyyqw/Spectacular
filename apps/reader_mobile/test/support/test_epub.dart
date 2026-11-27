import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';

/// 测试用最小 EPUB 构造（应用层测试共享）。
///
/// [cover] 为 true 时附带一张 JPEG 封面并在 OPF 里按
/// `<meta name="cover">` 声明（§37.3 第 2 级）。
Uint8List buildTestEpub({
  String title = '测试书',
  String author = '测试作者',
  String description = '',
  bool cover = false,
  String? identifier,
  List<String>? paragraphs,
}) {
  final body =
      (paragraphs ?? const <String>['这是用于应用壳测试的段落，内容足够长以便分页。', '第二章稍后展开。'])
          .map((text) => '<p>$text</p>')
          .join();
  final chapter =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>$title</title>'
      '</head><body><h1>第一章 简单正文</h1>$body</body></html>';
  final opf =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="bid"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="bid">'
      '${identifier ?? 'urn:uuid:test-${title.hashCode}'}</dc:identifier>'
      '<dc:title>$title</dc:title>'
      '<dc:creator>$author</dc:creator>'
      '<dc:language>zh</dc:language>'
      '<dc:description>${const HtmlEscape().convert(description)}</dc:description>'
      '<meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>'
      '${cover ? '<meta name="cover" content="cover-img"/>' : ''}'
      '</metadata><manifest>'
      '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
      '${cover ? '<item id="cover-img" href="cover.jpg" '
                'media-type="image/jpeg"/>' : ''}'
      '</manifest><spine><itemref idref="c1"/></spine></package>';
  final container =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>';
  final files = <String, String>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': container,
    'OEBPS/content.opf': opf,
    'OEBPS/c1.xhtml': chapter,
  };
  final archive = Archive();
  files.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  if (cover) {
    final bytes = Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
    archive.addFile(ArchiveFile('OEBPS/cover.jpg', bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

/// 多章测试书（P4-32/搜索类测试用）：每章一个 xhtml。
Uint8List buildMultiChapterEpub({
  required List<String> chapters,
  String title = '多章测试书',
  String? identifier,
  bool rawBody = false,
  List<String>? chapterTitles,
}) {
  assert(
    chapterTitles == null || chapterTitles.length == chapters.length,
    'chapterTitles 必须与 chapters 等长',
  );
  final buffer = StringBuffer();
  final manifest = StringBuffer();
  final spine = StringBuffer();
  for (var i = 0; i < chapters.length; i++) {
    final id = 'c${i + 1}';
    manifest.write(
      '<item id="$id" href="$id.xhtml" media-type="application/xhtml+xml"/>',
    );
    spine.write('<itemref idref="$id"/>');
    buffer.write(
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>$title</title>'
      '</head><body><h1>第 ${i + 1} 章</h1>'
      '${rawBody ? chapters[i] : '<p>${chapters[i]}</p>'}</body></html>',
    );
    buffer.write('\u0000');
  }
  if (chapterTitles != null) {
    manifest.write(
      '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
      'properties="nav"/>',
    );
  }
  final opf =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="bid"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="bid">'
      '${identifier ?? 'urn:uuid:multi-${title.hashCode}'}</dc:identifier>'
      '<dc:title>$title</dc:title><dc:language>zh</dc:language>'
      '<meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>'
      '</metadata><manifest>$manifest</manifest><spine>$spine</spine>'
      '</package>';
  final container =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>';
  final files = <String, String>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': container,
    'OEBPS/content.opf': opf,
  };
  final parts = buffer.toString().split('\u0000');
  for (var i = 0; i < chapters.length; i++) {
    files['OEBPS/c${i + 1}.xhtml'] = parts[i];
  }
  if (chapterTitles != null) {
    final items = StringBuffer();
    for (var i = 0; i < chapterTitles.length; i++) {
      items.write('<li><a href="c${i + 1}.xhtml">${chapterTitles[i]}</a></li>');
    }
    files['OEBPS/nav.xhtml'] =
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>目录</title>'
        '</head><body><nav epub:type="toc"><ol>$items</ol></nav></body></html>';
  }
  final archive = Archive();
  files.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

/// 构造带导入告警的 EPUB：manifest 项缺 media-type（按扩展名推断），
/// 触发 `E_MANIFEST_MEDIA_TYPE_INFERRED`。
Uint8List buildWarningEpub({
  String title = '告警书',
  String identifier = 'urn:uuid:warning-book',
}) {
  final chapter =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>$title</title>'
      '</head><body><p>正文</p></body></html>';
  final opf =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="uid"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="uid">$identifier</dc:identifier>'
      '<dc:title>$title</dc:title><dc:language>zh</dc:language></metadata>'
      '<manifest><item id="c1" href="c1.xhtml"/></manifest>'
      '<spine><itemref idref="c1"/></spine></package>';
  final container =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>';
  final files = <String, String>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': container,
    'OEBPS/content.opf': opf,
    'OEBPS/c1.xhtml': chapter,
  };
  final archive = Archive();
  files.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

/// 打开测试书并应用正文区尺寸（阅读会话测试用）。
Future<EpubChapterSource> openTestChapterSource(
  Uint8List bytes, {
  double width = 320,
  double height = 560,
}) async {
  final source = await EpubChapterSource.open(bytes);
  await source.applyContentSize(width: width, height: height);
  return source;
}
