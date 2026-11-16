import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/source/format_opener.dart';
import 'package:reader_core/paint/page_renderer.dart';

import '../audit/audit_epub_fixture.dart';

const _pageSize = Size(384, 853.3333333333334);
const _insets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);
const _width = 366.6666666666667;
const _height = 773.1694444444445;

Future<EpubChapterSource> _open(String body, {String css = ''}) async {
  final source = await const EpubFormatOpener().openBytes(
    auditZip({
      'mimetype': 'application/epub+zip',
      'META-INF/container.xml': '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
      'book.opf':
          '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
          '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">empty-block-margin</dc:identifier>'
          '<dc:title>空块外边距回归</dc:title></metadata><manifest>'
          '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
          '</manifest><spine><itemref idref="c"/></spine></package>',
      'c.xhtml':
          '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
          'body {margin:0 1%;padding:0;font-family:Ahem;line-height:130%;}'
          '.gap {margin:70% auto auto;}'
          'p {margin:1em 10%;font-size:.8em;color:#fff;line-height:130%;text-indent:2em;}'
          '$css</style></head><body>$body</body></html>',
    }),
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

double _textTop(PageContent page, String text) {
  var top = page.topPadding;
  for (final slice in page.slices) {
    if (slice.block.layout.text == text) {
      return top + slice.leadingExtent + slice.textTopTrim;
    }
    if (!slice.overlay) top += slice.height;
  }
  throw StateError('页面未找到测试正文');
}

Future<ByteData> _paint(PageContent page) async {
  final recorder = ui.PictureRecorder();
  const PagePainter(background: Color(0xFF231E3A))
      .paint(Canvas(recorder), page, pageSize: _pageSize, pageInsets: _insets);
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

  test('空标题的百分比上边距按父内容宽保留，正文绘制避开背景书名区域', () async {
    final source = await _open(
      '<h2 class="gap" title="内容简介"></h2><p>INTRO</p>',
    );
    final page = (await source.loadChapter(0)).single;
    final expected = _width * .98 * .7;
    expect(_textTop(page, 'INTRO'), closeTo(expected, .01));
    final pixels = await _paint(page);
    var firstInk = -1;
    for (var y = 0; y < 854 && firstInk < 0; y++) {
      for (var x = 0; x < 384; x++) {
        if (pixels.getUint32((y * 384 + x) * 4) == 0xFFFFFFFF) {
          firstInk = y;
          break;
        }
      }
    }
    expect(firstInk, greaterThanOrEqualTo((_insets.top + expected).floor()));
    expect(firstInk, lessThan(_insets.top + expected + 24));
    final anchor = await source.loadAnchorChapter(0);
    expect(anchor.text, 'INTRO');
    final body = page.slices
        .singleWhere((slice) => slice.block.layout.text == 'INTRO')
        .block;
    expect(anchor.offsetFor(body.cfiAt(0)!), 0, reason: '空盒留白不增加原文字符');
  });

  for (final margins in [
    ('20px 0 30px', 30.0),
    ('-20px 0 -5px', -10.0),
    ('20px 0 -5px', 15.0),
  ]) {
    test('空盒上下边距与相邻段落穿透折叠：${margins.$1}', () async {
      final source = await _open(
        '<div class="empty"></div><p>INTRO</p>',
        css: '.empty {margin:${margins.$1};}',
      );
      final page = (await source.loadChapter(0)).single;
      expect(_textTop(page, 'INTRO'), closeTo(margins.$2, .01));
    });
  }

  test('连续空盒的正负边距按整体极值折叠，不能各自相加', () async {
    final source = await _open(
      '<div class="one"></div><div class="two"></div><p>INTRO</p>',
      css: '.one {margin:50px 0 -20px;} .two {margin:40px 0 -10px;}',
    );
    final page = (await source.loadChapter(0)).single;
    expect(_textTop(page, 'INTRO'), closeTo(30, .01));
  });

  test('隐藏空标题不留白，有内边距的空盒保留独立占位', () async {
    final hidden = await _open(
      '<h2 class="gap" style="display:none;"></h2><p>INTRO</p>',
    );
    final hiddenPage = (await hidden.loadChapter(0)).single;
    final plain = await _open('<p>INTRO</p>');
    final plainPage = (await plain.loadChapter(0)).single;
    expect(_textTop(hiddenPage, 'INTRO'), _textTop(plainPage, 'INTRO'));
    final padded = await _open(
      '<div class="empty"></div><p>INTRO</p>',
      css: '.empty {margin:20px 0 30px;padding:5px 0;}',
    );
    final page = (await padded.loadChapter(0)).single;
    expect(_textTop(page, 'INTRO'), closeTo(60, .01));
  });

  test('空盒与前后正文的边距共同折叠，原有正文高度不改变', () async {
    final source = await _open(
      '<p class="before">BEFORE</p><div class="empty"></div><p>INTRO</p>',
      css:
          '.before {height:40px;margin:0 0 45px;} '
          '.empty {margin:20px 0 -15px;}',
    );
    final page = (await source.loadChapter(0)).single;
    expect(_textTop(page, 'INTRO'), closeTo(40 + 45 - 15, .01));
  });

  test('带框容器里的空盒留白不能吞掉父盒首尾装饰', () async {
    final source = await _open(
      '<div class="panel"><div class="empty"></div><p>INTRO</p></div>',
      css:
          '.panel {padding:8px;border:2px solid red;} '
          '.empty {margin:30px 0 20px;}',
    );
    final page = (await source.loadChapter(0)).single;
    expect(_textTop(page, 'INTRO'), closeTo(10 + 30, .01));
    final body = page.slices.singleWhere(
      (slice) => slice.block.layout.text == 'INTRO',
    );
    expect(body.block.containers, isNotEmpty);
    expect(body.block.containers.last.startsHere, isTrue);
    expect(body.block.containers.last.endsHere, isTrue);
  });
}
