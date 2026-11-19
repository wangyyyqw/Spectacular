import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _dialogue =
    '“你已经死了，但我希望你到我的世界里来，把魔王给打倒，'
    '所以我打算将你复活，让你成为勇者，前往剑与魔法的世界。”';

Uint8List _epub(String body, String css) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
  'book.opf':
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">inline-line-height</dc:identifier></metadata>'
      '<manifest><item id="c" href="c.xhtml" media-type="application/xhtml+xml"/></manifest>'
      '<spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
      'body { margin:0 1%; line-height:130%; font-family:S1CJK; }'
      'p { text-align:justify; text-indent:2em; line-height:130%; margin:1em 1%; }'
      'span.dialogue { font-size:.9em; line-height:90%; color:#5f137e; margin:0 1%; }'
      '$css</style></head><body>$body</body></html>',
});

Future<EpubChapterSource> _open({
  String body = '<p><span class="dialogue">$_dialogue</span></p>',
  String css = '',
  double width = 366.6666666666667,
  double? lineHeight = 1.6,
}) async {
  final source = await const EpubFormatOpener().openBytes(
    _epub(body, css),
    options: ReaderOpenOptions(
      contentWidth: width,
      contentHeight: 773.1694444444444,
    ),
  );
  addTearDown(() async {
    source.close();
    await source.preparationsStopped;
  });
  await source.applyOverrides(
    ReaderOverrides(fontSize: 18, lineHeight: lineHeight, paragraphSpacing: 10),
  );
  return source;
}

void _expectStrut(PageBlock block, double height) {
  final layout = block.layout;
  expect(layout.lines.length, greaterThan(1));
  for (final line in layout.lines) {
    expect(line.height, closeTo(height, .001));
  }
  for (var i = 1; i < layout.lines.length; i++) {
    expect(
      layout.lines[i].baseline - layout.lines[i - 1].baseline,
      closeTo(height, .001),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final bytes = await File('../../test_fonts/SourceHanSerifSC-Regular.otf')
        .readAsBytes();
    await (FontLoader(
      'S1CJK',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });

  for (final width in [294.0, 366.6666666666667]) {
    test('整段小行高 span 在 $width 宽度仍保留段落最小行高与命中位置', () async {
      final source = await _open(width: width);
      final page = (await source.loadChapter(0)).single;
      final block = page.slices.single.block;
      _expectStrut(block, 28.8);
      expect(block.layout.text, _dialogue);
      final run = block.layout.runs.first;
      expect(run.style.fontSize, closeTo(16.2, .001));
      expect(run.style.lineHeight, closeTo(14.58, .001));
      expect(run.style.color.toARGB32(), 0xff5f137e);
      final boxes = TextHitTester.lineBoxes(page).toList();
      for (var i = 1; i < boxes.length; i++) {
        expect(
          boxes[i].rect.top,
          greaterThanOrEqualTo(boxes[i - 1].rect.bottom - .001),
        );
        final hit = TextHitTester.hitTest(page, boxes[i].rect.center);
        expect(hit?.lineIndex, i);
      }
    });
  }

  test('未覆盖阅读行高时保留作者段落的百分比行高', () async {
    final source = await _open(lineHeight: null);
    // 作者百分比先在原始 16px 正文字号下计算；只改阅读字号不重算此绝对值。
    _expectStrut(
      (await source.loadChapter(0)).single.slices.single.block,
      20.8,
    );
  });

  test('normal 段落同样保留自身字体度量，不被整段小行高覆盖', () async {
    final source = await _open(
      body: '<p>正文<br/>正文</p><p><span class="dialogue">小字<br/>小字</span></p>',
      css: 'p { line-height:normal; }',
      lineHeight: null,
    );
    final slices = (await source.loadChapter(0)).single.slices;
    final reference = slices.first.block.layout.lines.first;
    final small = slices.last.block.layout.lines.first;
    expect(small.height, closeTo(reference.height, .001));
    expect(small.baseline, closeTo(reference.baseline, .001));
  });

  test('混排行保留较大的行内行高，邻近纯小字行仍遵守段落下限', () async {
    final source = await _open(
      body: '<p><span class="dialogue">第一行<br/><b>大行高</b><br/>第三行</span></p>',
      css: 'b { font-size:1em; line-height:3; }',
    );
    final lines = (await source.loadChapter(0))
        .single
        .slices
        .single
        .block
        .layout
        .lines;
    expect(lines, hasLength(3));
    expect(lines[0].height, closeTo(28.8, .001));
    expect(lines[1].height, greaterThanOrEqualTo(48.6));
    expect(lines[2].height, closeTo(28.8, .001));
  });

  test('阅读行高重排保留原文与 CFI', () async {
    final source = await _open();
    final before = await source.loadAnchorChapter(0);
    final cfi = before.cfiAt(12)!;
    await source.loadChapter(0);
    await source.applyOverrides(
      const ReaderOverrides(fontSize: 18, lineHeight: 1.8),
    );
    _expectStrut(
      (await source.loadChapter(0)).single.slices.single.block,
      32.4,
    );
    final after = await source.loadAnchorChapter(0);
    expect(after.text, before.text);
    expect(after.cfiAt(12), cfi);
    expect(after.offsetFor(cfi), 12);
  });
}
