import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _chapter = 'OEBPS/Text/story.xhtml';
const _notes = 'OEBPS/Text/notes.xhtml';
const _pageSize = Size(384, 853.3333333333334);
const _insets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);
const _firstText = '第一条注文的第一段。';
const _continuation = '同一条注文的第二段。';

String _reference(int number, {String href = 'story.xhtml#chapter-top'}) =>
    '<span class="super"><a id="noteBack_$number" href="$href">'
    '<span>[$number]</span></a></span>';

String _definition(int number) =>
    '<p><a id="note_$number" href="notes.xhtml#notes-top">'
    '<span>[$number]</span></a><span>'
    '${number == 1 ? _firstText : '第$number条独立注文。'}</span></p>';

String _document(String body) =>
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
    'body {margin:0; font-family:Ahem;} p {margin:1em 0; text-indent:2em;}'
    '.super {vertical-align:super;} .super a {color:#0000ff;}'
    '.zy {color:#0000ff; font-size:0.6em; vertical-align:super;}'
    '.zs {font-size:0.8em;}'
    'img {width:100%; height:216px;} h1 {font-size:1.5em;}'
    '</style></head><body>$body</body></html>';

Uint8List _book({
  String? body,
  String? definitions,
  bool intermediate = false,
}) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="OEBPS/book.opf"/>'
      '</rootfiles></container>',
  'OEBPS/book.opf':
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="id"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">numbered-footnotes</dc:identifier>'
      '<dc:title>断链编号注释回归</dc:title></metadata><manifest>'
      '<item id="c" href="Text/story.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="n" href="Text/notes.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="other" href="Text/other.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="image" href="Text/note.svg" media-type="image/svg+xml"/>'
      '</manifest><spine><itemref idref="c"/>'
      '${intermediate ? '<itemref idref="other"/>' : ''}'
      '<itemref idref="n"/></spine></package>',
  _chapter: _document(
    '<div id="chapter-top"><img src="note.svg"/></div>'
    '${body ?? '<p>正文${_reference(1)}接续正文。</p>'
            '<p>下一段${_reference(2)}接续正文。</p>'}',
  ),
  _notes: _document(
    '<div><h1 id="notes-top">注释</h1>'
    '${definitions ?? '${_definition(1)}<p>$_continuation</p>'
            '<div><img src="note.svg"/></div>${_definition(2)}'}</div>',
  ),
  'OEBPS/Text/other.xhtml': _document('<p>普通的后续章节。</p>'),
  'OEBPS/Text/note.svg':
      '<svg xmlns="http://www.w3.org/2000/svg" width="2" height="2">'
      '<rect width="2" height="2" fill="red"/></svg>',
});

Future<EpubChapterSource> _open(Uint8List bytes) async {
  final source = await const EpubFormatOpener().openBytes(
    bytes,
    options: ReaderOpenOptions(
      contentWidth: _pageSize.width - _insets.horizontal,
      contentHeight: _pageSize.height - _insets.vertical,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 18, lineHeight: 1.6, paragraphSpacing: 10),
  );
  await source.applyContentSize(
    width: _pageSize.width - _insets.horizontal,
    height: _pageSize.height - _insets.vertical,
    topInset: _insets.top,
    sideInsets: (left: _insets.left, right: _insets.right),
  );
  return source;
}

Future<Offset> _paintedReference(PageContent page) async {
  final recorder = ui.PictureRecorder();
  PagePainter().paint(
    Canvas(recorder),
    page,
    pageSize: _pageSize,
    pageInsets: _insets,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(384, 854);
  try {
    final pixels = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    var bounds = Rect.zero;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final offset = (y * image.width + x) * 4;
        if (pixels.getUint8(offset) >= 100 ||
            pixels.getUint8(offset + 1) >= 100 ||
            pixels.getUint8(offset + 2) <= 150) {
          continue;
        }
        final pixel = Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1);
        bounds = bounds.isEmpty ? pixel : bounds.expandToInclude(pixel);
      }
      if (!bounds.isEmpty && y > bounds.bottom + 2) break;
    }
    expect(bounds.isEmpty, isFalse, reason: '上标注号必须实际绘制');
    return bounds.center - Offset(_insets.left, _insets.top);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('章首断链由相邻同号定义序列恢复，正文上标可点击且保留多段注文与图片', () async {
    final source = await _open(_book());
    final original = source.document.archive.readString(_chapter);
    expect(
      FootnoteParser.targetPaths(
        source.document.parseFootnotes(0),
        source.document.archive.names,
        followingPath: _notes,
      ),
      {_chapter, _notes},
      reason: '仅补读紧随的候选章，不扫描其他正文',
    );
    final page = (await source.loadChapter(0)).first;
    final notes = page.slices.expand((slice) => slice.block.footnotes).toList();
    expect(notes.map((note) => note.label), ['[1]', '[2]']);
    expect(notes.first.text, '$_firstText\n$_continuation');
    expect(notes.first.imageUrls, ['OEBPS/Text/note.svg']);
    expect(notes.last.text, '第2条独立注文。');
    expect(
      TextHitTester.footnoteAt(page, await _paintedReference(page)),
      same(notes.first),
    );
    final anchors = source.document.resolveFootnotes(0);
    expect(anchors.every((anchor) => anchor.kind == NoteKind.footnote), isTrue);
    expect(anchors.every((anchor) => anchor.targetSpine == 1), isTrue);
    expect(anchors.map((anchor) => anchor.targetId), ['note_1', 'note_2']);
    expect(anchors.map((anchor) => anchor.strategy.name).toSet(), {
      'numberedSequence',
    });
    expect(source.document.archive.readString(_chapter), original);
    final definitionPages = await source.loadChapter(1);
    expect(
      definitionPages
          .expand((page) => page.slices)
          .expand((slice) => slice.block.footnotes),
      isEmpty,
    );
    expect(
      definitionPages
          .expand((page) => page.slices)
          .map((slice) => slice.block.layout.text)
          .join(),
      contains(_continuation),
    );
  });

  for (final (name, definitions) in [
    ('只有一条同号定义', _definition(1)),
    ('定义编号与文字不同', _definition(1).replaceFirst('[1]', '[9]') + _definition(2)),
    (
      '定义锚点不在段首',
      '<p>普通正文<a id="note_1" '
          'href="notes.xhtml#notes-top">[1]</a>继续正文。</p>${_definition(2)}',
    ),
    ('定义 ID 重复', _definition(1) + _definition(1) + _definition(2)),
  ]) {
    test('$name不恢复断链', () async {
      final source = await _open(_book(definitions: definitions));
      final pages = await source.loadChapter(0);
      expect(
        pages
            .expand((page) => page.slices)
            .expand((slice) => slice.block.footnotes),
        isEmpty,
      );
    });
  }

  for (final (name, body) in [
    (
      '普通数字链接',
      '<p>正文<a href="#chapter-top">[1]</a>继续</p>'
          '<p>正文<a href="#chapter-top">[2]</a>继续</p>',
    ),
    ('只有一个断链注号', '<p>正文${_reference(1)}继续</p>'),
    (
      '不同的链接目标',
      '<p>正文${_reference(1)}继续</p>'
          '<p>正文${_reference(2, href: '#other-top')}继续</p><div id="other-top"/>',
    ),
  ]) {
    test('$name不生成注释', () async {
      final source = await _open(_book(body: body));
      final pages = await source.loadChapter(0);
      expect(
        pages
            .expand((page) => page.slices)
            .expand((slice) => slice.block.footnotes),
        isEmpty,
      );
    });
  }

  test('已有有效定义的链接优先，其他断链仍按编号恢复', () async {
    final source = await _open(
      _book(
        body:
            '<p>正文${_reference(1, href: '#local-note')}继续</p>'
            '<p>正文${_reference(2)}继续${_reference(3)}</p>'
            '<aside id="local-note" role="doc-footnote">有效本地注文。</aside>',
        definitions: _definition(1) + _definition(2) + _definition(3),
      ),
    );
    final pages = await source.loadChapter(0);
    final notes = pages
        .expand((page) => page.slices)
        .expand((slice) => slice.block.footnotes)
        .toList();
    expect(notes.map((note) => note.text), ['有效本地注文。', '第2条独立注文。', '第3条独立注文。']);
  });

  test('有效双向链接优先于相邻章的同号定义', () async {
    final source = await _open(
      _book(
        body:
            '<p>正文${_reference(1, href: '#paired')}继续</p>'
            '<p>正文${_reference(2, href: '#paired')}继续</p>'
            '<p id="paired"><a href="#noteBack_1">[1]</a>'
            '<a href="#noteBack_2">[2]</a>有效双向回链注文。</p>',
      ),
    );
    final pages = await source.loadChapter(0);
    final notes = pages
        .expand((page) => page.slices)
        .expand((slice) => slice.block.footnotes)
        .toList();
    expect(notes, hasLength(2));
    expect(notes.every((note) => note.text!.contains('有效双向回链注文。')), isTrue);
  });

  test('中文方括号注号与同章双向回链可点击，注文取同段正文', () async {
    final source = await _open(
      _book(
        body:
            '<p class="a">正文<a class="zy" href="#id1a" id="id1">〔1〕</a>继续正文。</p>'
            '<p class="zs"><a class="hl" href="#id1" id="id1a">〔1〕</a>注释正文第一段。</p>',
        definitions: '<p>无关页。</p>',
      ),
    );
    final page = (await source.loadChapter(0)).first;
    final notes = page.slices.expand((slice) => slice.block.footnotes).toList();
    expect(notes.map((note) => note.label), ['〔1〕']);
    expect(notes.single.text, '注释正文第一段。');
    expect(
      TextHitTester.footnoteAt(page, await _paintedReference(page)),
      same(notes.single),
    );
  });

  test('标题星号注号与同章回链可点击，注文取同段正文', () async {
    final source = await _open(
      _book(
        body:
            '<h3>正文标题<a class="zy" href="#id0a" id="id0">*</a></h3>'
            '<p class="a">正文第一段。</p>'
            '<p class="zs"><a class="hl" style="color:#000000" '
            'href="#id0" id="id0a"> * </a>标题注释正文。</p>',
        definitions: '<p>无关页。</p>',
      ),
    );
    final page = (await source.loadChapter(0)).first;
    final notes = page.slices.expand((slice) => slice.block.footnotes).toList();
    expect(notes.map((note) => note.label), ['*']);
    expect(notes.single.text, '标题注释正文。');
    expect(
      TextHitTester.footnoteAt(page, await _paintedReference(page)),
      same(notes.single),
    );
  });

  test('不越过紧随章节去扫描同号定义', () async {
    final source = await _open(_book(intermediate: true));
    final pages = await source.loadChapter(0);
    expect(
      pages
          .expand((page) => page.slices)
          .expand((slice) => slice.block.footnotes),
      isEmpty,
    );
  });
}
