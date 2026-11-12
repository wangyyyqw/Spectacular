import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _pageInsets = EdgeInsets.fromLTRB(
  8.8,
  22.311111111111124,
  8.53333333333336,
  24.08888888888893,
);
const _padding = 4.284;

Uint8List _epubBytes(String align, String extraCss, String subtitle) =>
    auditZip({
      'mimetype': 'application/epub+zip',
      'META-INF/container.xml':
          '<container><rootfiles><rootfile full-path="book.opf"/>'
          '</rootfiles></container>',
      'book.opf':
          '<package version="3.0" unique-identifier="id" '
          'xmlns="http://www.idpf.org/2007/opf"><metadata '
          'xmlns:dc="http://purl.org/dc/elements/1.1/">'
          '<dc:identifier id="id">centered-inline-padding</dc:identifier>'
          '<dc:title>行末内边距对齐回归</dc:title></metadata><manifest>'
          '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
          '<item id="font" href="font.ttf" media-type="font/ttf"/>'
          '</manifest><spine><itemref idref="c"/></spine></package>',
      'font.ttf': File('test/fixtures/fonts/MissingControlGlyphs.ttf')
          .readAsBytesSync(),
      'c.xhtml':
          '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
          '@font-face {font-family:ControlFallback; src:url(font.ttf);}'
          'body { margin:0 1%; font-family:ControlFallback, 黑体, sans-serif; '
          'line-height:130%; }'
          'h1 { font-weight:900; font-size:1.2em; line-height:180%; '
          'margin:1% 0 2em; text-align:$align; $extraCss }'
          'span { font-size:.7em; padding:.3em; }'
          '.tail { font-size:1em; padding:0 .3em 0 0; }'
          '</style></head><body><h1>题<br/>记<br/> '
          '$subtitle</h1></body></html>',
    });

Future<PageContent> _page(
  String align, {
  String extraCss = '',
  String subtitle = '<span>扰尘埃</span>',
}) async {
  final bytes = _epubBytes(align, extraCss, subtitle);
  final source = await const EpubFormatOpener().openBytes(
    bytes,
    options: const ReaderOpenOptions(
      contentWidth: 366.6666666666667,
      contentHeight: 806.9333333333333,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 17, lineHeight: 1.6, paragraphSpacing: 10),
  );
  await source.applyContentSize(
    width: 366.6666666666667,
    height: 806.9333333333333,
    topInset: _pageInsets.top,
    sideInsets: (left: _pageInsets.left, right: _pageInsets.right),
  );
  return (await source.loadChapter(0)).single;
}

Rect _glyphBounds(PageLineBox line) {
  final bounds = TextHitTester.selectionRects(
    line,
    0,
    line.text.length,
  ).reduce((a, b) => a.expandToInclude(b));
  return bounds.shift(Offset(line.rect.left + _pageInsets.left, 0));
}

void _expectAdvance(PageContent page, {double trailing = _padding}) {
  final lines = TextHitTester.lineBoxes(page);
  expect(lines.map((line) => line.text), ['题', '记', '扰尘埃']);
  final layout = page.slices.single.block.layout;
  final glyph = _glyphBounds(lines.last);
  expect(
    layout.lines.last.width,
    closeTo(glyph.width + _padding + trailing, .01),
    reason: '行宽应等于文字与两侧 padding 的总 advance',
  );
  expect(layout.lines.last.ellipsized, isFalse);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // 与手机一致的默认黑体，供自建子集字库缺失的占位字符回退。
    final loader = FontLoader('builtin_hei');
    for (final weight in ['Regular', 'Bold']) {
      loader.addFont(
        Future.value(
          ByteData.sublistView(
            File(
              '../../apps/reader_mobile/assets/fonts/SourceHanSansSC-$weight.otf',
            ).readAsBytesSync(),
          ),
        ),
      );
    }
    await loader.load();
  });

  for (final align in ['center', 'right', 'left']) {
    test('缺控制字形的子集字体：$align 按真实行内占宽对齐', () async {
      final page = await _page(align);
      _expectAdvance(page);
      final lines = TextHitTester.lineBoxes(page);
      final run = page.slices.single.block.layout.runs
          .where((run) => !run.syntheticFontFallback)
          .single;
      expect(run.style.fontFamily, contains('ControlFallback'));
      expect(run.style.fontSize, closeTo(14.28, .001));
      expect(run.leadingInset, closeTo(_padding, .001));
      expect(run.trailingInset, closeTo(_padding, .001));
      final first = _glyphBounds(lines.first);
      final last = _glyphBounds(lines.last);
      switch (align) {
        case 'center':
          expect(last.center.dx, closeTo(first.center.dx, .01));
        case 'right':
          expect(last.right + _padding, closeTo(first.right, .01));
        case 'left':
          expect(last.left - _padding, closeTo(first.left, .01));
      }
    });
  }

  test('60px 的 nowrap 行保留可容纳的完整副题', () async {
    final page = await _page(
      'center',
      extraCss:
          'width:60px; white-space:nowrap; '
          'overflow:hidden; text-overflow:ellipsis;',
    );
    _expectAdvance(page);
    expect(page.slices.single.block.layout.maxWidth, closeTo(60, .01));
  });

  test('嵌套尾侧内边距按总 advance 占宽', () async {
    final page = await _page(
      'center',
      subtitle: '<span><span class="tail">扰尘埃</span></span>',
    );
    _expectAdvance(page, trailing: _padding * 2);
    final lines = TextHitTester.lineBoxes(page);
    expect(
      _glyphBounds(lines.last).center.dx,
      closeTo(_glyphBounds(lines.first).center.dx - _padding / 2, .01),
    );
  });
}
