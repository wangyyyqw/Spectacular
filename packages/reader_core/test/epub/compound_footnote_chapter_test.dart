import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _chapter = 'OEBPS/Text/pub-story.xhtml';
const _notes = 'OEBPS/Text/pub-notes.xhtml';
const _width = 366.6666666666667;
const _height = 773.1694444444443;

String _reference(int number, {String tag = 'sup'}) => [
  for (final character in '[$number]'.split(''))
    '<$tag><a id="pub-story.xhtml_note_$number" '
        'href="#notes.xhtml_note_$number">$character</a></$tag>',
].join();

String _definition(int number, {String? target, bool backlink = true}) =>
    '<p><span id="pub-notes.xhtml_noteBack_$number">'
    '${backlink ? [for (final character in '[$number]'.split('')) '<a id="pub-notes.xhtml_noteBack_$number" '
                'href="#${target ?? 'story.xhtml_noteBack_$number'}">$character</a>'].join() : '[$number]'}第$number条完整注文。</span></p>';

String _document(String body) =>
    '<html><head><style>'
    'body {margin:0; font-family:Ahem;} p {margin:20px 0;} '
    'a {color:blue;} .header {text-align:center; font-size:19px;}'
    '</style></head><body>$body</body></html>';

Uint8List _book({
  String? definitions,
  String extraSource = '',
  bool ambiguous = false,
}) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': '<container><rootfiles><rootfile full-path="OEBPS/book.opf"/></rootfiles></container>',
  'OEBPS/book.opf':
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">compound-footnote</dc:identifier>'
      '<dc:title>复合注释锚点回归</dc:title></metadata><manifest>'
      '<item id="c" href="Text/pub-story.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="n" href="Text/pub-notes.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest><spine><itemref idref="c"/><itemref idref="n"/></spine></package>',
  _chapter: _document(
    '<h2>第一部</h2><p class="header">${_reference(1, tag: 'b')}${_reference(2, tag: 'b')}</p>'
    '<p>正文${_reference(4)}接续文字${_reference(10)}。</p>$extraSource',
  ),
  _notes: _document(
    definitions ??
        [
          for (final n in [1, 2, 4, 10]) _definition(n),
        ].join(),
  ),
  if (ambiguous) 'OEBPS/Other/pub-notes.xhtml': _document(_definition(4)),
});

Future<EpubChapterSource> _open(Uint8List bytes) async {
  final source = await const EpubFormatOpener().openBytes(
    bytes,
    options: const ReaderOpenOptions(
      contentWidth: _width,
      contentHeight: _height,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 18, lineHeight: 1.6, paragraphSpacing: 10),
  );
  await source.applyContentSize(
    width: _width,
    height: _height,
    topInset: 56.075,
    sideInsets: (left: 8.8, right: 8.53333333333336),
  );
  return source;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('文件名写入片段、note/noteBack错配与拆分注号经正式入口恢复，原书字节不变', () async {
    final source = await _open(_book());
    final original = source.document.archive.readString(_chapter)!;
    expect(
      FootnoteParser.targetPaths(source.document.parseFootnotes(0), [
        _chapter,
        _notes,
        'OEBPS/Text/unrelated.xhtml',
      ]),
      {_chapter, _notes},
      reason: '只加载带文件名证据的候选，不扫描整书正文',
    );
    final page = (await source.loadChapter(0)).first;
    final notes = page.slices.expand((slice) => slice.block.footnotes).toList();
    expect(notes.map((note) => note.label).toSet(), {
      '[1]',
      '[2]',
      '[4]',
      '[10]',
    });
    for (final line in TextHitTester.lineBoxes(page)) {
      for (final n in [1, 2, 4, 10]) {
        final start = line.text.indexOf('[$n]');
        if (start < 0) continue;
        for (var offset = start; offset < start + '[$n]'.length; offset++) {
          final rect = TextHitTester.selectionRects(
            line,
            offset,
            offset + 1,
          ).single.shift(line.rect.topLeft);
          final hit = TextHitTester.footnoteAt(page, rect.center);
          expect(hit?.label, '[$n]', reason: '注号的每个字符都能点击');
          expect(hit?.text, '第$n条完整注文。');
        }
      }
    }
    final resolved = source.document.resolveFootnotes(0);
    expect(
      resolved.every((a) => a.strategy == AnchorStrategy.backlink),
      isTrue,
    );
    expect(resolved.every((a) => a.targetSpine == 1), isTrue);
    expect(
      (await source.loadAnchorChapter(0)).text,
      contains('正文[4]接续文字[10]。'),
    );
    expect(source.document.archive.readString(_chapter), original);
    final notePage = (await source.loadChapter(1)).first;
    expect(
      notePage.slices.expand((s) => s.block.footnotes),
      isEmpty,
      reason: '返回链接不反向弹出正文',
    );
    expect(
      notePage.slices.map((s) => s.block.layout.text).join(),
      contains('第4条完整注文。'),
    );
  });

  for (final (name, definitions) in [
    ('缺少回链', _definition(4, backlink: false)),
    ('回链指向别章', _definition(4, target: 'other.xhtml_noteBack_4')),
    ('回链注号不同', _definition(4, target: 'story.xhtml_noteBack_3')),
    (
      '正文中间的同号链接',
      '<p>普通正文<span id="pub-notes.xhtml_noteBack_4">'
          '<a href="#story.xhtml_noteBack_4">[4]</a>继续正文</span></p>',
    ),
  ]) {
    test('$name不猜测匹配', () async {
      final source = await _open(_book(definitions: definitions));
      final page = (await source.loadChapter(0)).first;
      expect(page.slices.expand((s) => s.block.footnotes), isEmpty);
    });
  }

  test('两个候选都满足双向证据时保持未解析', () async {
    final source = await _open(_book(ambiguous: true));
    final page = (await source.loadChapter(0)).first;
    expect(
      page.slices
          .expand((s) => s.block.footnotes)
          .where((n) => n.label == '[4]'),
      isEmpty,
    );
  });

  test('同一文档重复定义相同ID且都有回链时保持未解析', () async {
    final source = await _open(
      _book(definitions: _definition(4) + _definition(4)),
    );
    final page = (await source.loadChapter(0)).first;
    expect(page.slices.expand((s) => s.block.footnotes), isEmpty);
  });

  test('有效本地锚点优先于同名片段兼容', () async {
    final source = await _open(
      _book(
        extraSource: '<aside id="notes.xhtml_note_4" role="doc-footnote">合法本地注文。</aside>',
      ),
    );
    final page = (await source.loadChapter(0)).first;
    final notes = page.slices
        .expand((s) => s.block.footnotes)
        .where((n) => n.label == '[4]');
    expect(notes, isNotEmpty);
    expect(notes.every((n) => n.text == '合法本地注文。'), isTrue);
  });
}
