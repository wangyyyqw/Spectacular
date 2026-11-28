import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/line_spans.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _insets = EdgeInsets.fromLTRB(
  8.8,
  22.311111111111124,
  8.53333333333336,
  24.08888888888893,
);
final _longText = List.filled(10, '甲乙丙丁戊己').join();

Uint8List _epub(String body, String css) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package version="3.0" unique-identifier="id" '
      'xmlns="http://www.idpf.org/2007/opf"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">prose-line-fill</dc:identifier>'
      '<dc:title>正文行余量回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="f" href="font.ttf" media-type="font/ttf"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'font.ttf': File('test/fixtures/fonts/NoHaltPunctuation.ttf')
      .readAsBytesSync(),
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
      '@font-face{font-family:Punctuation;src:url(font.ttf);font-weight:300}'
      'body{margin:3% auto 0;padding:3% 3% 5%;font-size:.9em;'
      'font-family:Punctuation;font-weight:300}'
      '.prose,.heading{font-size:.8em;font-weight:300;margin:1em .7em;'
      'text-indent:2em;text-align:left}'
      '.latin{font-family:Ahem}.atom{display:inline-block;width:1em;height:1em}'
      '$css</style></head><body>$body</body></html>',
});

Future<EpubChapterSource> _open(String body, {String css = ''}) async {
  final source = await const EpubFormatOpener().openBytes(
    _epub(body, css),
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

Future<PageContent> _page(String body, {String css = ''}) async =>
    (await (await _open(body, css: css)).loadChapter(0)).single;

TextPainter _painter(PageLineBox box) {
  final block = box.slice.block;
  return TextPainter(
    text: buildLineSpan(
      layout: block.layout,
      line: block.layout.lines[box.lineIndex],
      baseStyle: TextLayoutEngine.textStyleFor(block.style!),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
}

void _expectFilledLine(PageLineBox box) {
  final block = box.slice.block;
  final line = block.layout.lines[box.lineIndex];
  final painter = _painter(box);
  expect(line.justifyExtra, greaterThan(0));
  final gapCount = line.spacing!.justifyGaps.length;
  expect(gapCount, greaterThanOrEqualTo(8));
  expect(
    line.justifyExtra / gapCount,
    lessThanOrEqualTo(block.style!.fontSize * .1 + .001),
  );
  expect(painter.width, closeTo(line.advanceWidth, .05));
  expect(painter.width + line.indent, closeTo(block.layout.maxWidth, .1));
  painter.dispose();
}

void _expectCoordinates(PageContent page) {
  for (final box in TextHitTester.lineBoxes(page)) {
    final painter = _painter(box);
    final line = box.slice.block.layout.lines[box.lineIndex];
    final paintOffset = textLineJustifyOffset(line, painter);
    for (var i = 0; i < box.text.length; i++) {
      final rect = TextHitTester.selectionRects(box, i, i + 1).single;
      final painted = painter
          .getBoxesForSelection(
            TextSelection(baseOffset: i, extentOffset: i + 1),
          )
          .single;
      expect(rect.left, closeTo(painted.left + paintOffset, .01));
      expect(rect.right, closeTo(painted.right + paintOffset, .01));
      expect(
        TextHitTester.caretOffset(box, TextPosition(offset: i)).dx,
        closeTo(
          painter.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dx +
              paintOffset,
          .01,
        ),
      );
      expect(
        TextHitTester.hitTest(
          page,
          Offset(box.rect.left + rect.left + .05, box.rect.center.dy),
        )?.charOffset,
        i,
      );
    }
    painter.dispose();
  }
}

Future<void> _expectSavedCfis(
  EpubChapterSource source,
  List<String?> saved,
) async {
  final chapter = await source.loadAnchorChapter(0);
  expect(chapter.text, _longText);
  for (var i = 0; i < saved.length; i++) {
    expect(chapter.cfiAt(i), saved[i]);
    expect(chapter.offsetFor(saved[i]!), i);
  }
}

void _expectNoFill(PageContent page) {
  for (final slice in page.slices) {
    for (final line in slice.block.layout.lines) {
      expect(line.justifyExtra, 0);
    }
  }
}

bool _expectLatinWord(PageLineBox box, Iterable<int> gaps) {
  final word = box.text.indexOf('EPUB');
  if (word < 0) {
    return false;
  }
  expect(gaps.toSet().intersection({word, word + 1, word + 2}), isEmpty);
  expect(
    TextHitTester.selectionRects(box, word, word + 4).single.width,
    closeTo(13.6 * 4, .05),
  );
  return true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('长中文左对齐正文仅填非末行小余量，CSS与原文坐标保持不变', () async {
    final source = await _open('<p class="prose">$_longText</p>');
    final before = await source.loadAnchorChapter(0);
    final saved = [for (var i = 0; i < _longText.length; i++) before.cfiAt(i)];
    final page = (await source.loadChapter(0)).single;
    final block = page.slices.single.block;
    expect(block.style!.textAlign, CssTextAlign.left);
    expect(block.style!.letterSpacing, 0);
    expect(block.style!.wordSpacing, 0);
    expect(block.style!.fontSize, closeTo(13.6, .001));
    expect(block.layout.text, _longText);
    final boxes = TextHitTester.lineBoxes(page);
    expect(boxes.length, greaterThanOrEqualTo(3));
    for (final box in boxes.take(boxes.length - 1)) {
      _expectFilledLine(box);
    }
    expect(block.layout.lines.last.isLastLine, isTrue);
    expect(block.layout.lines.last.justifyExtra, 0);
    _expectCoordinates(page);
    await _expectSavedCfis(source, saved);
  });

  test('补距不拉宽满格标点、标点两侧或英文词内，混排命中同步', () async {
    final body = List.filled(
      4,
      '甲乙丙！丁戊己<span class="latin">EPUB</span>甲乙丙丁戊己',
    ).join();
    final page = await _page('<p class="prose">$body</p>');
    var punctuation = false, english = false, filled = false;
    for (final box in TextHitTester.lineBoxes(page)) {
      final line = box.slice.block.layout.lines[box.lineIndex];
      final gaps = line.spacing!.justifyGaps;
      filled = filled || line.justifyExtra > 0;
      for (var i = 0; i < box.text.length; i++) {
        if (box.text[i] != '！') {
          continue;
        }
        punctuation = true;
        expect(gaps, isNot(contains(i - 1)));
        expect(gaps, isNot(contains(i)));
        expect(
          TextHitTester.selectionRects(box, i, i + 1).single.width,
          closeTo(13.6, .05),
        );
      }
      english = _expectLatinWord(box, gaps) || english;
    }
    expect((punctuation, english, filled), (true, true, true));
    expect(page.slices.single.block.style!.textAlign, CssTextAlign.left);
    expect(page.slices.single.block.style!.letterSpacing, 0);
    _expectCoordinates(page);
  });

  test('祖先或正文显式声明字距、词距、对齐策略时不叠加补距', () async {
    for (final css in [
      'body{letter-spacing:0}',
      '.prose{letter-spacing:.1em}',
      '.prose{letter-spacing:-.01em}',
      'body{word-spacing:normal}',
      'body{text-justify:auto}',
    ]) {
      final page = await _page('<p class="prose">$_longText</p>', css: css);
      expect(page.slices.single.block.style!.textAlign, CssTextAlign.left);
      _expectNoFill(page);
      _expectCoordinates(page);
    }
    final nested = await _page(
      '<p class="prose"><span><span style="letter-spacing:0">'
      '$_longText</span></span></p>',
    );
    _expectNoFill(nested);
    _expectCoordinates(nested);
  });

  test('长行余量过大时不为贴边拉宽字距', () async {
    final page = await _page(
      '<p class="prose">甲乙丙丁戊己甲乙丙丁戊己'
      '<span class="latin">EPUBTEST</span>$_longText</p>',
      css: '.prose{width:220px;text-indent:0}',
    );
    final block = page.slices.single.block;
    final line = block.layout.lines.first;
    expect(line.end - line.start, 12);
    expect(
      (block.layout.maxWidth - line.width) / 11,
      greaterThan(block.style!.fontSize * .1),
    );
    expect(line.justifyExtra, 0);
  });

  test('标题、题记硬换行、短段及特殊行内结构不补距', () async {
    for (final body in [
      '<h2 class="heading">$_longText</h2>',
      '<p class="prose">甲乙丙丁戊己<br/>$_longText</p>',
      '<p class="prose">甲乙丙丁戊己</p>',
      '<p class="prose">$_longText<span class="atom">甲</span>$_longText</p>',
      '<p class="prose"><ruby>甲<rt>乙</rt></ruby>$_longText</p>',
      '<p class="prose" style="initial-letter:2">$_longText</p>',
    ]) {
      final page = await _page(body);
      _expectNoFill(page);
      if (body.contains('class="atom"')) {
        expect(
          page.slices
              .expand((slice) => slice.block.layout.lines)
              .expand((line) => line.inlineBoxes),
          isNotEmpty,
        );
      }
      if (body.contains('<ruby>')) {
        expect(
          page.slices.any((slice) => slice.block.rubies?.isNotEmpty ?? false),
          isTrue,
        );
      }
      if (body.contains('initial-letter:2')) {
        expect(
          page.slices.any(
            (slice) => slice.block.style?.initialLetterLines == 2,
          ),
          isTrue,
        );
      }
    }
  });
}
