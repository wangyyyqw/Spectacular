import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _noteText = '蝶番（takatugayi），铰链，使用于屏风或者柜门上';
const _contentWidth = 366.6666666666667;
const _contentHeight = 773.1694444444443;

const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
    'AAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==';

Uint8List _book({String imageUrl = 'note.png'}) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
  'book.opf':
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">empty-inline-note</dc:identifier>'
      '<dc:title>空行内盒注释回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="s" href="s.css" media-type="text/css"/>'
      '<item id="n" href="note.png" media-type="image/png"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
      '<link rel="stylesheet" href="s.css"/></head><body><h2>1</h2>'
      '<p>剪刀男的第三名牺牲者住在目黑区鹰番。</p>'
      '<p>但我至今还对鹰番这一街名见所未见闻所未闻，它究竟位于目黑区哪里，'
      '最近的车站是哪条线的哪一站，我完全无从猜测。</p>'
      '<p>首先，我认定这一街名的读法是 “takatugayi”。不消说，因为联想到“蝶番”'
      '<span class="reader js_readerFooterNote" data-wr-footernote="$_noteText"/>'
      '，脑海中浮现出两只鹰在青空下亲密地飞翔，宛如江户时代屏风绘的景象。</p>'
      '<p>顶着一头宛如&lt;医师&gt;般的漂亮银发。</p>'
      '</body></html>',
  's.css':
      '''
p { text-indent:2em; }
h2 { color:#444; font-size:24px; text-align:center; }
span.reader { position:relative; display:inline-block; width:19px; height:19px;
  vertical-align:sub; cursor:pointer; margin:0 3px;
  background-image:url("$imageUrl"); background-size:100%; background-repeat:no-repeat; }
''',
  'note.png': base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
    'AAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
  ),
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('正式 EPUB 入口可读取行内注号的 data 图片及包内图片', () async {
    const url = 'data:image/png;base64,$_pngBase64';
    final source = await const EpubFormatOpener().openBytes(
      _book(imageUrl: url),
      options: const ReaderOpenOptions(
        contentWidth: _contentWidth,
        contentHeight: _contentHeight,
      ),
    );
    addTearDown(source.close);
    final pages = await source.loadChapter(0);
    final payload = pages
        .expand((page) => page.slices)
        .expand((slice) => slice.block.layout.lines)
        .expand((line) => line.inlineBoxes)
        .single
        .spec
        .payload;
    final style = payload is PageBlock
        ? payload.style
        : payload as ComputedStyle;
    expect(style?.backgroundImage, url);
    expect(await source.readImageBytes(url), base64Decode(_pngBase64));
    expect(await source.readImageBytes('note.png'), base64Decode(_pngBase64));
    expect(await source.readImageBytes('data:image/png,%89PNG%0D%0A'), [
      137,
      80,
      78,
      71,
      13,
      10,
    ]);
    expect(await source.readImageBytes('data:image/png;base64,%%%'), isNull);
    expect(await source.readImageBytes('data:text/plain,hello'), isNull);
  });

  test('章节含转义尖括号时，空背景图片注号保留正文与实际点击区', () async {
    final source = await const EpubFormatOpener().openBytes(
      _book(),
      options: const ReaderOpenOptions(
        contentWidth: _contentWidth,
        contentHeight: _contentHeight,
      ),
    );
    addTearDown(source.close);
    await source.applyOverrides(
      const ReaderOverrides(
        fontSize: 21,
        lineHeight: 1.6,
        paragraphSpacing: 10,
      ),
    );
    final pages = await source.loadChapter(0);
    final page = pages.single;
    final text = page.slices.map((slice) => slice.block.layout.text).join('\n');
    expect(text, contains('宛如<医师>般'));
    final notes = page.slices.expand((slice) => slice.block.footnotes);
    expect(notes, hasLength(1));
    final note = notes.single;
    expect(note.text, _noteText);
    final box = TextHitTester.lineBoxes(page).singleWhere(
      (box) =>
          box.slice.block.layout.lines[box.lineIndex].inlineBoxes.isNotEmpty,
    );
    final line = box.slice.block.layout.lines[box.lineIndex];
    final icon = line.inlineBoxes.single;
    expect(icon.width, closeTo(19, .01));
    expect(icon.height, closeTo(19, .01));
    final center = Offset(
      box.rect.left + icon.left + icon.width / 2,
      (box.textTop ?? box.rect.top) +
          icon.topIn(line.baseline - line.top) +
          icon.height / 2,
    );
    expect(TextHitTester.footnoteAt(page, center), same(note));
  });
}
