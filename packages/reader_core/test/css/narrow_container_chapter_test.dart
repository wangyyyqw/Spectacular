import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _insets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);
const _contentWidth = 384 - 8.8 - 8.53333333333336;
const _contentHeight = 853.3333333333333 - 56.075 - 24.08888888888893;

Uint8List _book(String width, String extraCss) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package version="3.0" unique-identifier="id" '
      'xmlns="http://www.idpf.org/2007/opf"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">narrow-container</dc:identifier>'
      '<dc:title>窄容器后代断行回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="i" href="image.png" media-type="image/png"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
      'body {font-size:16px; font-family:Ahem; background:#b7b7b7;} '
      'h1 {display:none;} p {text-indent:2em; text-align:justify;} '
      '.banner {width:100%; margin:30% auto 0;} img {width:100%;} '
      '.label {$width border-width:0 2px; border-style:solid; '
      'margin:5% auto; padding:0 7px;} '
      '.label p {font-size:1.5em; text-indent:0;} '
      '$extraCss</style></head><body><h1>正文</h1>'
      '<div class="banner"><img src="image.png"/></div>'
      '<div class="label"><p>正文</p></div>'
      '<p>后续正文仍使用正常行宽。</p></body></html>',
  'image.png': base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
    'AAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
  ),
});

Future<EpubChapterSource> _open(String width, {String extraCss = ''}) async {
  final source = await const EpubFormatOpener().openBytes(
    _book(width, extraCss),
    options: const ReaderOpenOptions(
      contentWidth: _contentWidth,
      contentHeight: _contentHeight,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 18, lineHeight: 1.6, paragraphSpacing: 10),
  );
  await source.applyContentSize(
    width: _contentWidth,
    height: _contentHeight,
    topInset: _insets.top,
    sideInsets: (left: _insets.left, right: _insets.right),
  );
  return source;
}

PageBlock _title(PageContent page) =>
    page.slices.singleWhere((slice) => slice.block.layout.text == '正文').block;

void _expectNarrowTitle(PageContent page, double width) {
  final block = _title(page);
  final container = block.containers.last.container;
  expect(container.contentWidth, closeTo(width, .001));
  expect(
    container.left + container.width / 2,
    closeTo(_contentWidth / 2, .001),
  );
  expect(block.layout.maxWidth, closeTo(width, .001), reason: '后代按作者包含块宽断行');
  final lines = TextHitTester.lineBoxes(page)
      .where((line) => identical(line.slice.block, block))
      .toList();
  expect(lines.map((line) => line.text), ['正', '文']);
  for (final line in lines) {
    expect(line.rect.left, greaterThanOrEqualTo(container.left + 2));
    expect(
      line.rect.right,
      lessThanOrEqualTo(container.left + container.width - 2),
    );
  }
  expect(block.startCfi, isNotNull, reason: '自动断行保留原文锚点');
  final prose = page.slices.last.block;
  expect(prose.layout.text, '后续正文仍使用正常行宽。');
  expect(prose.layout.maxWidth, closeTo(_contentWidth, .001));
  expect(prose.layout.lineCount, 1);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (declaration, width) in [
    ('width:1.5em;', 24.0),
    ('width:24px;', 24.0),
    ('width:10%;', _contentWidth * .1),
  ]) {
    test('真机18字号下窄容器后代每行一字，保留边框与相邻正文：$declaration', () async {
      final source = await _open(declaration);
      _expectNarrowTitle((await source.loadChapter(0)).single, width);
    });
  }

  test('窄容器内显式 nowrap 仍保留一行，不强制拆开文字', () async {
    final source = await _open(
      'width:1.5em;',
      extraCss: '.label p {white-space:nowrap;}',
    );
    final title = _title((await source.loadChapter(0)).single);
    expect(title.layout.maxWidth, closeTo(24, .001));
    expect(title.layout.lines, hasLength(1));
    expect(title.layout.text, '正文');
  });
}
