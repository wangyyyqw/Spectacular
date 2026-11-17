import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _text = '甲乙　题记扰尘埃';
const _width = 366.6666666666667;
const _height = 773.1694444444443;
const _insets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);

Uint8List _epub(String extraCss, {bool padding = true}) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
  'book.opf':
      '<package version="3.0" unique-identifier="id" xmlns="http://www.idpf.org/2007/opf">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">inline-font-boundary</dc:identifier>'
      '<dc:title>行内字体切换回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="base" href="base.ttf" media-type="font/ttf"/>'
      '<item id="inline" href="inline.ttf" media-type="font/ttf"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'base.ttf': File('test/fixtures/fonts/EmptyNotdefSubset.ttf')
      .readAsBytesSync(),
  'inline.ttf': File('test/fixtures/fonts/NoHaltPunctuation.ttf')
      .readAsBytesSync(),
  'c.xhtml':
      '<html><head><style>'
      '@font-face{font-family:BaseSubset;src:url(base.ttf)}'
      '@font-face{font-family:InlineSubset;src:url(inline.ttf)}'
      'body{margin:0}h1{font-family:BaseSubset,MissingSecondFamily;'
      'font-size:1.3em;font-weight:700;line-height:1.3em;margin:0;$extraCss}'
      'span{font-family:InlineSubset;padding:${padding ? '.1em .2em' : '0'};'
      'background:#932700;color:white}'
      '</style></head><body><h1><span>甲乙</span>　题记扰尘埃</h1></body></html>',
});

Future<EpubChapterSource> _open(String css, {bool padding = true}) async {
  final source = await const EpubFormatOpener().openBytes(
    _epub(css, padding: padding),
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
    topInset: _insets.top,
    sideInsets: (left: _insets.left, right: _insets.right),
  );
  return source;
}

Future<void> _paint(PageContent page) async {
  final recorder = ui.PictureRecorder();
  const PagePainter().paint(
    Canvas(recorder),
    page,
    pageSize: const Size(384, 853.3333333333334),
    pageInsets: _insets,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(384, 853);
  expect(await image.toByteData(), isNotNull);
  image.dispose();
  picture.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final align in ['left', 'center', 'right']) {
    test('空缺字轮廓与跨字体内边距：$align 可测量、绘制并保持原文位置', () async {
      final source = await _open('text-align:$align');
      final before = await source.loadAnchorChapter(0);
      final cfis = [for (var i = 0; i < _text.length; i++) before.cfiAt(i)];
      final page = (await source.loadChapter(0)).single;
      final plain = (await (await _open(
        'text-align:$align',
        padding: false,
      )).loadChapter(0)).single;
      final layout = page.slices.single.block.layout;
      expect(layout.text, _text);
      expect(layout.lines, hasLength(1));
      expect(
        layout.lines.single.height,
        closeTo(plain.slices.single.block.layout.lines.single.height, .01),
      );
      expect(
        layout.lines.single.width -
            plain.slices.single.block.layout.lines.single.width,
        closeTo(23.4 * .4, .01),
      );
      final line = TextHitTester.lineBoxes(page).single;
      for (var i = 0; i < _text.length; i++) {
        final rect = TextHitTester.selectionRects(line, i, i + 1).single;
        expect(rect.width, closeTo(23.4, .01));
        expect(
          TextHitTester.hitTest(
            page,
            Offset(rect.left + .1, rect.center.dy) + line.rect.topLeft,
          )?.charOffset,
          i,
        );
      }
      await _paint(page);
      final after = await source.loadAnchorChapter(0);
      expect(after.text, _text);
      for (var i = 0; i < cfis.length; i++) {
        expect(after.cfiAt(i), cfis[i]);
        expect(after.offsetFor(cfis[i]!), i);
      }
    });
  }

  test('跨字体的左右内边距仅在首尾占宽，窄行仍可换行和绘制', () async {
    final source = await _open('text-align:left;width:80px;');
    final page = (await source.loadChapter(0)).single;
    final lines = TextHitTester.lineBoxes(page);
    expect(lines.length, greaterThan(1));
    expect(lines.map((line) => line.text).join(), _text);
    expect(
      page.slices.single.block.layout.lines.expand((line) => line.inlineBoxes),
      hasLength(2),
    );
    await _paint(page);
  });
}
