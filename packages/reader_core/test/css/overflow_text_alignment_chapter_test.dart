import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _pageSize = Size(384, 853.3333333333333);
const _pageInsets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);
const _contentWidth = 384 - 8.8 - 8.53333333333336;
const _contentHeight = 853.3333333333333 - 56.075 - 24.08888888888893;
const _titleCss = '''
html, body { font-size:16px; }
h1 { font-family:builtin_hei; font-size:1em; width:1.1em;
  text-align:center; margin:-5.5em auto 2em;
  padding:5em .1em 4em; color:#fff; background-color:#000; }
''';

Future<EpubChapterSource> _open({
  String extraCss = '',
  String title = '内容简介',
}) async {
  final source = await const EpubFormatOpener().openBytes(
    auditZip({
      'mimetype': 'application/epub+zip',
      'META-INF/container.xml':
          '<container><rootfiles><rootfile full-path="book.opf"/>'
          '</rootfiles></container>',
      'book.opf':
          '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
          'unique-identifier="id"><metadata '
          'xmlns:dc="http://purl.org/dc/elements/1.1/">'
          '<dc:identifier id="id">overflow-text-alignment</dc:identifier>'
          '<dc:title>窄背景文字对齐回归</dc:title></metadata><manifest>'
          '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
          '</manifest><spine><itemref idref="c"/></spine></package>',
      'c.xhtml':
          '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
          '<style>$_titleCss$extraCss</style></head><body>'
          '<div><br/></div><h1>$title</h1>'
          '<p>相邻正文保持完整。</p></body></html>',
    }),
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

List<PageLineBox> _titleLines(PageContent page) => TextHitTester.lineBoxes(page)
    .where(
      (line) =>
          line.slice.block.style?.backgroundColor == const Color(0xFF000000),
    )
    .toList();

void _expectCentered(PageContent page, double fontSize) {
  final lines = _titleLines(page);
  expect(lines.map((line) => line.text), ['内', '容', '简', '介']);
  final block = lines.first.slice.block;
  expect(block.style!.fontSize, fontSize);
  expect(block.layout.maxWidth, closeTo(16 * 1.1, .001));
  expect(block.style!.padding.horizontal, closeTo(16 * .2, .001));
  for (final line in lines) {
    expect(
      line.rect.center.dx,
      closeTo(_contentWidth / 2, .001),
      reason: '单字宽于内容盒时仍应与背景同中心，不能退回左侧起排',
    );
  }
  expect(page.slices.last.block.layout.text, '相邻正文保持完整。');
}

Future<ByteData> _render(PageContent page) async {
  final recorder = ui.PictureRecorder();
  const PagePainter().paint(
    Canvas(recorder),
    page,
    pageSize: _pageSize,
    pageInsets: _pageInsets,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(384, 854);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('builtin_hei');
    for (final weight in ['Regular', 'Bold']) {
      loader.addFont(
        Future.value(
          ByteData.sublistView(
            File('../../test_fonts/SourceHanSansSC-$weight.otf')
                .readAsBytesSync(),
          ),
        ),
      );
    }
    await loader.load();
  });

  test('真机页宽与21字号下窄背景标题的四个字保持居中', () async {
    final page = (await (await _open()).loadChapter(0)).single;
    _expectCentered(page, 21);
  });

  test('窄背景中的白字与宽背景中的完整字形一致', () async {
    final source = await _open();
    final reference = await _open(
      extraCss: 'h1 { width:4em; }',
      title: '内<br/>容<br/>简<br/>介',
    );
    final page = (await source.loadChapter(0)).single;
    final referencePage = (await reference.loadChapter(0)).single;
    final pixels = await _render(page);
    final fullGlyphs = await _render(referencePage);
    final lines = _titleLines(referencePage);
    var differences = 0;
    for (final line in lines) {
      final rect = line.rect.shift(Offset(_pageInsets.left, _pageInsets.top));
      for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
        for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
          final offset = (y * 384 + x) * 4;
          if ((pixels.getUint8(offset) - fullGlyphs.getUint8(offset)).abs() >
              3) {
            differences++;
          }
        }
      }
    }
    expect(differences, 0, reason: '白字各笔画与留白均应完整，不能向右偏出黑底');
  });

  test('放大、缩小和恢复字号不改变作者盒宽或文字中心', () async {
    final source = await _open();
    for (final fontSize in [25.0, 12.0, 21.0]) {
      await source.applyOverrides(
        ReaderOverrides(
          fontSize: fontSize,
          lineHeight: 1.6,
          paragraphSpacing: 10,
        ),
      );
      _expectCentered((await source.loadChapter(0)).single, fontSize);
    }
  });

  for (final align in ['right', 'end', 'left', 'justify']) {
    test('宽于内容盒的单字保留 $align 对齐且不拉伸', () async {
      final page = (await (await _open(
        extraCss: 'h1 { text-align:$align; }',
      )).loadChapter(0)).single;
      final lines = _titleLines(page);
      final style = lines.first.slice.block.style!;
      final contentLeft = style.margin.left + style.padding.left;
      for (final line in lines) {
        final right = align == 'right' || align == 'end';
        expect(
          right ? line.rect.right : line.rect.left,
          closeTo(contentLeft + (right ? 16 * 1.1 : 0), .001),
        );
        expect(line.slice.block.layout.lines[line.lineIndex].justifyExtra, 0);
      }
    });
  }

  test('末行单独声明居中时也允许负的对齐偏移', () async {
    final page = (await (await _open(
      extraCss: 'h1 { text-align:left; text-align-last:center; }',
    )).loadChapter(0)).single;
    final lines = _titleLines(page);
    expect(lines.last.rect.center.dx, closeTo(_contentWidth / 2, .001));
    expect(lines.first.rect.left, greaterThan(lines.last.rect.left));
  });
}
