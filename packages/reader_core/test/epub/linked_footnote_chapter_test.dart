import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _contentWidth = 366.6666666666667;
const _contentHeight = 773.1694444444443;
const _pageSize = Size(384, 853.3333333333333);
const _insets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);

Uint8List _book(String body) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package version="2.0" unique-identifier="id">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">linked-footnotes</dc:identifier>'
      '<dc:title>双向链接注释回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html><head><style>'
      'h1 {font-size:1.5em;line-height:1.2em;text-align:center;'
      'margin:1.5em 0 1em;}'
      'h1 a {color:#C74331;}'
      'p {font-size:1em;text-indent:2em;}'
      '.raised {font-size:.7em;vertical-align:super;}'
      '</style></head><body>$body</body></html>',
});

Future<List<PageContent>> _pages(String body) async {
  final source = await const EpubFormatOpener().openBytes(
    _book(body),
    options: const ReaderOpenOptions(
      contentWidth: _contentWidth,
      contentHeight: _contentHeight,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 21, lineHeight: 1.6, paragraphSpacing: 10),
  );
  return source.loadChapter(0);
}

/// 从正式绘制的标题注号墨迹定位点击点，不从待验证的命中矩形反推。
Future<Offset> _paintedTitleNoteCenter(PageContent page) async {
  final recorder = ui.PictureRecorder();
  PagePainter().paint(
    Canvas(recorder),
    page,
    pageSize: _pageSize,
    pageInsets: _insets,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(384, 854);
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    var bounds = Rect.zero;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final offset = (y * image.width + x) * 4;
        if (bytes.getUint8(offset) > 150 &&
            bytes.getUint8(offset + 1) < 110 &&
            bytes.getUint8(offset + 2) < 110) {
          final pixel = Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1);
          bounds = bounds.isEmpty ? pixel : bounds.expandToInclude(pixel);
        }
      }
    }
    expect(bounds.isEmpty, isFalse, reason: '标题注号必须实际绘制');
    return bounds.center - Offset(_insets.left, _insets.top);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('标题和正文的前置空锚点配对数字回链可读取注文，定义不进入正文', () async {
    final pages = await _pages(
      '<h1>自序<a id="reference-a"></a><a href="#definition-a">'
      '<span class="raised">[1]</span></a></h1>'
      '<p>正文<a id="reference-b"></a><a href="#definition-b">'
      '<span class="raised">[2]</span></a>继续正文。</p>'
      '<p><a id="definition-a"></a><a href="#reference-a">[1]</a> '
      '标题注释正文。</p>'
      '<p><a id="definition-b"></a><a href="#reference-b">[2]</a> '
      '段内注释正文。</p>',
    );
    final blocks = pages
        .expand((page) => page.slices)
        .map((slice) => slice.block);
    final notes = blocks.expand((block) => block.footnotes).toList();
    expect(notes.map((note) => note.text), ['标题注释正文。', '段内注释正文。']);
    expect(
      blocks.map((block) => block.layout.text).join('\n'),
      '自序[1]\n正文[2]继续正文。',
    );
    expect(
      TextHitTester.footnoteAt(
        pages.first,
        await _paintedTitleNoteCenter(pages.first),
      ),
      same(notes.first),
    );
  });

  test('正文区块之间的数字往返链接保留正文，不生成注释', () async {
    final pages = await _pages(
      '<p>第一段<a id="section-a"></a><a href="#section-b">[1]</a></p>'
      '<p>第二段<a id="section-b"></a><a href="#section-a">[1]</a></p>'
      '<p><a href="#plain-section">2</a></p>'
      '<section id="plain-section"><p>普通章节正文。</p></section>',
    );
    final blocks = pages
        .expand((page) => page.slices)
        .map((slice) => slice.block);
    expect(blocks.expand((block) => block.footnotes), isEmpty);
    expect(
      blocks.map((block) => block.layout.text),
      containsAll(['第一段[1]', '第二段[1]', '普通章节正文。']),
    );
  });
}
