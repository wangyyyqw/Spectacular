import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/line_spans.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _text = '甲，乙“丙”丁！戊。';
const _insets = EdgeInsets.fromLTRB(
  8.8,
  22.311111111111124,
  8.53333333333336,
  24.08888888888893,
);

Uint8List _epub(String css, String text) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package version="3.0" unique-identifier="id" '
      'xmlns="http://www.idpf.org/2007/opf"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">punctuation-fallback</dc:identifier>'
      '<dc:title>无 halt 字体回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="f" href="font.ttf" media-type="font/ttf"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'font.ttf': File('test/fixtures/fonts/NoHaltPunctuation.ttf')
      .readAsBytesSync(),
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
      '@font-face{font-family:Punctuation;src:url(font.ttf);font-weight:300}'
      'body{margin:3% auto 0;padding:3% 3% 5%;font-size:.9em}'
      'p.prose{font-family:Punctuation;font-weight:300;font-size:.8em;'
      'margin:1em .7em;text-indent:0;text-align:left;color:black;$css}'
      '</style></head><body><p class="prose">$text</p></body></html>',
});

Future<EpubChapterSource> _open(String css, {String text = _text}) async {
  final source = await const EpubFormatOpener().openBytes(
    _epub(css, text),
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
    topInset: _insets.top,
    sideInsets: (left: _insets.left, right: _insets.right),
  );
  return source;
}

Future<PageContent> _page(String css, {String text = _text}) async =>
    (await (await _open(css, text: text)).loadChapter(0)).single;

void _expectCoordinates(PageContent page) {
  final hitLine = TextHitTester.lineBoxes(page).single;
  final block = hitLine.slice.block;
  final line = block.layout.lines.single;
  final painter = TextPainter(
    text: buildLineSpan(
      layout: block.layout,
      line: line,
      baseStyle: TextLayoutEngine.textStyleFor(block.style!),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  expect(painter.width, closeTo(line.advanceWidth, .05));
  for (var i = 0; i < _text.length; i++) {
    _expectGlyphCoordinates(page, hitLine, painter, i);
  }
  painter.dispose();
}

void _expectGlyphCoordinates(
  PageContent page,
  PageLineBox hitLine,
  TextPainter painter,
  int i,
) {
  final selected = TextHitTester.selectionRects(hitLine, i, i + 1).single;
  final painted = painter
      .getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1))
      .single;
  expect(selected.left, closeTo(painted.left, .01));
  expect(selected.right, closeTo(painted.right, .01));
  expect(
    TextHitTester.caretOffset(hitLine, TextPosition(offset: i)).dx,
    closeTo(
      painter.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dx,
      .01,
    ),
  );
  expect(
    TextHitTester.hitTest(
      page,
      Offset(hitLine.rect.left + selected.left + .05, hitLine.rect.center.dy),
    )?.charOffset,
    i,
  );
}

Future<List<Rect>> _inkBands(PageContent page) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(4);
  const PagePainter().paint(
    canvas,
    page,
    pageSize: const Size(384, 853.3333333333334),
    pageInsets: _insets,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(1536, 512);
  final bytes = (await image.toByteData())!;
  final bands = <Rect>[];
  for (var x = 0; x < 1536; x++) {
    final column = _inkColumn(bytes, x);
    if (column == null) {
      continue;
    }
    if (bands.isNotEmpty && bands.last.right == x) {
      bands[bands.length - 1] = bands.last.expandToInclude(column);
    } else {
      bands.add(column);
    }
  }
  image.dispose();
  picture.dispose();
  return bands;
}

Rect? _inkColumn(ByteData bytes, int x) {
  var top = 512, bottom = -1;
  for (var y = 0; y < 512; y++) {
    final offset = (y * 1536 + x) * 4;
    if (bytes.getUint8(offset + 3) > 100 &&
        bytes.getUint8(offset) < 100 &&
        bytes.getUint8(offset + 1) < 100 &&
        bytes.getUint8(offset + 2) < 100) {
      if (y < top) {
        top = y;
      }
      bottom = y;
    }
  }
  if (bottom < top) {
    return null;
  }
  return Rect.fromLTRB(x.toDouble(), top.toDouble(), x + 1.0, bottom + 1.0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('无 halt 字体只回收安全留白，绘制与原文坐标保持一致', () async {
    final source = await _open('');
    final anchorBefore = await source.loadAnchorChapter(0);
    final saved = [
      for (var i = 0; i < _text.length; i++) anchorBefore.cfiAt(i),
    ];
    final page = (await source.loadChapter(0)).single;
    final block = page.slices.single.block;
    final glyphs = block.layout.lines.single.spacing!.glyphs;
    expect(block.style!.fontSize, closeTo(13.6, .001));
    expect(glyphs.keys, containsAll([1, 3, 5, 9]));
    expect(glyphs.containsKey(7), isFalse, reason: '满格叹号没有可安全回收的留白');
    for (final glyph in glyphs.values) {
      expect(glyph.halfWidth, isFalse);
      expect(glyph.reduction, greaterThan(0));
      expect(glyph.reduction, lessThanOrEqualTo(13.6 * .32 + .001));
      expect(glyph.letterSpacing, closeTo(-glyph.reduction, .001));
    }
    expect(block.layout.text, _text);
    _expectCoordinates(page);
    final anchorAfter = await source.loadAnchorChapter(0);
    expect(anchorAfter.text, _text);
    for (var i = 0; i < saved.length; i++) {
      expect(anchorAfter.cfiAt(i), saved[i]);
      expect(anchorAfter.offsetFor(saved[i]!), i);
    }
  });

  test('压缩前后矩形墨迹尺寸不变，相邻字符仍分离', () async {
    final trimmed = await _inkBands(await _page(''));
    final plain = await _inkBands(await _page('text-spacing-trim:space-all;'));
    expect(trimmed, hasLength(_text.length));
    expect(plain, hasLength(_text.length));
    expect(trimmed.last.left, lessThan(plain.last.left));
    for (var i = 0; i < _text.length; i++) {
      expect(trimmed[i].width, closeTo(plain[i].width, 1));
      expect(trimmed[i].height, closeTo(plain[i].height, 1));
      if (i > 0) {
        expect(trimmed[i].left, greaterThan(trimmed[i - 1].right));
      }
    }
  });

  test('安全压缩参与实际断行，不只改变绘制位置', () async {
    const text = '甲，乙甲，乙';
    final trimmed = await _page('width:77px;', text: text);
    final plain = await _page(
      'width:77px;text-spacing-trim:space-all;',
      text: text,
    );
    expect(trimmed.slices.single.block.layout.lines, hasLength(1));
    expect(plain.slices.single.block.layout.lines, hasLength(2));
    expect(trimmed.slices.single.block.layout.text, text);
    expect(
      trimmed.slices.single.block.layout.lines.single.width,
      lessThanOrEqualTo(77),
    );
  });

  test('作者 space-all 保留整格占宽和既有命中位置', () async {
    final page = await _page('text-spacing-trim:space-all;');
    final layout = page.slices.single.block.layout;
    expect(layout.lines.single.spacing!.glyphs, isEmpty);
    expect(layout.lines.single.width, closeTo(_text.length * 13.6, .05));
    expect(layout.text, _text);
    _expectCoordinates(page);
  });

  test('作者显式字体特性或负字距不再叠加回退压缩', () async {
    for (final css in [
      'font-feature-settings:"halt" 0;',
      'letter-spacing:-.01em;',
    ]) {
      final page = await _page(css);
      final layout = page.slices.single.block.layout;
      expect(layout.lines.single.spacing!.glyphs, isEmpty, reason: css);
      expect(layout.text, _text);
      _expectCoordinates(page);
    }
  });
}
