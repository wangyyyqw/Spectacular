import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// 连续版本测试使用稳定的语义路径和章名，插章不改写已有章身份。
class RevisionTestChapter {
  const RevisionTestChapter(this.path, this.title, this.paragraphs);

  final String path;
  final String title;
  final List<String> paragraphs;
}

const revisionTitle = '覆盖更新独立测试书';
const revisionAuthor = '版本测试作者';
const revisionIdentifier = 'urn:uuid:revision-update-test';
const revisionBefore = '甲乙丙丁戊己庚辛壬癸这是保持不变的前文用于验证旧引用的位置。';
const revisionQuote = '原版笔记应该跟着这段独有文字走。';
const revisionAfter = '子丑寅卯辰巳午未申酉这是保持不变的后文用于验证旧引用的终点。';
const revisionBookmarkQuote = '书签指向原书第二章的这一段，插入前言与中间章以后还应保留。';
const _middle = RevisionTestChapter('middle.xhtml', '旅程', [
  revisionBookmarkQuote,
  '这一章另有不重复的独有段落用于章节关联。',
]);
const _last = RevisionTestChapter('last.xhtml', '归来', ['原来全书的最后一章结束于这里。']);

const revisionOriginalChapters = [
  RevisionTestChapter('first.xhtml', '相遇', [
    revisionBefore,
    revisionQuote,
    revisionAfter,
  ]),
  _middle,
  _last,
];

const revisionUpdatedChapters = [
  RevisionTestChapter('preface.xhtml', '前言序', ['新版新增的前言序不能把原来书签挤到这里。']),
  RevisionTestChapter('first.xhtml', '相遇', [
    '新版在引用前增添了开场段落。',
    revisionBefore,
    revisionQuote,
    revisionAfter,
  ]),
  RevisionTestChapter('insert-one.xhtml', '插入章甲', ['新增中间章节甲的可读正文。']),
  RevisionTestChapter('insert-two.xhtml', '插入章乙', ['新增中间章节乙的可读正文。']),
  _middle,
  _last,
  RevisionTestChapter('postscript.xhtml', '后记', ['新版追加后记的可读正文。']),
];

Uint8List buildRevisionTestEpub({
  List<RevisionTestChapter> chapters = revisionOriginalChapters,
  String title = revisionTitle,
  String author = revisionAuthor,
  String identifier = revisionIdentifier,
}) {
  final files = <String, String>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml':
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
    'OEBPS/content.opf': _opf(chapters, title, author, identifier),
    'OEBPS/nav.xhtml': _navigation(chapters),
    for (final chapter in chapters) 'OEBPS/${chapter.path}': _chapter(chapter),
  };
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

String _escape(String text) => const HtmlEscape().convert(text);

String _opf(
  List<RevisionTestChapter> chapters,
  String title,
  String author,
  String identifier,
) {
  final manifest = StringBuffer();
  final spine = StringBuffer();
  for (var i = 0; i < chapters.length; i++) {
    manifest.write(
      '<item id="c$i" href="${_escape(chapters[i].path)}" media-type="application/xhtml+xml"/>',
    );
    spine.write('<itemref idref="c$i"/>');
  }
  return '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bid">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="bid">${_escape(identifier)}</dc:identifier>'
      '<dc:title>${_escape(title)}</dc:title><dc:creator>${_escape(author)}</dc:creator>'
      '<dc:language>zh</dc:language><meta property="dcterms:modified">2026-11-05T00:00:00Z</meta>'
      '</metadata><manifest>$manifest'
      '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
      '</manifest><spine>$spine</spine></package>';
}

String _chapter(RevisionTestChapter chapter) =>
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>${_escape(chapter.title)}</title></head>'
    '<body><h1>${_escape(chapter.title)}</h1>'
    '${chapter.paragraphs.map((text) => '<p>${_escape(text)}</p>').join()}'
    '</body></html>';

String _navigation(List<RevisionTestChapter> chapters) =>
    '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
    '<head><title>目录</title></head><body><nav epub:type="toc"><ol>'
    '${chapters.map((chapter) => '<li><a href="${_escape(chapter.path)}">${_escape(chapter.title)}</a></li>').join()}'
    '</ol></nav></body></html>';
