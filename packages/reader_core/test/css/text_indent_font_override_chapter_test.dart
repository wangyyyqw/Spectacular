import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _pageInsets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);
const _contentWidth = 384 - 8.8 - 8.53333333333336;
const _contentHeight = 853.3333333333333 - 56.075 - 24.08888888888893;
const _text =
    '正文首行应当按当前字号缩进两个字，后续各行仍从段落左缘开始。'
    '改变字号之后，首行缩进应同步更新，原文和作者的背景边框保持完整。';

Uint8List _book(String body, String css) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="id"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">text-indent-font-override</dc:identifier>'
      '<dc:title>阅读字号与首行缩进回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
      'html, body { font-size:16px; font-family:builtin_song; } '
      'p { text-align:justify; line-height:130%; margin:.6em 0; } '
      '$css</style></head><body>$body</body></html>',
});

Future<EpubChapterSource> _open(
  String css, {
  String body = '<p>$_text</p>',
}) async {
  final source = await const EpubFormatOpener().openBytes(
    _book(body, css),
    options: const ReaderOpenOptions(
      contentWidth: _contentWidth,
      contentHeight: _contentHeight,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 21, lineHeight: 1.6, paragraphSpacing: 10),
  );
  await source.applyContentSize(
    width: _contentWidth,
    height: _contentHeight,
    topInset: _pageInsets.top,
    sideInsets: (left: _pageInsets.left, right: _pageInsets.right),
  );
  return source;
}

void _expectIndent(PageContent page, double expected) {
  final block = page.slices.single.block;
  expect(block.layout.text, _text);
  expect(block.style!.textIndent, closeTo(expected, .001));
  expect(block.layout.lines.first.indent, closeTo(expected, .001));
  expect(block.layout.lines[1].indent, 0);
  final lines = TextHitTester.lineBoxes(page);
  expect(
    lines.first.rect.left - lines[1].rect.left,
    closeTo(expected, .001),
    reason: '首行与后续行的实际起排位置应相差声明的缩进，不能只更新样式字段',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('builtin_song');
    loader.addFont(
      Future.value(
        ByteData.sublistView(
          File('../../apps/reader_mobile/assets/fonts/MoyuSerif-Regular.otf')
              .readAsBytesSync(),
        ),
      ),
    );
    await loader.load();
  });

  test('真机参数下正文2em缩进随21字号达到42像素', () async {
    final source = await _open('p { text-indent:2em; }');
    final page = (await source.loadChapter(0)).single;
    _expectIndent(page, 42);
    expect(page.slices.single.block.style!.values['text-indent'], '2em');
  });

  test('切换字号后缩进同步更新，恢复字号不重复缩放', () async {
    final source = await _open('p { text-indent:2em; }');
    for (final fontSize in [17.0, 25.0, 21.0, null]) {
      await source.applyOverrides(
        ReaderOverrides(
          fontSize: fontSize,
          lineHeight: 1.6,
          paragraphSpacing: 10,
        ),
      );
      _expectIndent((await source.loadChapter(0)).single, 2 * (fontSize ?? 16));
    }
  });

  test('局部相对字号的2em缩进只按最终字号计算一次', () async {
    final source = await _open(
      'p.small { font-size:.75em; text-indent:2em; }',
      body: '<p class="small">$_text</p>',
    );
    final page = (await source.loadChapter(0)).single;
    expect(page.slices.single.block.style!.fontSize, 21 * .75);
    _expectIndent(page, 2 * 21 * .75);
  });

  for (final (declaration, expected) in [
    ('37px', 37.0),
    ('2rem', 32.0),
    ('10%', _contentWidth * .1),
    ('4ex', 42.0),
    ('-2em', -42.0),
    ('calc(2em + 5px + 10%)', 42 + 5 + _contentWidth * .1),
  ]) {
    test('$declaration 缩进只更新当前字体相关的长度', () async {
      final source = await _open('p { text-indent:$declaration; }');
      _expectIndent((await source.loadChapter(0)).single, expected);
    });
  }

  for (final declaration in ['', 'p { text-indent:inherit; }']) {
    test('继承的已计算缩进保持父元素长度：$declaration', () async {
      final source = await _open('body { text-indent:2em; } $declaration');
      _expectIndent((await source.loadChapter(0)).single, 32);
    });
  }

  test('更新首行缩进时保留作者背景、内边距和边框尺寸', () async {
    final source = await _open('''
p { text-indent:2em; padding:1em; border:2px solid #334455;
  background:#eeeeee; }
''');
    final page = (await source.loadChapter(0)).single;
    _expectIndent(page, 42);
    final style = page.slices.single.block.style!;
    expect(style.padding.left, 16);
    expect(style.borders.left.width, 2);
    expect(style.backgroundColor, const Color(0xFFEEEEEE));
  });
}
