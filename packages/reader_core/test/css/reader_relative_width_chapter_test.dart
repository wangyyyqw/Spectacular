import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _width = 384 - 8.8 - 8.53333333333336;
const _height = 853.3333333333333 - 56.075 - 24.08888888888893;
const _panelWidth = 16 * .97 * 4;

Uint8List _book(String width, String extraCss) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package version="3.0" unique-identifier="id" '
      'xmlns="http://www.idpf.org/2007/opf"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">reader-relative-width</dc:identifier>'
      '<dc:title>阅读字号与窄列宽回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
      'body {font-size:97%; font-family:Ahem; margin:0 10px;} '
      'div {margin:0; padding:0; text-align:center; line-height:130%;} '
      'p {text-indent:2em; text-align:justify; margin:0 .5%;} '
      '.page {width:100%; height:90vh; border:1px solid transparent;} '
      '.panel {width:4em; margin:.5em 1em .5em auto; '
      'border:1px dashed #000; background:#ffffff80;} '
      'h1 {font-size:.9em; width:1em; margin:1em .6em 0 auto; '
      'border-left:2px solid #888; padding:3em 0 2em 7px; line-height:100%;} '
      '.caption {font-size:1.5em; width:$width; text-align:right; '
      'text-indent:0; margin:-1em 1.5em .5em auto; line-height:100%;} '
      '$extraCss</style></head><body><div class="page"><div class="panel">'
      '<h1>第一卷</h1><p class="caption">正文</p>'
      '</div></div><p>相邻正文保持正常行宽。</p></body></html>',
});

Future<EpubChapterSource> _open({
  String width = '1em',
  String extraCss = '',
}) async {
  final source = await const EpubFormatOpener().openBytes(
    _book(width, extraCss),
    options: const ReaderOpenOptions(
      contentWidth: _width,
      contentHeight: _height,
    ),
  );
  addTearDown(source.close);
  await _setSize(source, 18);
  await source.applyContentSize(
    width: _width,
    height: _height,
    topInset: 56.075,
    sideInsets: (left: 8.8, right: 8.53333333333336),
  );
  return source;
}

Future<void> _setSize(EpubChapterSource source, double? size) =>
    source.applyOverrides(
      ReaderOverrides(fontSize: size, lineHeight: 1.6, paragraphSpacing: 10),
    );

PageBlock _caption(PageContent page) =>
    page.slices.singleWhere((slice) => slice.block.layout.text == '正文').block;

void _expectInsidePanel(PageContent page, double fontSize) {
  final block = _caption(page);
  final panel = block.containers.last.container;
  expect(panel.contentWidth, closeTo(_panelWidth, .001));
  expect(block.style!.fontSize, closeTo(fontSize, .001));
  expect(block.layout.maxWidth, closeTo(fontSize, .001));
  final lines = TextHitTester.lineBoxes(page)
      .where((line) => identical(line.slice.block, block))
      .toList();
  expect(lines.map((line) => line.text), ['正', '文']);
  for (final line in lines) {
    expect(line.rect.left, greaterThanOrEqualTo(panel.contentLeft - .001));
    expect(
      line.rect.right,
      lessThanOrEqualTo(panel.contentLeft + panel.contentWidth + .001),
    );
  }
  expect(block.style!.margin.top, closeTo(-fontSize, .001));
  expect(block.startCfi, isNotNull);
  final prose = page.slices.last.block;
  expect(prose.layout.text, '相邻正文保持正常行宽。');
  expect(prose.layout.maxWidth, greaterThan(300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('真机18字号下相对列宽与文字同步放大，右对齐单字不越过父框', () async {
    final source = await _open();
    _expectInsidePanel((await source.loadChapter(0)).single, 27);
  });

  test('切换和恢复阅读字号时重新求解em列宽，父框和独立标题盒保持原宽', () async {
    final source = await _open();
    for (final size in [21.0, 12.0, 18.0, null]) {
      await _setSize(source, size);
      final page = (await source.loadChapter(0)).single;
      _expectInsidePanel(page, (size ?? 16 * .97) * 1.5);
      final heading = page.slices.first.block;
      expect(heading.layout.text, '第一卷');
      expect(heading.layout.maxWidth, closeTo(16 * .97 * .9, .001));
    }
  });

  for (final (width, expected) in [
    ('24px', 24.0),
    ('37.5%', _panelWidth * .375),
    ('calc(1em + 5%)', 27 + _panelWidth * .05),
  ]) {
    test('相对字号列宽保留作者的单位和父宽基准：$width', () async {
      final source = await _open(width: width);
      final block = _caption((await source.loadChapter(0)).single);
      expect(block.style!.fontSize, closeTo(27, .001));
      expect(block.layout.maxWidth, closeTo(expected, .001));
    });
  }

  test('em列宽重排后两侧auto外边距重新居中', () async {
    final source = await _open(extraCss: '.caption {margin:0 auto;}');
    final page = (await source.loadChapter(0)).single;
    final block = _caption(page);
    final panel = block.containers.last.container;
    final lines = TextHitTester.lineBoxes(page)
        .where((line) => identical(line.slice.block, block))
        .toList();
    expect(block.layout.maxWidth, closeTo(27, .001));
    expect(lines.map((line) => line.text), ['正', '文']);
    for (final line in lines) {
      expect(
        line.rect.center.dx,
        closeTo(panel.contentLeft + panel.contentWidth / 2, .001),
      );
    }
  });

  test('em列宽重排不覆盖作者的nowrap或max-width约束', () async {
    final source = await _open(
      extraCss: '.caption {white-space:nowrap; max-width:24px;}',
    );
    final block = _caption((await source.loadChapter(0)).single);
    expect(block.layout.maxWidth, closeTo(24, .001));
    expect(block.layout.lines, hasLength(1));
    expect(block.layout.text, '正文');
  });
}
